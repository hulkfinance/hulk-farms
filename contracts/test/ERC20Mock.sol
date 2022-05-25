pragma solidity ^0.6.6;

import "../libs/BEP20.sol";


contract BEP20Mock is BEP20("Mock BEP20", "BEPMOCK") {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
