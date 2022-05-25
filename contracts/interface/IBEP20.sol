pragma solidity ^0.6.6;

import "./IERC20.sol";

interface IBEP20 is IERC20 {
    /**
     * @dev Returns the bep token owner.
     */
    function getOwner() external view returns (address);
}
