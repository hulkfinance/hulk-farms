// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import "./abstract/Ownable.sol";
import "./interface/IBEP20.sol";
import "./libs/SafeERC20.sol";

contract HULKSwap is Ownable {
    using SafeERC20 for IBEP20;

    address  public token0;
    address  public token1;

    address public immutable deadAddress = 0x000000000000000000000000000000000000dEaD;

    bool public isSwapStarted = false;

    event Swap(address indexed user, uint256 amount);
    event AdminTokenRecovery(address tokenRecovered, uint256 amount);

    constructor(
        address _presaleToken,
        address _officialToken
    ) public {
        token0 = _presaleToken;
        token1 = _officialToken;
    }

    function swap(uint256 _amount) public {
        require(isSwapStarted == true, 'HULKSwap:: Swap not started.');

        uint256 hulk_balance = IBEP20(token1).balanceOf(address(this));
        uint256 hulkpre_balance = IBEP20(token0).balanceOf(_msgSender());

        require(_amount <= hulkpre_balance, "HULKSwap:: Insufficient HULKPRE balance.");
        require(_amount <= hulk_balance, "HULKSwap:: Not enough HULK balance on contract.");

        IBEP20(token0).safeTransferFrom(_msgSender(), deadAddress, _amount);
        IBEP20(token1).safeTransfer(_msgSender(), _amount);

        emit Swap(_msgSender(), _amount);
    }


    function startSwap() public onlyOwner returns (bool) {
        isSwapStarted = true;
        return true;
    }

    function stopSwap() public onlyOwner returns (bool) {
        isSwapStarted = false;
        return true;
    }


    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        IBEP20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }
}