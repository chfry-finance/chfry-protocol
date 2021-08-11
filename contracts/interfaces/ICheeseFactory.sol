//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

interface ICheeseFactory {
    function poolMint(bytes32 poolName_) external returns (uint256);

    function prePoolMint(bytes32 poolName_) external view returns (uint256);
}
