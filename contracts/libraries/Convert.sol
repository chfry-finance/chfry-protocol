//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

contract Convert {
	using SafeMath for uint256;

	function convertTokenAmount(
		address _fromToken,
		address _toToken,
		uint256 _fromAmount
	) public view returns (uint256 toAmount) {
		uint256 fromDecimals = uint256(ERC20(_fromToken).decimals());
		uint256 toDecimals = uint256(ERC20(_toToken).decimals());
		if (fromDecimals > toDecimals) {
			toAmount = _fromAmount.div(10**(fromDecimals.sub(toDecimals)));
		} else if (toDecimals > fromDecimals) {
			toAmount = _fromAmount.mul(10**(toDecimals.sub(fromDecimals)));
		} else {
			toAmount = _fromAmount;
		}
		return toAmount;
	}
}
