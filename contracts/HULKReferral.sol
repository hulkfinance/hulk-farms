// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "./libs/SafeERC20.sol";
import "./abstract/Ownable.sol";
import "./interface/IHULKReferral.sol";

contract HULKReferral is Ownable, IHULKReferral {
    using SafeERC20 for IBEP20;

    address private _masterOperator;

    mapping(address => address) public referrers; // user address => referrer address
    mapping(address => uint256) public referralsCount; // referrer address => referrals count
    mapping(address => uint256) public totalReferralCommissions; // referrer address => total referral commissions

    event ReferralRecorded(address indexed user, address indexed referrer);
    event ReferralCommissionRecorded(address indexed referrer, uint256 commission);

    constructor(
        address _masterChef
    ) public {
        _masterOperator = _masterChef;
    }

    modifier onlyMasterOperator() {
        require(_masterOperator == msg.sender, "Operator: caller is not the operator.");
        _;
    }

    function recordReferral(address _user, address _referrer) public override onlyMasterOperator {
        if (_user != address(0)
        && _referrer != address(0)
        && _user != _referrer
            && referrers[_user] == address(0)
        ) {
            referrers[_user] = _referrer;
            referralsCount[_referrer] += 1;
            emit ReferralRecorded(_user, _referrer);
        }
    }

    function recordReferralCommission(address _referrer, uint256 _commission) public override onlyMasterOperator {
        if (_referrer != address(0) && _commission > 0) {
            totalReferralCommissions[_referrer] += _commission;
            emit ReferralCommissionRecorded(_referrer, _commission);
        }
    }

    // Get the referrer address that referred the user
    function getReferrer(address _user) public override view returns (address) {
        return referrers[_user];
    }

    // Owner can drain tokens that are sent here by mistake
    function drainBEP20Token(IBEP20 _token, uint256 _amount, address _to) external onlyOwner {
        _token.safeTransfer(_to, _amount);
    }
}
