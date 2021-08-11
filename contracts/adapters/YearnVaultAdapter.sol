// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

pragma experimental ABIEncoderV2;


import "@openzeppelin/contracts/math/SafeMath.sol";

import "../libraries/FixedPointMath.sol";
import "../libraries/TransferHelper.sol";
import "../interfaces/IDetailedERC20.sol";
import "../interfaces/IVaultAdapter.sol";
import "../interfaces/IyVaultV2.sol";

/// @title YearnVaultAdapter
///
/// @dev A vault adapter implementation which wraps a yEarn vault.
contract YearnVaultAdapter is IVaultAdapter {
    using FixedPointMath for FixedPointMath.uq192x64;
    using TransferHelper for address;
    using SafeMath for uint256;

    /// @dev The vault that the adapter is wrapping.
    IyVaultV2 public vault;

    /// @dev The address which has admin control over this contract.
    address public admin;

    /// @dev The decimals of the token.
    uint256 public decimals;

    constructor(IyVaultV2 _vault, address _admin) public {
        vault = _vault;
        admin = _admin;
        updateApproval();
        decimals = _vault.decimals();
    }

    /// @dev A modifier which reverts if the caller is not the admin.
    modifier onlyAdmin() {
        require(admin == msg.sender, "YearnVaultAdapter: only admin");
        _;
    }

    /// @dev Gets the token that the vault accepts.
    ///
    /// @return the accepted token.
    function token() external view override returns (address) {
        return vault.token();
    }

    /// @dev Gets the total value of the assets that the adapter holds in the vault.
    ///
    /// @return the total assets.
    function totalValue() external view override returns (uint256) {
        return _sharesToTokens(vault.balanceOf(address(this)));
    }

    /// @dev Deposits tokens into the vault.
    ///
    /// @param _amount the amount of tokens to deposit into the vault.
    function deposit(uint256 _amount) external override {
        vault.deposit(_amount);
    }

    /// @dev Withdraws tokens from the vault to the recipient.
    ///
    /// This function reverts if the caller is not the admin.
    ///
    /// @param _recipient the account to withdraw the tokes to.
    /// @param _amount    the amount of tokens to withdraw.
    function withdraw(address _recipient, uint256 _amount)
        external
        override
        onlyAdmin
    {
        vault.withdraw(_tokensToShares(_amount), _recipient);
    }

    /// @dev Updates the vaults approval of the token to be the maximum value.
    function updateApproval() public {
        address _token = vault.token();
        _token.safeApprove(address(vault), uint256(-1));
    }

    /// @dev Computes the number of tokens an amount of shares is worth.
    ///
    /// @param _sharesAmount the amount of shares.
    ///
    /// @return the number of tokens the shares are worth.

    function _sharesToTokens(uint256 _sharesAmount)
        internal
        view
        returns (uint256)
    {
        return _sharesAmount.mul(vault.pricePerShare()).div(10**decimals);
    }

    /// @dev Computes the number of shares an amount of tokens is worth.
    ///
    /// @param _tokensAmount the amount of shares.
    ///
    /// @return the number of shares the tokens are worth.
    function _tokensToShares(uint256 _tokensAmount)
        internal
        view
        returns (uint256)
    {
        return _tokensAmount.mul(10**decimals).div(vault.pricePerShare());
    }
}
