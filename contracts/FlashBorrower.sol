//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './interfaces/IERC3156FlashBorrower.sol';
import './interfaces/IERC3156FlashLender.sol';
import './libraries/TransferHelper.sol';

//  FlashLoan DEMO
contract FlashBorrower is IERC3156FlashBorrower {
	enum Action {
		NORMAL,
		STEAL,
		REENTER
	}

  using TransferHelper for address;

	IERC3156FlashLender lender;

	uint256 public flashBalance;
	address public flashInitiator;
	address public flashToken;
	uint256 public flashAmount;
	uint256 public flashFee;

	address public admin;

	constructor(address lender_) public {
		admin = msg.sender;
		lender = IERC3156FlashLender(lender_);
	}

	function setLender(address _lender) external {
		require(msg.sender == admin, '!admin');
		lender = IERC3156FlashLender(_lender);
	}

	/// @dev ERC-3156 Flash loan callback
	function onFlashLoan(
		address initiator,
		address token,
		uint256 amount,
		uint256 fee,
		bytes calldata data
	) external override returns (bytes32) {
		require(msg.sender == address(lender), 'FlashBorrower: Untrusted lender');
		require(initiator == address(this), 'FlashBorrower: External loan initiator');
		Action action = abi.decode(data, (Action)); // Use this to unpack arbitrary data
		flashInitiator = initiator;
		flashToken = token;
		flashAmount = amount;
		flashFee = fee;
		if (action == Action.NORMAL) {
			flashBalance = IERC20(token).balanceOf(address(this));
		} else if (action == Action.STEAL) {
			// do nothing
		} else if (action == Action.REENTER) {
			flashBorrow(token, amount * 2);
		}
		return keccak256('ERC3156FlashBorrower.onFlashLoan');
	}

	function flashBorrow(address token, uint256 amount) public {
		// Use this to pack arbitrary data to `onFlashLoan`
		bytes memory data = abi.encode(Action.NORMAL);
		approveRepayment(token, amount);
		lender.flashLoan(this, token, amount, data);
	}

	function flashBorrowAndSteal(address token, uint256 amount) public {
		// Use this to pack arbitrary data to `onFlashLoan`
		bytes memory data = abi.encode(Action.STEAL);
		lender.flashLoan(this, token, amount, data);
	}

	function flashBorrowAndReenter(address token, uint256 amount) public {
		// Use this to pack arbitrary data to `onFlashLoan`
		bytes memory data = abi.encode(Action.REENTER);
		approveRepayment(token, amount);
		lender.flashLoan(this, token, amount, data);
	}

	function approveRepayment(address token, uint256 amount) public {
		uint256 _allowance = IERC20(token).allowance(address(this), address(lender));
		uint256 _fee = lender.flashFee(token, amount);
		uint256 _repayment = amount + _fee;
		token.safeApprove(address(lender), 0);
		token.safeApprove(address(lender), _allowance + _repayment);
	}

	function transferFromAdmin(
		address _token,
		address _receiver,
		uint256 _amount
	) external {
		require(msg.sender == admin, '!admin');
		_token.safeTransfer(_receiver, _amount);
	}
}