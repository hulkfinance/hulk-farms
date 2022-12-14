// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "./abstract/Ownable.sol";
import "./libs/SafeMath.sol";
import "./libs/SafeERC20.sol";
import "./interface/IBEP20.sol";
import "./HULKToken.sol";
import "./abstract/ReentrancyGuard.sol";
import "./interface/IHULKReferral.sol";

// MasterChef is the master of HULK. He can make HULK and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once HULK is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract HULKMasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;           // How many LP tokens the user has provided.
        uint256 rewardDebt;       // Reward debt. See explanation below.
        uint256 rewardLockedUp;   // Reward locked up.
        uint256 nextHarvestUntil; // When can the user harvest again.
        //
        // We do some fancy math here. Basically, any point in time, the amount of HULK
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accHULKPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accHULKPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.

    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;             // Address of LP token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. HULK to distribute per block.
        uint256 lastRewardBlock;    // Last block number that HULK distribution occurs.
        uint256 accHULKPerShare;    // Accumulated HULK per share, times 1e12. See below.
        uint16 depositFeeBP;        // Deposit fee in basis points
        uint256 harvestInterval;    // Harvest interval in seconds
        uint256 totalLp;            // Total Token in Pool
    }

    // The HULK TOKEN!
    HULKToken public hulk;
    // The operator can only update EmissionRate and AllocPoint to protect tokenomics
    //i.e some wrong setting and a pools get too much allocation accidentally
    address private _operator;
    // Dev address.
    address public devAddress;
    // Deposit Fee address
    address public feeAddress;
    // HULK tokens created per block.
    uint256 public hulkPerBlock;
    uint256 public constant MAX_HULK_PER_BLOCK = 2000 * 10 ** 18;
    // Bonus multiplier for early hulk makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Max harvest interval: 14 days.
    uint256 public constant MAXIMUM_HARVEST_INTERVAL = 14 days;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when HULK mining starts.
    uint256 public startBlock;
    // Total locked up rewards
    uint256 public totalLockedUpRewards;
    // Total HULK in HULK Pools (can be multiple pools)
    uint256 public totalHULKInPools = 0;
    // HULK referral contract address.
    IHULKReferral public hulkReferral;
    // Referral commission rate in basis points.
    uint16 public referralCommissionRate = 300;
    // Max referral commission rate: 10%.
    uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 1000;
    // Maximum deposit fee rate: 10%
    uint16 public constant MAXIMUM_DEPOSIT_FEE_RATE = 1000;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmissionRateUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint256 commissionAmount);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);

    modifier onlyOperator() {
        require(_operator == msg.sender, "Operator: caller is not the operator");
        _;
    }

    constructor(
        HULKToken _hulk,
        uint256 _hulkPerBlock
    ) public {
        //StartBlock always many years later from contract construct, will be set later in StartFarming function
        startBlock = block.number + (10 * 365 * 24 * 60 * 60);

        hulk = _hulk;
        hulkPerBlock = _hulkPerBlock;

        devAddress = msg.sender;
        feeAddress = msg.sender;
        _operator = msg.sender;
        emit OperatorTransferred(address(0), _operator);
    }

    function operator() public view returns (address) {
        return _operator;
    }

    function transferOperator(address newOperator) public onlyOperator {
        require(newOperator != address(0), "TransferOperator: new operator is the zero address");
        emit OperatorTransferred(_operator, newOperator);
        _operator = newOperator;
    }

    // Set farming start, can call only once
    function startFarming() public onlyOwner {
        require(block.number < startBlock, "Error::Farm started already");

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardBlock = block.number;
        }

        startBlock = block.number;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    //actual HULK lef in MasterChef can be used in rewards, must excluding all in hulk pools
    //this function is for safety check only not used anywhere
    function remainRewards() external view returns (uint256) {
        return hulk.balanceOf(address(this)).sub(totalHULKInPools);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // Can add multiple pool with same lp token without messing up rewards, because each pool's balance is tracked using its own totalLp
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, uint256 _harvestInterval, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= MAXIMUM_DEPOSIT_FEE_RATE, "add: deposit fee too high");
        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "add: invalid harvest interval");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accHULKPerShare : 0,
        depositFeeBP : _depositFeeBP,
        harvestInterval : _harvestInterval,
        totalLp : 0
        }));
    }

    // Update the given pool's HULK allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, uint256 _harvestInterval, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= MAXIMUM_DEPOSIT_FEE_RATE, "set: deposit fee too high");
        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "set: invalid harvest interval");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].harvestInterval = _harvestInterval;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending HULK on frontend.
    function pendingHULK(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accHULKPerShare = pool.accHULKPerShare;
        uint256 lpSupply = pool.totalLp;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 hulkReward = multiplier.mul(hulkPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accHULKPerShare = accHULKPerShare.add(hulkReward.mul(1e12).div(lpSupply));
        }
        uint256 pending = user.amount.mul(accHULKPerShare).div(1e12).sub(user.rewardDebt);
        return pending.add(user.rewardLockedUp);
    }

    // View function to see if user can harvest HULK.
    function canHarvest(uint256 _pid, address _user) public view returns (bool) {
        UserInfo storage user = userInfo[_pid][_user];
        return block.number >= startBlock && block.timestamp >= user.nextHarvestUntil;
    }

    //this function make sure even thousands of pool gas fee is still low because transfer is just 1 time
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        uint256 totalReward = 0;

        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            if (block.number <= pool.lastRewardBlock) {
                continue;
            }

            if (pool.totalLp == 0 || pool.allocPoint == 0) {
                pool.lastRewardBlock = block.number;
                continue;
            }

            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 hulkReward = multiplier.mul(hulkPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

            pool.accHULKPerShare = pool.accHULKPerShare.add(hulkReward.mul(1e12).div(pool.totalLp));
            pool.lastRewardBlock = block.number;

            totalReward.add(hulkReward.div(10));
        }

        safeHULKTransfer(devAddress, totalReward);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.totalLp == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 hulkReward = multiplier.mul(hulkPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        pool.accHULKPerShare = pool.accHULKPerShare.add(hulkReward.mul(1e12).div(pool.totalLp));
        pool.lastRewardBlock = block.number;

        safeHULKTransfer(devAddress, hulkReward.div(10));
    }

    // Deposit LP tokens to MasterChef for HULK allocation.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) public nonReentrant {
        require(block.number >= startBlock, "MasterChef:: Can not deposit before farm start");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (_amount > 0 && address(hulkReferral) != address(0) && _referrer != address(0) && _referrer != msg.sender) {
            hulkReferral.recordReferral(msg.sender, _referrer);
        }
        payOrLockupPendingHULK(_pid);
        if (_amount > 0) {
            uint256 beforeDeposit = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 afterDeposit = pool.lpToken.balanceOf(address(this));

            _amount = afterDeposit.sub(beforeDeposit);

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
                pool.totalLp = pool.totalLp.add(_amount).sub(depositFee);

                if (address(pool.lpToken) == address(hulk)) {
                    totalHULKInPools = totalHULKInPools.add(_amount).sub(depositFee);
                }
            } else {
                user.amount = user.amount.add(_amount);
                pool.totalLp = pool.totalLp.add(_amount);

                if (address(pool.lpToken) == address(hulk)) {
                    totalHULKInPools = totalHULKInPools.add(_amount);
                }
            }
        }
        user.rewardDebt = user.amount.mul(pool.accHULKPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "Withdraw: User amount not enough");
        //this will make sure that user can only withdraw from his pool
        //cannot withdraw more than pool's balance and from MasterChef's token
        require(pool.totalLp >= _amount, "Withdraw: Pool total LP not enough");

        updatePool(_pid);
        payOrLockupPendingHULK(_pid);
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalLp = pool.totalLp.sub(_amount);
            if (address(pool.lpToken) == address(hulk)) {
                totalHULKInPools = totalHULKInPools.sub(_amount);
            }
            pool.lpToken.safeTransfer(address(msg.sender), _amount);

        }
        user.rewardDebt = user.amount.mul(pool.accHULKPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;

        require(pool.totalLp >= amount, "EmergencyWithdraw: Pool total LP not enough");

        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        user.nextHarvestUntil = 0;
        pool.totalLp = pool.totalLp.sub(amount);
        if (address(pool.lpToken) == address(hulk)) {
            totalHULKInPools = totalHULKInPools.sub(amount);
        }
        pool.lpToken.safeTransfer(address(msg.sender), amount);

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Pay or lockup pending HULK.
    function payOrLockupPendingHULK(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.nextHarvestUntil == 0 && block.number >= startBlock) {
            user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);
        }

        uint256 pending = user.amount.mul(pool.accHULKPerShare).div(1e12).sub(user.rewardDebt);
        if (canHarvest(_pid, msg.sender)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending.add(user.rewardLockedUp);

                // reset lockup
                totalLockedUpRewards = totalLockedUpRewards.sub(user.rewardLockedUp);
                user.rewardLockedUp = 0;
                user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);

                // send rewards
                safeHULKTransfer(msg.sender, totalRewards);
                payReferralCommission(msg.sender, totalRewards);
            }
        } else if (pending > 0) {
            user.rewardLockedUp = user.rewardLockedUp.add(pending);
            totalLockedUpRewards = totalLockedUpRewards.add(pending);
            emit RewardLockedUp(msg.sender, _pid, pending);
        }
    }

    // Safe hulk transfer function, just in case if rounding error causes pool do not have enough HULK.
    function safeHULKTransfer(address _to, uint256 _amount) internal {
        if (hulk.balanceOf(address(this)) > totalHULKInPools) {
            //hulkBal = total hulk in MasterChef - total hulk in hulk pools, this will make sure that MasterChef never transfer rewards from deposited hulk pools
            uint256 hulkBal = hulk.balanceOf(address(this)).sub(totalHULKInPools);
            if (_amount >= hulkBal) {
                hulk.transfer(_to, hulkBal);
            } else if (_amount > 0) {
                hulk.transfer(_to, _amount);
            }
        }
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) public {
        require(msg.sender == devAddress, "setDevAddress: FORBIDDEN");
        require(_devAddress != address(0), "setDevAddress: ZERO");
        devAddress = _devAddress;
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        require(_feeAddress != address(0), "setFeeAddress: ZERO");
        feeAddress = _feeAddress;
    }

    // Update the hulk referral contract address by the owner
    function setHULKReferral(IHULKReferral _hulkReferral) public onlyOwner {
        hulkReferral = _hulkReferral;
    }

    // Update referral commission rate by the owner
    function setReferralCommissionRate(uint16 _referralCommissionRate) public onlyOperator {
        require(_referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE, "setReferralCommissionRate: referral commission rate too high");
        referralCommissionRate = _referralCommissionRate;
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (address(hulkReferral) != address(0) && referralCommissionRate > 0) {
            address referrer = hulkReferral.getReferrer(_user);
            uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);

            if (referrer != address(0) && commissionAmount > 0) {
                safeHULKTransfer(referrer, commissionAmount);
                hulkReferral.recordReferralCommission(referrer, commissionAmount);
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }

    // Pancake has to add hidden dummy pools in order to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _hulkPerBlock) public onlyOperator {
        require(_hulkPerBlock <= MAX_HULK_PER_BLOCK, "HULK per block too high");
        massUpdatePools();

        emit EmissionRateUpdated(msg.sender, hulkPerBlock, _hulkPerBlock);
        hulkPerBlock = _hulkPerBlock;
    }

    function updateAllocPoint(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOperator {
        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }
}
