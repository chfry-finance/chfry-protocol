// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;
interface IChainlink {
  function latestAnswer() external view returns (int256);
}