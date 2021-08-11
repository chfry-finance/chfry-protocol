// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/cryptography/MerkleProof.sol';
import './libraries/Upgradable.sol';
import './libraries/TransferHelper.sol';
import './libraries/WhiteList.sol';
import './libraries/ConfigNames.sol';
import './CheeseToken.sol';
import './CheeseFactory.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

contract CheeseStakePool is UpgradableProduct, ReentrancyGuard {
	event AddPoolToken(address indexed pool, uint256 indexed weight);
	event UpdatePoolToken(address indexed pool, uint256 indexed weight);

	event Stake(address indexed pool, address indexed user, uint256 indexed amount);
	event Withdraw(address indexed pool, address indexed user, uint256 indexed amount);
	event Claimed(address indexed pool, address indexed user, uint256 indexed amount);
	event SetCheeseFactory(address indexed factory);
	event SetCheeseToken(address indexed token);
	event SettleFlashLoan(bytes32 indexed merkleRoot, uint256 indexed index, uint256 amount, uint256 settleBlockNumber);
	using TransferHelper for address;
	using SafeMath for uint256;

	struct UserInfo {
		uint256 amount;
		uint256 debt;
		uint256 reward;
		uint256 totalIncome;
	}

	struct PoolInfo {
		uint256 pid;
		address token;
		uint256 weight;
		uint256 rewardPerShare;
		uint256 reward;
		uint256 lastBlockTimeStamp;
		uint256 debt;
		uint256 totalAmount;
	}

	struct MerkleDistributor {
		bytes32 merkleRoot;
		uint256 index;
		uint256 amount;
		uint256 settleBlocNumber;
	}

	CheeseToken public token;
	CheeseFactory public cheeseFactory;
	PoolInfo[] public poolInfos;
	PoolInfo public flashloanPool;

	uint256 public lastBlockTimeStamp;
	uint256 public rewardPerShare;
	uint256 public totalWeight;

	MerkleDistributor[] public merkleDistributors;

	mapping(address => uint256) public tokenOfPid;
	mapping(address => bool) public tokenUsed;

	mapping(uint256 => mapping(address => UserInfo)) public userInfos;
	mapping(uint256 => mapping(address => bool)) claimedFlashLoanState;

	constructor(address cheeseFactory_, address token_) public {
		cheeseFactory = CheeseFactory(cheeseFactory_);
		token = CheeseToken(token_);
		_initFlashLoanPool(0);
	}

	function _initFlashLoanPool(uint256 flashloanPoolWeight) internal {
		flashloanPool = PoolInfo(0, address(this), flashloanPoolWeight, 0, 0, block.timestamp, 0, 0);
		totalWeight = totalWeight.add(flashloanPool.weight);
		emit AddPoolToken(address(this), flashloanPool.weight);
	}

	function setCheeseFactory(address cheeseFactory_) external requireImpl {
		cheeseFactory = CheeseFactory(cheeseFactory_);
		emit SetCheeseFactory(cheeseFactory_);
	}

	function setCheeseToken(address token_) external requireImpl {
		token = CheeseToken(token_);
		emit SetCheeseToken(token_);
	}

	modifier verifyPid(uint256 pid) {
		require(poolInfos.length > pid && poolInfos[pid].token != address(0), 'pool does not exist');
		_;
	}

	modifier updateAllPoolRewardPerShare() {
		if (totalWeight > 0 && block.timestamp > lastBlockTimeStamp) {
			(uint256 _reward, uint256 _perShare) = currentAllPoolRewardShare();
			rewardPerShare = _perShare;
			lastBlockTimeStamp = block.timestamp;
			require(_reward == cheeseFactory.poolMint(ConfigNames.STAKE), 'pool mint error');
		}
		_;
	}

	modifier updateSinglePoolReward(PoolInfo storage poolInfo) {
		if (poolInfo.weight > 0) {
			uint256 debt = poolInfo.weight.mul(rewardPerShare).div(1e18);
			uint256 poolReward = debt.sub(poolInfo.debt);
			poolInfo.reward = poolInfo.reward.add(poolReward);
			poolInfo.debt = debt;
		}
		_;
	}

	modifier updateSinglePoolRewardPerShare(PoolInfo storage poolInfo) {
		if (poolInfo.totalAmount > 0 && block.timestamp > poolInfo.lastBlockTimeStamp) {
			(uint256 _reward, uint256 _perShare) = currentSinglePoolRewardShare(poolInfo.pid);
			poolInfo.rewardPerShare = _perShare;
			poolInfo.reward = poolInfo.reward.sub(_reward);
			poolInfo.lastBlockTimeStamp = block.timestamp;
		}
		_;
	}

	modifier updateUserReward(PoolInfo storage poolInfo, address user) {
		UserInfo storage userInfo = userInfos[poolInfo.pid][user];
		if (userInfo.amount > 0) {
			uint256 debt = userInfo.amount.mul(poolInfo.rewardPerShare).div(1e18);
			uint256 userReward = debt.sub(userInfo.debt);
			userInfo.reward = userInfo.reward.add(userReward);
			userInfo.debt = debt;
		}
		_;
	}

	function getPoolInfo(uint256 pid)
		external
		view
		virtual
		verifyPid(pid)
		returns (
			uint256 _pid,
			address _token,
			uint256 _weight,
			uint256 _rewardPerShare,
			uint256 _reward,
			uint256 _lastBlockTimeStamp,
			uint256 _debt,
			uint256 _totalAmount
		)
	{
		PoolInfo memory pool = poolInfos[pid];
		return (
			pool.pid,
			pool.token,
			pool.weight,
			pool.rewardPerShare,
			pool.reward,
			pool.lastBlockTimeStamp,
			pool.debt,
			pool.totalAmount
		);
	}

	function getPoolInfos()
		external
		view
		virtual
		returns (
			uint256 length,
			uint256[] memory _pid,
			address[] memory _token,
			uint256[] memory _weight,
			uint256[] memory _lastBlockTimeStamp,
			uint256[] memory _totalAmount
		)
	{
		length = poolInfos.length;
		_pid = new uint256[](length);
		_token = new address[](length);
		_weight = new uint256[](length);
		_lastBlockTimeStamp = new uint256[](length);
		_totalAmount = new uint256[](length);

		for (uint256 i = 0; i < length; i++) {
			PoolInfo memory pool = poolInfos[i];
			_pid[i] = pool.pid;
			_token[i] = pool.token;
			_weight[i] = pool.weight;
			_lastBlockTimeStamp[i] = pool.lastBlockTimeStamp;
			_totalAmount[i] = pool.totalAmount;
		}

		return (length, _pid, _token, _weight, _lastBlockTimeStamp, _totalAmount);
	}

	function getUserInfo(uint256 pid, address userAddress)
		external
		view
		virtual
		returns (
			uint256 _amount,
			uint256 _debt,
			uint256 _reward,
			uint256 _totalIncome
		)
	{
		UserInfo memory userInfo = userInfos[pid][userAddress];
		return (userInfo.amount, userInfo.debt, userInfo.reward, userInfo.totalIncome);
	}

	function currentAllPoolRewardShare() public view virtual returns (uint256 _reward, uint256 _perShare) {
		_reward = cheeseFactory.prePoolMint(ConfigNames.STAKE);
		_perShare = rewardPerShare;

		if (totalWeight > 0) {
			_perShare = _perShare.add(_reward.mul(1e18).div(totalWeight));
		}
		return (_reward, _perShare);
	}

	function currentSinglePoolRewardShare(uint256 pid)
		public
		view
		virtual
		verifyPid(pid)
		returns (uint256 _reward, uint256 _perShare)
	{
		PoolInfo memory poolInfo = poolInfos[pid];

		_reward = poolInfo.reward;
		_perShare = poolInfo.rewardPerShare;

		if (poolInfo.totalAmount > 0) {
			uint256 pendingShare = _reward.mul(1e18).div(poolInfo.totalAmount);
			_perShare = _perShare.add(pendingShare);
		}
		return (_reward, _perShare);
	}

	function stake(uint256 pid, uint256 amount)
		external
		virtual
		nonReentrant
		verifyPid(pid)
		updateAllPoolRewardPerShare()
		updateSinglePoolReward(poolInfos[pid])
		updateSinglePoolRewardPerShare(poolInfos[pid])
		updateUserReward(poolInfos[pid], msg.sender)
	{
		PoolInfo storage poolInfo = poolInfos[pid];

		if (amount > 0) {
			UserInfo storage userInfo = userInfos[pid][msg.sender];
			userInfo.amount = userInfo.amount.add(amount);
			userInfo.debt = userInfo.amount.mul(poolInfo.rewardPerShare).div(1e18);
			poolInfo.totalAmount = poolInfo.totalAmount.add(amount);
			address(poolInfo.token).safeTransferFrom(msg.sender, address(this), amount);
			emit Stake(poolInfo.token, msg.sender, amount);
		}
	}

	function withdraw(uint256 pid, uint256 amount)
		external
		virtual
		nonReentrant
		verifyPid(pid)
		updateAllPoolRewardPerShare()
		updateSinglePoolReward(poolInfos[pid])
		updateSinglePoolRewardPerShare(poolInfos[pid])
		updateUserReward(poolInfos[pid], msg.sender)
	{
		PoolInfo storage poolInfo = poolInfos[pid];

		if (amount > 0) {
			UserInfo storage userInfo = userInfos[pid][msg.sender];
			require(userInfo.amount >= amount, 'Insufficient balance');
			userInfo.amount = userInfo.amount.sub(amount);
			userInfo.debt = userInfo.amount.mul(poolInfo.rewardPerShare).div(1e18);
			poolInfo.totalAmount = poolInfo.totalAmount.sub(amount);
			address(poolInfo.token).safeTransfer(msg.sender, amount);
			emit Withdraw(poolInfo.token, msg.sender, amount);
		}
	}

	function claim(uint256 pid)
		external
		virtual
		nonReentrant
		verifyPid(pid)
		updateAllPoolRewardPerShare()
		updateSinglePoolReward(poolInfos[pid])
		updateSinglePoolRewardPerShare(poolInfos[pid])
		updateUserReward(poolInfos[pid], msg.sender)
	{
		PoolInfo storage poolInfo = poolInfos[pid];
		UserInfo storage userInfo = userInfos[pid][msg.sender];
		if (userInfo.reward > 0) {
			uint256 amount = userInfo.reward;
			userInfo.reward = 0;
			userInfo.totalIncome = userInfo.totalIncome.add(amount);
			address(token).safeTransfer(msg.sender, amount);
			emit Claimed(poolInfo.token, msg.sender, amount);
		}
	}

	function calculateIncome(uint256 pid, address userAddress) external view virtual verifyPid(pid) returns (uint256) {
		PoolInfo storage poolInfo = poolInfos[pid];
		UserInfo storage userInfo = userInfos[pid][userAddress];

		(uint256 _reward, uint256 _perShare) = currentAllPoolRewardShare();

		uint256 poolPendingReward = poolInfo.weight.mul(_perShare).div(1e18).sub(poolInfo.debt);
		_reward = poolInfo.reward.add(poolPendingReward);
		_perShare = poolInfo.rewardPerShare;

		if (block.timestamp > poolInfo.lastBlockTimeStamp && poolInfo.totalAmount > 0) {
			uint256 poolPendingShare = _reward.mul(1e18).div(poolInfo.totalAmount);
			_perShare = _perShare.add(poolPendingShare);
		}
		uint256 userReward = userInfo.amount.mul(_perShare).div(1e18).sub(userInfo.debt);
		return userInfo.reward.add(userReward);
	}

	function isClaimedFlashLoan(uint256 index, address user) public view returns (bool) {
		return claimedFlashLoanState[index][user];
	}

	function settleFlashLoan(
		uint256 index,
		uint256 amount,
		uint256 settleBlockNumber,
		bytes32 merkleRoot
	) external requireImpl updateAllPoolRewardPerShare() updateSinglePoolReward(flashloanPool) {
		require(index == merkleDistributors.length, 'index already exists');
		require(flashloanPool.reward >= amount, 'Insufficient reward funds');
		require(block.number >= settleBlockNumber, '!blockNumber');

		if (merkleDistributors.length > 0) {
			MerkleDistributor memory md = merkleDistributors[merkleDistributors.length - 1];
			require(md.settleBlocNumber < settleBlockNumber, '!settleBlocNumber');
		}

		flashloanPool.reward = flashloanPool.reward.sub(amount);
		merkleDistributors.push(MerkleDistributor(merkleRoot, index, amount, settleBlockNumber));
		emit SettleFlashLoan(merkleRoot, index, amount, settleBlockNumber);
	}

	function claimFlashLoan(
		uint256 index,
		uint256 amount,
		bytes32[] calldata proof
	) external {
		address user = msg.sender;
		require(merkleDistributors.length > index, 'Invalid index');
		require(!isClaimedFlashLoan(index, user), 'Drop already claimed.');
		MerkleDistributor storage merkleDistributor = merkleDistributors[index];
		require(merkleDistributor.amount >= amount, 'Not sufficient');
		bytes32 leaf = keccak256(abi.encodePacked(index, user, amount));
		require(MerkleProof.verify(proof, merkleDistributor.merkleRoot, leaf), 'Invalid proof.');
		merkleDistributor.amount = merkleDistributor.amount.sub(amount);
		claimedFlashLoanState[index][user] = true;
		address(token).safeTransfer(msg.sender, amount);
		emit Claimed(address(this), user, amount);
	}

	function addPool(address tokenAddr, uint256 weight) external virtual requireImpl updateAllPoolRewardPerShare() {
		require(weight >= 0 && tokenAddr != address(0) && tokenUsed[tokenAddr] == false, 'Check the parameters');
		uint256 pid = poolInfos.length;
		uint256 debt = weight.mul(rewardPerShare).div(1e18);
		poolInfos.push(PoolInfo(pid, tokenAddr, weight, 0, 0, block.timestamp, debt, 0));
		tokenOfPid[tokenAddr] = pid;
		tokenUsed[tokenAddr] = true;
		totalWeight = totalWeight.add(weight);
		emit AddPoolToken(tokenAddr, weight);
	}

	function _updatePool(PoolInfo storage poolInfo, uint256 weight) internal {
		totalWeight = totalWeight.sub(poolInfo.weight);
		poolInfo.weight = weight;
		poolInfo.debt = poolInfo.weight.mul(rewardPerShare).div(1e18);
		totalWeight = totalWeight.add(weight);
	}

	function updatePool(address tokenAddr, uint256 weight)
		external
		virtual
		requireImpl
		verifyPid(tokenOfPid[tokenAddr])
		updateAllPoolRewardPerShare()
		updateSinglePoolReward(poolInfos[tokenOfPid[tokenAddr]])
		updateSinglePoolRewardPerShare(poolInfos[tokenOfPid[tokenAddr]])
	{
		require(weight >= 0 && tokenAddr != address(0), 'Parameter error');
		PoolInfo storage poolInfo = poolInfos[tokenOfPid[tokenAddr]];
		require(poolInfo.token == tokenAddr, 'pool does not exist');
		_updatePool(poolInfo, weight);
		emit UpdatePoolToken(address(poolInfo.token), weight);
	}

	function updateFlashloanPool(uint256 weight)
		external
		virtual
		requireImpl
		updateAllPoolRewardPerShare()
		updateSinglePoolReward(flashloanPool)
	{
		require(weight >= 0, 'Parameter error');
		_updatePool(flashloanPool, weight);
		emit UpdatePoolToken(address(flashloanPool.token), weight);
	}
}
