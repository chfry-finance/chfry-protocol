//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import './interfaces/IERC3156FlashBorrower.sol';
import './interfaces/IERC3156FlashLender.sol';
import './libraries/TransferHelper.sol';

//  FlashLoan DEMO
contract FlashBorrowerDemo is IERC3156FlashBorrower, ReentrancyGuard {
	enum Action {
		NORMAL
	}

	enum Lender {
		USDT,
		USDC,
		DAI
	}

	using TransferHelper for address;
	using SafeMath for uint256;

	IERC3156FlashLender contextLender;

	uint256 public flashBalance;
	address public flashInitiator;
	address public flashToken;
	uint256 public flashAmount;
	uint256 public flashFee;

	address public admin;

	mapping(Lender => IERC3156FlashLender) lenders;

	event FlashBorrow(address indexed _sender, Lender _index, address _token, uint256 _amount, uint256 _fee);
	event SetLender(Lender, address);

	constructor(
		address _admin,
		address _USDTLender,
		address _USDCLender,
		address _DAILender
	) public {
		admin = _admin;
		lenders[Lender.USDT] = IERC3156FlashLender(_USDTLender);
		lenders[Lender.USDC] = IERC3156FlashLender(_USDCLender);
		lenders[Lender.DAI] = IERC3156FlashLender(_DAILender);
	}

	modifier onlyAdmin() {
		require(admin == msg.sender, 'only admin');
		_;
	}

	function setLender(Lender _index, address _address) external onlyAdmin {
		lenders[_index] = IERC3156FlashLender(_address);
		emit SetLender(_index, _address);
	}

	/// @dev ERC-3156 Flash loan callback
	function onFlashLoan(
		address initiator,
		address token,
		uint256 amount,
		uint256 fee,
		bytes calldata data
	) external override returns (bytes32) {
		require(msg.sender == address(contextLender), 'FlashBorrower: Untrusted lender');
		require(initiator == address(this), 'FlashBorrower: External loan initiator');
		Action action = abi.decode(data, (Action));
		flashInitiator = initiator;
		flashToken = token;
		flashAmount = amount;
		flashFee = fee;
		if (action == Action.NORMAL) {
			flashBalance = IERC20(token).balanceOf(address(this));
		}
		return keccak256('ERC3156FlashBorrower.onFlashLoan');
	}

	function flashBorrow(
		Lender _index,
		address _token,
		uint256 _amount
	) external nonReentrant {
		// Use this to pack arbitrary data to `onFlashLoan`
		contextLender = lenders[_index];
		bytes memory data = abi.encode(Action.NORMAL);
		uint256 _fee = _approveRepayment(_token, _amount);
		contextLender.flashLoan(this, _token, _amount, data);
		emit FlashBorrow(msg.sender, _index, _token, _amount, _fee);
	}

	function _approveRepayment(address _token, uint256 _amount) internal returns (uint256) {
		uint256 _fee = contextLender.flashFee(_token, _amount);
		uint256 _repayment = _amount.add(_fee);
		_token.safeTransferFrom(msg.sender, address(this), _fee);
		_token.safeApprove(address(contextLender), 0);
		_token.safeApprove(address(contextLender), _repayment);
		return _fee;
	}

	function transferFromAdmin(
		address _token,
		address _receiver,
		uint256 _amount
	) external onlyAdmin {
		_token.safeTransfer(_receiver, _amount);
	}
}
