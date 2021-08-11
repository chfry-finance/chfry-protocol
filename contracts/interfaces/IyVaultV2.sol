// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

interface IyVaultV2 {
    function token() external view returns (address);
    function deposit(uint) external returns (uint);
    function withdraw(uint, address) external returns (uint);
    function pricePerShare() external view returns (uint);
    function decimals() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
}