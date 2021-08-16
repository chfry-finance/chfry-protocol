//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract FriesToken is AccessControl, ERC20('Fry USD', 'FUSD') {
	using SafeMath for uint256;

	/// @dev The identifier of the role which maintains other roles.
	bytes32 public constant ADMIN_ROLE = keccak256('ADMIN');

	/// @dev The identifier of the role which allows accounts to mint tokens.
	bytes32 public constant SENTINEL_ROLE = keccak256('SENTINEL');

	/// @dev addresses whitelisted for minting new tokens
	mapping(address => bool) public whiteList;

	/// @dev addresses blacklisted for minting new tokens
	mapping(address => bool) public blacklist;

	/// @dev addresses paused for minting new tokens
	mapping(address => bool) public paused;

	/// @dev ceiling per address for minting new tokens
	mapping(address => uint256) public ceiling;

	/// @dev already minted amount per address to track the ceiling
	mapping(address => uint256) public hasMinted;

	event Paused(address friesAddress, bool isPaused);

	constructor() public {
		_setupRole(ADMIN_ROLE, msg.sender);
		_setupRole(SENTINEL_ROLE, msg.sender);
		_setRoleAdmin(SENTINEL_ROLE, ADMIN_ROLE);
		_setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
	}

	/// @dev A modifier which checks if whitelisted for minting.
	modifier onlyWhitelisted() {
		require(whiteList[msg.sender], 'Fries is not whitelisted');
		_;
	}

	/// @dev Mints tokens to a recipient.
	///
	/// This function reverts if the caller does not have the minter role.
	///
	/// @param _recipient the account to mint tokens to.
	/// @param _amount    the amount of tokens to mint.
	function mint(address _recipient, uint256 _amount) external onlyWhitelisted {
		require(!blacklist[msg.sender], 'Fries is blacklisted.');
		uint256 _total = _amount.add(hasMinted[msg.sender]);
		require(_total <= ceiling[msg.sender], 'Fries ceiling was breached.');
		require(!paused[msg.sender], 'user is currently paused.');
		hasMinted[msg.sender] = hasMinted[msg.sender].add(_amount);
		_mint(_recipient, _amount);
	}

	/// This function reverts if the caller does not have the admin role.
	///
	/// @param _toWhitelist the account to mint tokens to.
	/// @param _state the whitelist state.

	function setWhitelist(address _toWhitelist, bool _state) external onlyAdmin {
		whiteList[_toWhitelist] = _state;
	}

	/// This function reverts if the caller does not have the admin role.
	///
	/// @param _newSentinel the account to set as sentinel.

	function setSentinel(address _newSentinel) external onlyAdmin {
		_setupRole(SENTINEL_ROLE, _newSentinel);
	}

	/// This function reverts if the caller does not have the admin role.
	///
	/// @param _toBlacklist the account to mint tokens to.
	function setBlacklist(address _toBlacklist) external onlySentinel {
		blacklist[_toBlacklist] = true;
	}

	/// This function reverts if the caller does not have the admin role.
	function pauseFries(address _toPause, bool _state) external onlySentinel {
		paused[_toPause] = _state;
		Paused(_toPause, _state);
	}

	/// This function reverts if the caller does not have the admin role.
	///
	/// @param _toSetCeiling the account set the ceiling off.
	/// @param _ceiling the max amount of tokens the account is allowed to mint.
	function setCeiling(address _toSetCeiling, uint256 _ceiling) external onlyAdmin {
		ceiling[_toSetCeiling] = _ceiling;
	}

	/// @dev A modifier which checks that the caller has the admin role.
	modifier onlyAdmin() {
		require(hasRole(ADMIN_ROLE, msg.sender), 'only admin');
		_;
	}
	/// @dev A modifier which checks that the caller has the sentinel role.
	modifier onlySentinel() {
		require(hasRole(SENTINEL_ROLE, msg.sender), 'only sentinel');
		_;
	}

	/**
	 * @dev Destroys `amount` tokens from the caller.
	 *
	 * See {ERC20-_burn}.
	 */
	function burn(uint256 amount) public virtual {
		_burn(_msgSender(), amount);
	}

	/**
	 * @dev Destroys `amount` tokens from `account`, deducting from the caller's
	 * allowance.
	 *
	 * See {ERC20-_burn} and {ERC20-allowance}.
	 *
	 * Requirements:
	 *
	 * - the caller must have allowance for ``accounts``'s tokens of at least
	 * `amount`.
	 */
	function burnFrom(address account, uint256 amount) public virtual {
		uint256 decreasedAllowance = allowance(account, _msgSender()).sub(
			amount,
			'ERC20: burn amount exceeds allowance'
		);

		_approve(account, _msgSender(), decreasedAllowance);
		_burn(account, amount);
	}

	/**
	 * @dev lowers hasminted from the caller's allocation
	 *
	 */
	function lowerHasMinted(uint256 amount) public onlyWhitelisted {
		if (hasMinted[msg.sender] < amount) {
			hasMinted[msg.sender] = 0;
		} else {
			hasMinted[msg.sender] = hasMinted[msg.sender].sub(amount);
		}
	}
}
