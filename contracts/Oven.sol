//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import './libraries/TransferHelper.sol';
import './libraries/Upgradable.sol';
import './libraries/Convert.sol';
import './interfaces/IERC20Burnable.sol';
import './interfaces/IDetailedERC20.sol';

contract Oven is ReentrancyGuard, UpgradableProduct, Convert {
	using SafeMath for uint256;
	using TransferHelper for address;
	using Address for address;

	address public constant ZERO_ADDRESS = address(0);
	uint256 public EXCHANGE_PERIOD;

	address public friesToken;
	address public token;

	mapping(address => uint256) public depositedFriesTokens;
	mapping(address => uint256) public tokensInBucket;
	mapping(address => uint256) public realisedTokens;
	mapping(address => uint256) public lastDividendPoints;

	mapping(address => bool) public userIsKnown;
	mapping(uint256 => address) public userList;
	uint256 public nextUser;

	uint256 public totalSupplyFriesTokens;
	uint256 public buffer;
	uint256 public lastDepositBlock;

	uint256 public pointMultiplier = 10**18;

	// SHARE
	uint256 public totalDividendPoints;
	// DAI/USDT/USDC Income
	uint256 public unclaimedDividends;

	address public upgradeAddress;
	uint256 public upgradeTime;
	uint256 public upgradeAmount;

	mapping(address => bool) public whiteList;

	event UpgradeSettingUpdate(address upgradeAddress, uint256 upgradeTime, uint256 upgradeAmount);
	event Upgrade(address upgradeAddress, uint256 upgradeAmount);
	event ExchangerPeriodUpdated(uint256 newTransmutationPeriod);

	constructor(address _friesToken, address _token) public {
		friesToken = _friesToken;
		token = _token;
		EXCHANGE_PERIOD = 50;
	}

	///@return displays the user's share of the pooled friesTokens.
	function dividendsOwing(address account) public view returns (uint256) {
		uint256 newDividendPoints = totalDividendPoints.sub(lastDividendPoints[account]);
		return depositedFriesTokens[account].mul(newDividendPoints).div(pointMultiplier);
	}

	///@dev modifier to fill the bucket and keep bookkeeping correct incase of increase/decrease in shares
	modifier updateAccount(address account) {
		uint256 owing = dividendsOwing(account);
		if (owing > 0) {
			unclaimedDividends = unclaimedDividends.sub(owing);
			tokensInBucket[account] = tokensInBucket[account].add(owing);
		}
		lastDividendPoints[account] = totalDividendPoints;
		_;
	}
	///@dev modifier add users to userlist. Users are indexed in order to keep track of when a bond has been filled
	modifier checkIfNewUser() {
		if (!userIsKnown[msg.sender]) {
			userList[nextUser] = msg.sender;
			userIsKnown[msg.sender] = true;
			nextUser++;
		}
		_;
	}

	///@dev run the phased distribution of the buffered funds
	modifier runPhasedDistribution() {
		uint256 _lastDepositBlock = lastDepositBlock;
		uint256 _currentBlock = block.number;
		uint256 _toDistribute = 0;
		uint256 _buffer = buffer;

		// check if there is something in bufffer
		if (_buffer > 0) {
			// NOTE: if last deposit was updated in the same block as the current call
			// then the below logic gates will fail

			//calculate diffrence in time
			uint256 deltaTime = _currentBlock.sub(_lastDepositBlock);

			// distribute all if bigger than timeframe
			if (deltaTime >= EXCHANGE_PERIOD) {
				_toDistribute = _buffer;
			} else {
				//needs to be bigger than 0 cuzz solidity no decimals
				if (_buffer.mul(deltaTime) > EXCHANGE_PERIOD) {
					_toDistribute = _buffer.mul(deltaTime).div(EXCHANGE_PERIOD);
				}
			}

			// factually allocate if any needs distribution
			if (_toDistribute > 0) {
				// remove from buffer
				buffer = _buffer.sub(_toDistribute);

				// increase the allocation
				increaseAllocations(_toDistribute);
			}
		}

		// current timeframe is now the last
		lastDepositBlock = _currentBlock;
		_;
	}

	/// @dev A modifier which checks if whitelisted for minting.
	modifier onlyWhitelisted() {
		require(whiteList[msg.sender], '!whitelisted');
		_;
	}

	///@dev set the EXCHANGE_PERIOD variable
	///
	/// sets the length (in blocks) of one full distribution phase
	function setExchangePeriod(uint256 newExchangePeriod) public requireImpl {
		EXCHANGE_PERIOD = newExchangePeriod;
		emit ExchangerPeriodUpdated(EXCHANGE_PERIOD);
	}

	///@dev claims the base token after it has been exchange
	///
	///This function reverts if there is no realisedToken balance
	function claim() public nonReentrant {
		address sender = msg.sender;
		require(realisedTokens[sender] > 0);
		uint256 value = realisedTokens[sender];
		realisedTokens[sender] = 0;
		token.safeTransfer(sender, value);
	}

	///@dev Withdraws staked friesTokens from the exchange
	///
	/// This function reverts if you try to draw more tokens than you deposited
	///
	///@param amount the amount of friesTokens to unstake
	function unstake(uint256 amount) public nonReentrant runPhasedDistribution() updateAccount(msg.sender) {
		// by calling this function before transmuting you forfeit your gained allocation
		address sender = msg.sender;

		uint256 tokenAmount = convertTokenAmount(friesToken, token, amount);
		amount = convertTokenAmount(token, friesToken, tokenAmount);
		require(tokenAmount > 0, 'The amount is too small');

		require(depositedFriesTokens[sender] >= amount, 'unstake amount exceeds deposited amount');
		depositedFriesTokens[sender] = depositedFriesTokens[sender].sub(amount);
		totalSupplyFriesTokens = totalSupplyFriesTokens.sub(amount);
		friesToken.safeTransfer(sender, amount);
	}

	///@dev Deposits friesTokens into the exchange
	///
	///@param amount the amount of friesTokens to stake
	function stake(uint256 amount)
		public
		nonReentrant
		runPhasedDistribution()
		updateAccount(msg.sender)
		checkIfNewUser()
	{
		// precision
		uint256 tokenAmount = convertTokenAmount(friesToken, token, amount);
		amount = convertTokenAmount(token, friesToken, tokenAmount);
		require(tokenAmount > 0, 'The amount is too small');

		// requires approval of AlToken first
		address sender = msg.sender;
		//require tokens transferred in;
		friesToken.safeTransferFrom(sender, address(this), amount);
		totalSupplyFriesTokens = totalSupplyFriesTokens.add(amount);
		depositedFriesTokens[sender] = depositedFriesTokens[sender].add(amount);
	}

	function exchange() public nonReentrant runPhasedDistribution() updateAccount(msg.sender) {
		address sender = msg.sender;
		uint256 pendingz = tokensInBucket[sender]; //
		uint256 pendingzToFries = convertTokenAmount(token, friesToken, pendingz); // fries
		uint256 diff; // token

		require(pendingz > 0 && pendingzToFries > 0, 'need to have pending in bucket');

		tokensInBucket[sender] = 0;

		// check bucket overflow
		if (pendingzToFries > depositedFriesTokens[sender]) {
			diff = convertTokenAmount(friesToken, token, pendingzToFries.sub(depositedFriesTokens[sender]));
			// remove overflow
			pendingzToFries = depositedFriesTokens[sender];
			pendingz = convertTokenAmount(friesToken, token, pendingzToFries);
			require(pendingz > 0 && pendingzToFries > 0, 'need to have pending in bucket');
		}

		// decrease friesTokens
		depositedFriesTokens[sender] = depositedFriesTokens[sender].sub(pendingzToFries);

		// BURN friesTokens
		IERC20Burnable(friesToken).burn(pendingzToFries);

		// adjust total
		totalSupplyFriesTokens = totalSupplyFriesTokens.sub(pendingzToFries);

		// reallocate overflow
		increaseAllocations(diff);

		// add payout
		realisedTokens[sender] = realisedTokens[sender].add(pendingz);
	}

	function forceExchange(address toExchange)
		public
		nonReentrant
		runPhasedDistribution()
		updateAccount(msg.sender)
		updateAccount(toExchange)
	{
		//load into memory
		address sender = msg.sender;
		uint256 pendingz = tokensInBucket[toExchange];
		uint256 pendingzToFries = convertTokenAmount(token, friesToken, pendingz);
		// check restrictions
		require(pendingzToFries > depositedFriesTokens[toExchange], '!overflow');

		// empty bucket
		tokensInBucket[toExchange] = 0;

		address _toExchange = toExchange;

		// calculaate diffrence
		uint256 diff = convertTokenAmount(friesToken, token, pendingzToFries.sub(depositedFriesTokens[_toExchange]));

		// remove overflow
		pendingzToFries = depositedFriesTokens[_toExchange];

		// decrease friesTokens
		depositedFriesTokens[_toExchange] = 0;

		// BURN friesTokens
		IERC20Burnable(friesToken).burn(pendingzToFries);

		// adjust total
		totalSupplyFriesTokens = totalSupplyFriesTokens.sub(pendingzToFries);

		// reallocate overflow
		tokensInBucket[sender] = tokensInBucket[sender].add(diff);

		uint256 payout = convertTokenAmount(friesToken, token, pendingzToFries);

		// add payout
		realisedTokens[_toExchange] = realisedTokens[_toExchange].add(payout);

		// force payout of realised tokens of the toExchange address
		if (realisedTokens[_toExchange] > 0) {
			uint256 value = realisedTokens[_toExchange];
			realisedTokens[_toExchange] = 0;
			token.safeTransfer(_toExchange, value);
		}
	}

	function exit() public {
		exchange();
		uint256 toWithdraw = depositedFriesTokens[msg.sender];
		unstake(toWithdraw);
	}

	function exchangeAndClaim() public {
		exchange();
		claim();
	}

	function exchangeClaimAndWithdraw() public {
		exchange();
		claim();
		uint256 toWithdraw = depositedFriesTokens[msg.sender];
		unstake(toWithdraw);
	}

	/// @dev Distributes the base token proportionally to all alToken stakers.
	///
	/// This function is meant to be called by the Fries contract for when it is sending yield to the exchange.
	/// Anyone can call this and add funds, idk why they would do that though...
	///
	/// @param origin the account that is sending the tokens to be distributed.
	/// @param amount the amount of base tokens to be distributed to the exchange.
	function distribute(address origin, uint256 amount) public onlyWhitelisted runPhasedDistribution {
		token.safeTransferFrom(origin, address(this), amount);
		buffer = buffer.add(amount);
	}

	/// @dev Allocates the incoming yield proportionally to all alToken stakers.
	///
	/// @param amount the amount of base tokens to be distributed in the exchange.
	function increaseAllocations(uint256 amount) internal {
		if (totalSupplyFriesTokens > 0 && amount > 0) {
			totalDividendPoints = totalDividendPoints.add(amount.mul(pointMultiplier).div(totalSupplyFriesTokens));
			unclaimedDividends = unclaimedDividends.add(amount);
		} else {
			buffer = buffer.add(amount);
		}
	}

	/// @dev Gets the status of a user's staking position.
	///
	/// The total amount allocated to a user is the sum of pendingdivs and inbucket.
	///
	/// @param user the address of the user you wish to query.
	///
	/// returns user status

	function userInfo(address user)
		public
		view
		returns (
			uint256 depositedToken,
			uint256 pendingdivs,
			uint256 inbucket,
			uint256 realised
		)
	{
		uint256 _depositedToken = depositedFriesTokens[user];
		uint256 _toDistribute = buffer.mul(block.number.sub(lastDepositBlock)).div(EXCHANGE_PERIOD);
		if (block.number.sub(lastDepositBlock) > EXCHANGE_PERIOD) {
			_toDistribute = buffer;
		}
		uint256 _pendingdivs = 0;

		if (totalSupplyFriesTokens > 0) {
			_pendingdivs = _toDistribute.mul(depositedFriesTokens[user]).div(totalSupplyFriesTokens);
		}
		uint256 _inbucket = tokensInBucket[user].add(dividendsOwing(user));
		uint256 _realised = realisedTokens[user];
		return (_depositedToken, _pendingdivs, _inbucket, _realised);
	}

	/// @dev Gets the status of multiple users in one call
	///
	/// This function is used to query the contract to check for
	/// accounts that have overfilled positions in order to check
	/// who can be force exchange.
	///
	/// @param from the first index of the userList
	/// @param to the last index of the userList
	///
	/// returns the userList with their staking status in paginated form.
	function getMultipleUserInfo(uint256 from, uint256 to)
		public
		view
		returns (address[] memory theUserList, uint256[] memory theUserData)
	{
		uint256 i = from;
		uint256 delta = to - from;
		address[] memory _theUserList = new address[](delta); //user
		uint256[] memory _theUserData = new uint256[](delta * 2); //deposited-bucket
		uint256 y = 0;
		uint256 _toDistribute = buffer.mul(block.number.sub(lastDepositBlock)).div(EXCHANGE_PERIOD);
		if (block.number.sub(lastDepositBlock) > EXCHANGE_PERIOD) {
			_toDistribute = buffer;
		}
		for (uint256 x = 0; x < delta; x += 1) {
			_theUserList[x] = userList[i];
			_theUserData[y] = depositedFriesTokens[userList[i]];

			uint256 pending = 0;
			if (totalSupplyFriesTokens > 0) {
				pending = _toDistribute.mul(depositedFriesTokens[userList[i]]).div(totalSupplyFriesTokens);
			}

			_theUserData[y + 1] = dividendsOwing(userList[i]).add(tokensInBucket[userList[i]]).add(pending);
			y += 2;
			i += 1;
		}
		return (_theUserList, _theUserData);
	}

	/// @dev Gets info on the buffer
	///
	/// This function is used to query the contract to get the
	/// latest state of the buffer
	///
	/// @return _toDistribute the amount ready to be distributed
	/// @return _deltaBlocks the amount of time since the last phased distribution
	/// @return _buffer the amount in the buffer
	function bufferInfo()
		public
		view
		returns (
			uint256 _toDistribute,
			uint256 _deltaBlocks,
			uint256 _buffer
		)
	{
		_deltaBlocks = block.number.sub(lastDepositBlock);
		_buffer = buffer;
		_toDistribute = _buffer.mul(_deltaBlocks).div(EXCHANGE_PERIOD);
	}

	/// This function reverts if the caller is not governance
	///
	/// @param _toWhitelist the account to mint tokens to.
	/// @param _state the whitelist state.
	function setWhitelist(address _toWhitelist, bool _state) external requireImpl {
		whiteList[_toWhitelist] = _state;
	}

	/// @notice Ensure that oven is invalid first!! then upgradesetting could be called.
	function upgradeSetting(
		address _upgradeAddress,
		uint256 _upgradeTime,
		uint256 _upgradeAmount
	) external requireImpl {
		require(_upgradeAddress != address(0) && _upgradeAddress != address(this), '!upgradeAddress');
		require(_upgradeTime > block.timestamp, '!upgradeTime');
		require(_upgradeAmount > 0, '!upgradeAmount');

		upgradeAddress = _upgradeAddress;
		upgradeTime = _upgradeTime;
		upgradeAmount = _upgradeAmount;
		emit UpgradeSettingUpdate(upgradeAddress, upgradeTime, upgradeAmount);
	}

	/// @notice Operation notice!
	/// @notice The assets((DAI/USDT/USDC)) total value should be equal or more than user's fryUSD.
	/// @notice Require upgradeAmount <=  DAI/USDT/USDC - fryUSD
	function upgrade() external requireImpl {
		require(
			upgradeAddress != address(0) && upgradeAmount > 0 && block.timestamp > upgradeTime && upgradeTime > 0,
			'!upgrade'
		);
		token.safeApprove(upgradeAddress, upgradeAmount);
		Oven(upgradeAddress).distribute(address(this), upgradeAmount);
		upgradeAddress = address(0);
		upgradeAmount = 0;
		upgradeTime = 0;
		emit Upgrade(upgradeAddress, upgradeAmount);
	}
}