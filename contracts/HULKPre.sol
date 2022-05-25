// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import "./abstract/Ownable.sol";
import "./interface/IBEP20.sol";
import "./libs/Address.sol";
import "./libs/SafeERC20.sol";
import "./interface/AggregatorV3Interface.sol";

/**
 * @dev Implementation of the {IBEP20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IBEP20-approve}.
 */
contract HULKPRE is Ownable, IBEP20 {
    using Address for address;
    using SafeERC20 for IBEP20;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256[3] private _prices;

    uint256[3] private _soldTokens = [0, 0, 0];

    uint8 private _currentRound;

    uint256[3] private _limits = [210000000, 180000000, 110000000];

    uint256[3] private _stopDates = [0,0,0];

    address private HULK;

    address private _marketWallet = 0xe4a9d13F6F88cB5fF1727D2b5682e0e50042D5d9;


    // CONTRACT ADDRESSES

    address private BUSD;
    address private USDT;
    AggregatorV3Interface private BNBPriceFeed;
    AggregatorV3Interface private BUSDPriceFeed;
    AggregatorV3Interface private USDTPriceFeed;


    uint256 private _totalSupply;
    uint8 private _decimals;
    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(uint256 _basePrice) public  {
//        require((block.chainid == 56 || block.chainid == 97), "Invalid blockchain, only BSC supported");
        _name = "HULKPRE";
        _symbol = "HLKPRE";
        _decimals = 18;
        _totalSupply = 500000000 * 10 ** uint256(_decimals);
        _balances[address(this)] = _totalSupply;
        _prices = [_basePrice, _basePrice * 115 / 100, _basePrice * 130 / 100];
        emit Transfer(address(0), address(this), _totalSupply);

        uint chainId;
        assembly {
            chainId := chainid()
        }

        // MAINNET
        if (chainId == 56) {
            BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
            USDT = 0xF2Ebd97dDA388f38aB119e3166Edd0d3107E1538;
            BNBPriceFeed = AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);
            BUSDPriceFeed = AggregatorV3Interface(0xcBb98864Ef56E9042e7d2efef76141f15731B82f);
            USDTPriceFeed = AggregatorV3Interface(0xB97Ad0E74fa7d920791E90258A6E2085088b4320);
            // TESTNET
        } else {
            BUSD = 0xdB1Cc97ada0D2A0bCE7325699A9F1081C95F0ac9;
            USDT = 0xbDf2f04a77Ca7474F127208cab24260197D14a04;
            BNBPriceFeed = AggregatorV3Interface(0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526);
            BUSDPriceFeed = AggregatorV3Interface(0x9331b55D9830EF609A2aBCfAc0FBCE050A52fdEa);
            USDTPriceFeed = AggregatorV3Interface(0xEca2605f0BCF2BA5966372C99837b1F182d3D620);
        }


    }

    function getOwner() external view override returns (address) {
        return owner();
    }

    function getPrice() public view returns (uint256) {
        return _prices[_currentRound];
    }

    function getCurrentRound() public view returns (uint8) {
        return _currentRound;
    }

    function getAvailable() public view returns (uint256) {
        uint256 result = _limits[_currentRound] * 10 ** uint256(decimals()) - _soldTokens[_currentRound];
        return result;
    }


    function totalSold() public view returns (uint256) {
        return _soldTokens[0] + _soldTokens[1] + _soldTokens[2];
    }

    function setHULKAddress(address _hulk) public onlyOwner {
        require(_hulk != address(0), "Zero address is prohibited");
        require(_hulk.isContract(), "Please provide a valid contract address");
        HULK = _hulk;
    }


    function withdrawBNB() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No BNB on contract balance");
        payable(owner()).transfer(balance);

    }

    function withdrawToken(address _token) public onlyOwner {
        require(_token != address(0) && _token.isContract(), "Invalid token contract address");
        IBEP20 token_contract = IBEP20(_token);
        uint256 balance = token_contract.balanceOf(address(this));
        require(balance > 0, "No tokens on contract address");
        token_contract.safeTransfer(owner(), balance);

    }


    function withdrawHULKPRE(uint256 _amount) public onlyOwner {
        require(block.timestamp > _stopDates[2], "Presale 2 is not over");
        require(_amount <= balanceOf(address(this)), "Insufficient token on contract balance");
        _transfer(address(this), owner(), _amount);
    }


    function setStopDate(uint256 _date, uint8 _round) public onlyOwner {
        require(_date > block.timestamp, "Date must be grater than now");
        require((_round < 3 && _round >= _currentRound), "Invalid round. 0-2 required");
        _stopDates[_round] = _date;
    }


    function nextRound() public onlyOwner {
        require(_currentRound < 2, "Last presale round already reached");
        _currentRound += 1;

    }



    function getRate(address _baseCoin) public view returns (uint256){
        int256 rate;
        if (_baseCoin == address(0)) {
            ( , rate, , , ) = BNBPriceFeed.latestRoundData();
        } else if (_baseCoin == BUSD) {
            ( , rate, , , ) = BUSDPriceFeed.latestRoundData();
        } else {
            ( , rate, , , ) = USDTPriceFeed.latestRoundData();
        }

        return uint256(rate);
    }


    function coinToTokens(uint256 _amountIn, address _coin) public view returns (uint256){
        uint256 rate = getRate(_coin);
        if (rate == 0) {
            return 0;
        }
        uint256 result = _amountIn * rate / _prices[_currentRound] / 10 ** 4;
        if (result > getAvailable()) {
            result = getAvailable();
        }
        return result;
    }


    function tokensToCoin(uint256 _amountIn, address _coin) public view returns (uint256) {
        uint256 rate = getRate(_coin);
        if (rate == 0) {
            return 0;
        }
        uint256 result = _amountIn * _prices[_currentRound] * 10 ** 4 / rate;
        return result;
    }


    function buyTokens(uint256 _amount, address _coin) public payable {
        require(HULK != address(0), "HULK contract address is not set");
        require(_stopDates[_currentRound] > block.timestamp, "Current presale round is over");
        require((_amount > 0 && _amount <= balanceOf(address(this))), "Invalid amount of tokens");
        require(getAvailable() >= _amount, "Insufficient token amount on current round left");
        require(_amount * _prices[_currentRound] / 10 ** 22 >= 20, "The minimum buy amount is 20 USD");
        require((_coin == BUSD || _coin == USDT || _coin == address(0)), "Invalid coin address");
        uint256 coinAmount = tokensToCoin(_amount, _coin);
        uint256 change;
        if (_coin == address(0)) {
            require(msg.value >= coinAmount, "Insufficient BNB amount to buy tokens");
            if (msg.value > coinAmount) {
                change = msg.value - coinAmount;
            }
        } else {
            IBEP20 coin_contract = IBEP20(_coin);
            require(coin_contract.balanceOf(_msgSender()) >= coinAmount, "Insufficient coin balance to buy tokens");
            coin_contract.safeTransferFrom(_msgSender(), address(this), coinAmount);
        }

        _transfer(address(this), _msgSender(), _amount);
        _soldTokens[_currentRound] += _amount;
        distribute(coinAmount, _coin);
        if (change > 0) {
            payable(_msgSender()).transfer(change);
        }

    }

    function distribute(uint256 _amount, address _coin) internal {
        uint256 marketAmount = _amount * 10 / 100;
        uint256 hulkAmount = _amount * 50 / 100;
        if (_coin == address(0)) {
            payable(HULK).transfer(hulkAmount);
            payable(_marketWallet).transfer(marketAmount);
            payable(owner()).transfer(_amount - hulkAmount - marketAmount);
        } else {
            IBEP20 coin_contract = IBEP20(_coin);
            coin_contract.safeTransfer(_marketWallet, marketAmount);
            coin_contract.safeTransfer(owner(), _amount - marketAmount);
        }
    }


    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IBEP20-balanceOf} and {IBEP20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IBEP20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IBEP20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IBEP20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IBEP20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IBEP20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IBEP20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IBEP20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IBEP20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");


        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);


    }


    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }


}