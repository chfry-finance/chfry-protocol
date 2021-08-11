//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

pragma experimental ABIEncoderV2;

import "./Upgradable.sol";

contract WhiteList is UpgradableProduct {
    event SetWhitelist(address indexed user, bool state);

    mapping(address => bool) public whiteList;

    /// This function reverts if the caller is not governance
    ///
    /// @param _toWhitelist the account to mint tokens to.
    /// @param _state the whitelist state.
    function setWhitelist(address _toWhitelist, bool _state)
        external
        requireImpl
    {
        whiteList[_toWhitelist] = _state;
        emit SetWhitelist(_toWhitelist, _state);
    }

    /// @dev A modifier which checks if whitelisted for minting.
    modifier onlyWhitelisted() {
        require(whiteList[msg.sender], "!whitelisted");
        _;
    }
}
