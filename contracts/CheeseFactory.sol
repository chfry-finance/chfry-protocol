// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import './libraries/Upgradable.sol';
import './CheeseToken.sol';
import './libraries/ConfigNames.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

//a1 = 75000, n = week, d= -390, week = [0,156]
//an=a1+(n-1)*d
//Sn=n*a1+(n(n-1)*d)/2
contract CheeseFactory is UpgradableProduct, ReentrancyGuard {
	using SafeMath for uint256;

	uint256 public constant MAX_WEEK = 156;
	uint256 public constant d = 390 * 10**18;
	uint256 public constant a1 = 75000 * 10**18;
	uint256 public constant TOTAL_WEIGHT = 10000;

	uint256 public startTimestamp;
	uint256 public lastTimestamp;
	uint256 public weekTimestamp;
	uint256 public totalMintAmount;
	CheeseToken public token;
	bool public initialized;

	struct Pool {
		address pool;
		uint256 weight;
		uint256 minted;
	}

	mapping(bytes32 => Pool) public poolInfo;

	constructor(address token_, uint256 weekTimestamp_) public {
		weekTimestamp = weekTimestamp_;
		token = CheeseToken(token_);
	}

	function setCheeseToken(address token_) external requireImpl {
		token = CheeseToken(token_);
	}

	function setPool(bytes32 poolName_, address poolAddress_) external requireImpl {
		require(poolName_ == ConfigNames.PRIVATE || poolName_ == ConfigNames.STAKE, 'name error');
		Pool storage pool = poolInfo[poolName_];
		pool.pool = poolAddress_;
	}

	modifier expectInitialized() {
		require(initialized, 'not initialized.');
		_;
	}

	function initialize(
		address private_,
		address stake_,
		uint256 startTimestamp_
	) external requireImpl {
		require(!initialized, 'already initialized');
		require(startTimestamp_ >= block.timestamp, '!startTime');
		// weight
		poolInfo[ConfigNames.PRIVATE] = Pool(private_, 1066, 0);
		poolInfo[ConfigNames.STAKE] = Pool(stake_, 8934, 0);
		initialized = true;
		startTimestamp = startTimestamp_;
		lastTimestamp = startTimestamp_;
	}

	function preMint() public view returns (uint256) {
		if (block.timestamp <= startTimestamp) {
			return uint256(0);
		}

		if (block.timestamp <= lastTimestamp) {
			return uint256(0);
		}
		uint256 time = block.timestamp.sub(startTimestamp);
		uint256 max_week_time = MAX_WEEK.mul(weekTimestamp);
		// time lt 156week
		if (time > max_week_time) {
			time = max_week_time;
		}

		// gt 1week
		if (time >= weekTimestamp) {
			uint256 n = time.div(weekTimestamp);

			//an =a1-(n)*d d<0
			//=> a1+(n)*(-d)
			uint256 an = a1.sub(n.mul(d));

			// gt 1week time stamp
			uint256 otherTimestamp = time.mod(weekTimestamp);
			uint256 other = an.mul(otherTimestamp).div(weekTimestamp);

			//Sn=n*a1+(n(n-1)*d)/2 d<0
			// => n*a1-(n(n-1)*(-d))/2

			// fist = n*a1
			uint256 first = n.mul(a1);
			// last = (n(n-1)*(-d))/2
			uint256 last = n.mul(n.sub(1)).mul(d).div(2);
			uint256 sn = first.sub(last);
			return other.add(sn).sub(totalMintAmount);
		} else {
			return a1.mul(time).div(weekTimestamp).sub(totalMintAmount);
		}
	}

	function _updateTotalAmount() internal returns (uint256) {
		uint256 preMintAmount = preMint();
		totalMintAmount = totalMintAmount.add(preMintAmount);
		lastTimestamp = block.timestamp;
		return preMintAmount;
	}

	function prePoolMint(bytes32 poolName_) public view returns (uint256) {
		uint256 preMintAmount = preMint();
		Pool memory pool = poolInfo[poolName_];
		uint256 poolTotal = totalMintAmount.add(preMintAmount).mul(pool.weight).div(TOTAL_WEIGHT);
		return poolTotal.sub(pool.minted);
	}

	function poolMint(bytes32 poolName_) external nonReentrant expectInitialized returns (uint256) {
		Pool storage pool = poolInfo[poolName_];
		require(msg.sender == pool.pool, 'Permission denied');
		_updateTotalAmount();
		uint256 poolTotal = totalMintAmount.mul(pool.weight).div(TOTAL_WEIGHT);
		uint256 amount = poolTotal.sub(pool.minted);
		if (amount > 0) {
			token.mint(msg.sender, amount);
			pool.minted = pool.minted.add(amount);
		}
		return amount;
	}
}
