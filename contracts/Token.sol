// SPDX-License-Identifier: MIT
/**
 *Submitted for verification at Etherscan.io on 2019-05-09
 */

pragma solidity >=0.6.5 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libraries/Upgradable.sol";

// MOCK ERC20
// ----------------------------------------------------------------------------
// ERC20 Token, with the addition of symbol, name and decimals and a
// fixed supply
// ----------------------------------------------------------------------------
contract Token is ERC20, UpgradableProduct {
    constructor(
        string memory _symbol,
        string memory _name,
        uint8 _decimals,
        uint256 _total
    ) public ERC20(_name, _symbol) {
        _setupDecimals(_decimals);

        if (_total > 0) {
            _mint(msg.sender, _total * 10**uint256(decimals()));
        }
    }

    function mint(address account, uint256 amount)
        external
        virtual
        requireImpl
    {
        _mint(account, amount);
    }

    function burn(uint256 amount) external virtual {
        _burn(msg.sender, amount);
    }
}
