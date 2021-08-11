// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import './libraries/Upgradable.sol';

contract CheeseToken is ERC20, UpgradableProduct {
	using SafeMath for uint256;

	mapping(address => bool) public whiteList;

	constructor(string memory _symbol, string memory _name) public ERC20(_name, _symbol) {
		_mint(msg.sender, uint256(2328300).mul(1e18));
	}

	modifier onlyWhitelisted() {
		require(whiteList[msg.sender], '!whitelisted');
		_;
	}

	function setWhitelist(address _toWhitelist, bool _state) external requireImpl {
		whiteList[_toWhitelist] = _state;
	}

	function mint(address account, uint256 amount) external virtual onlyWhitelisted {
		require(totalSupply().add(amount) <= cap(), 'ERC20Capped: cap exceeded');
		_mint(account, amount);
	}

	function cap() public pure virtual returns (uint256) {
		return 9313200 * 1e18;
	}

	function burnFrom(address account, uint256 amount) public virtual {
		uint256 decreasedAllowance = allowance(account, _msgSender()).sub(
			amount,
			'ERC20: burn amount exceeds allowance'
		);
		_approve(account, _msgSender(), decreasedAllowance);
		_burn(account, amount);
	}

	function burn(uint256 amount) external virtual {
		_burn(_msgSender(), amount);
	}
}
