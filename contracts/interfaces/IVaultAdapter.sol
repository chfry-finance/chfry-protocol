// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

/// Interface for all Vault Adapter implementations.
interface IVaultAdapter {

  /// @dev Gets the token that the adapter accepts.
  function token() external view returns (address);

  /// @dev The total value of the assets deposited into the vault.
  function totalValue() external view returns (uint256);

  /// @dev Deposits funds into the vault.
  ///
  /// @param _amount  the amount of funds to deposit.
  function deposit(uint256 _amount) external;

  /// @dev Attempts to withdraw funds from the wrapped vault.
  ///
  /// The amount withdrawn to the recipient may be less than the amount requested.
  ///
  /// @param _recipient the recipient of the funds.
  /// @param _amount    the amount of funds to withdraw.
  function withdraw(address _recipient, uint256 _amount) external;
}