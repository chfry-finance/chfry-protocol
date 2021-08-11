//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import './FixedPointMath.sol';
import './TransferHelper.sol';
import './ConfigNames.sol';
import '../interfaces/IFryerConfig.sol';

library CDP {
	using CDP for Data;
	using FixedPointMath for FixedPointMath.uq192x64;
	using SafeMath for uint256;

	uint256 public constant MAXIMUM_COLLATERALIZATION_LIMIT = 4000000000000000000;

	struct Context {
		IFryerConfig fryerConfig;
		FixedPointMath.uq192x64 accumulatedYieldWeight;
	}

	struct Data {
		uint256 totalDeposited;
		uint256 totalDebt;
		uint256 totalCredit;
		uint256 lastDeposit;
		FixedPointMath.uq192x64 lastAccumulatedYieldWeight;
	}

	function update(Data storage _self, Context storage _ctx) internal {
		uint256 _earnedYield = _self.getEarnedYield(_ctx);
		if (_earnedYield > _self.totalDebt) {
			uint256 _currentTotalDebt = _self.totalDebt;
			_self.totalDebt = 0;
			_self.totalCredit = _earnedYield.sub(_currentTotalDebt);
		} else {
			_self.totalCredit = 0;
			_self.totalDebt = _self.totalDebt.sub(_earnedYield);
		}
		_self.lastAccumulatedYieldWeight = _ctx.accumulatedYieldWeight;
	}

	function checkHealth(
		Data storage _self,
		Context storage _ctx,
		string memory _msg
	) internal view {
		require(_self.isHealthy(_ctx), _msg);
	}

	function isHealthy(Data storage _self, Context storage _ctx) internal view returns (bool) {
		return collateralizationLimit(_ctx).cmp(_self.getCollateralizationRatio(_ctx)) <= 0;
	}

	function collateralizationLimit(Context storage _ctx) internal view returns (FixedPointMath.uq192x64 memory) {
		return
			FixedPointMath.uq192x64(
				MAXIMUM_COLLATERALIZATION_LIMIT.mul(_ctx.fryerConfig.getConfigValue(ConfigNames.FRYER_LTV)).div(
					_ctx.fryerConfig.PERCENT_DENOMINATOR()
				)
			);
	}

	function getUpdatedTotalDebt(Data storage _self, Context storage _ctx) internal view returns (uint256) {
		uint256 _unclaimedYield = _self.getEarnedYield(_ctx);
		if (_unclaimedYield == 0) {
			return _self.totalDebt;
		}

		uint256 _currentTotalDebt = _self.totalDebt;
		if (_unclaimedYield >= _currentTotalDebt) {
			return 0;
		}

		return _currentTotalDebt.sub(_unclaimedYield);
	}

	function getUpdatedTotalCredit(Data storage _self, Context storage _ctx) internal view returns (uint256) {
		uint256 _unclaimedYield = _self.getEarnedYield(_ctx);
		if (_unclaimedYield == 0) {
			return _self.totalCredit;
		}

		uint256 _currentTotalDebt = _self.totalDebt;
		if (_unclaimedYield <= _currentTotalDebt) {
			return 0;
		}

		return _self.totalCredit.add(_unclaimedYield.sub(_currentTotalDebt));
	}

	function getEarnedYield(Data storage _self, Context storage _ctx) internal view returns (uint256) {
		FixedPointMath.uq192x64 memory _currentAccumulatedYieldWeight = _ctx.accumulatedYieldWeight;
		FixedPointMath.uq192x64 memory _lastAccumulatedYieldWeight = _self.lastAccumulatedYieldWeight;

		if (_currentAccumulatedYieldWeight.cmp(_lastAccumulatedYieldWeight) == 0) {
			return 0;
		}

		return _currentAccumulatedYieldWeight.sub(_lastAccumulatedYieldWeight).mul(_self.totalDeposited).decode();
	}

	function getCollateralizationRatio(Data storage _self, Context storage _ctx)
		internal
		view
		returns (FixedPointMath.uq192x64 memory)
	{
		uint256 _totalDebt = _self.getUpdatedTotalDebt(_ctx);
		if (_totalDebt == 0) {
			return FixedPointMath.maximumValue();
		}
		return FixedPointMath.fromU256(_self.totalDeposited).div(_totalDebt);
	}
}
