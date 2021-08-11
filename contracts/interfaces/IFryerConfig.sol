// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

interface IFryerConfig {
    function getConfigValue(bytes32 _name) external view returns (uint256);

    function PERCENT_DENOMINATOR() external view returns (uint256);

    function ZERO_ADDRESS() external view returns (address);
}
