// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
/**
 * @dev A token holder contract that will allow a beneficiary to extract the
 * tokens after a given release time.
 *
 * Useful for simple vesting schedules like "advisors get all of their tokens
 * after 1 year".
 */
contract TokenTimeRelease is ReentrancyGuard {
	using SafeERC20 for IERC20;
	using SafeMath for uint256;

	// ERC20 basic token contract being held
	IERC20 public _token;

	// beneficiary of tokens after they are released
	address public _beneficiary;

	// timestamp when token release is enabled
	uint256 public _releaseTime;
	uint256 public _releaseAmount;
	uint256 public _releaseTotalAmount;
	uint256 public _startTime;

	bool public initialized;

	modifier expectInitialized() {
		require(initialized, 'not initialized.');
		_;
	}

	function initialize() external {
		require(!initialized, 'already initialized');
		initialized = true;
		require(IERC20(_token).balanceOf(address(this)) >= _releaseTotalAmount, '!balance');
	}

	//
	constructor(
		IERC20 token_,
		address beneficiary_,
		uint256 releaseTime_,
		uint256 releaseTotalAmount_
	) public {
		// solhint-disable-next-line not-rely-on-time
		require(releaseTime_ > block.timestamp, 'TokenTimelock: release time is before current time');
		require(releaseTotalAmount_ > 0, 'TokenTimelock: !amount');

		_token = token_;
		_beneficiary = beneficiary_;
		_releaseTime = releaseTime_;
		_startTime = block.timestamp;

		_releaseTotalAmount = releaseTotalAmount_;
	}

	/**
	 * @return the token being held.
	 */
	function token() public view virtual returns (IERC20) {
		return _token;
	}

	/**
	 * @return the beneficiary of the tokens.
	 */
	function beneficiary() public view virtual returns (address) {
		return _beneficiary;
	}

	/**
	 * @return the time when the tokens are released.
	 */
	function releaseTime() public view virtual returns (uint256) {
		return _releaseTime;
	}

	function currentIncome() public view virtual returns (uint256) {
		uint256 currentTime = block.timestamp;
		if (currentTime > _releaseTime) {
			currentTime = _releaseTime;
		}

		uint256 timestamp = currentTime.sub(_startTime);
		uint256 releaseTimestamp = _releaseTime.sub(_startTime);
		uint256 amount = _releaseTotalAmount.mul(timestamp).div(releaseTimestamp);
		return amount.sub(_releaseAmount);
	}

	/**
	 * @notice Transfers tokens held by timelock to beneficiary.
	 */
	function release() public virtual expectInitialized nonReentrant {
		uint256 amount = currentIncome();
		if (amount > 0) {
			_releaseAmount = _releaseAmount.add(amount);
			token().safeTransfer(beneficiary(), amount);
		}
	}
}
