//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Faucet {
    constructor() public {}

    function withdraw(address token) external {
        uint256 amount = 1000 * (10**uint256(ERC20(token).decimals()));
        ERC20(token).transfer(msg.sender, amount);
    }
}
