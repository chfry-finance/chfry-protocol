// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libraries/Upgradable.sol";
import "./libraries/ConfigNames.sol";
import "./libraries/WhiteList.sol";
import "./libraries/TransferHelper.sol";
import "./CheeseToken.sol";
import "./CheeseFactory.sol";

contract CheesePrivateStakePool is WhiteList, ReentrancyGuard {
    event Stake(address indexed user, uint256 indexed amount);
    event Withdraw(address indexed user, uint256 indexed amount);
    event Claimed(address indexed user, uint256 indexed amount);
    event SetCheeseFactory(address indexed factory);
    event SetCheeseToken(address indexed token);

    using TransferHelper for address;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 amount;
        uint256 debt;
        uint256 reward;
        uint256 totalIncome;
    }

    CheeseToken public token;
    CheeseFactory public cheeseFactory;

    uint256 public lastBlockTimeStamp;
    uint256 public rewardPerShare;
    uint256 public totalStake;

    mapping(address => UserInfo) public userInfos;

    constructor(address cheeseFactory_, address token_) public {
        cheeseFactory = CheeseFactory(cheeseFactory_);
        token = CheeseToken(token_);
    }

    function setCheeseFactory(address cheeseFactory_) external requireImpl {
        cheeseFactory = CheeseFactory(cheeseFactory_);
        emit SetCheeseFactory(cheeseFactory_);
    }

    function setCheeseToken(address token_) external requireImpl {
        token = CheeseToken(token_);
        emit SetCheeseToken(token_);
    }

    function getUserInfo(address userAddress)
        external
        view
        virtual
        returns (
            uint256 amount,
            uint256 debt,
            uint256 reward,
            uint256 totalIncome
        )
    {
        UserInfo memory userInfo = userInfos[userAddress];
        return (
            userInfo.amount,
            userInfo.debt,
            userInfo.reward,
            userInfo.totalIncome
        );
    }

    function currentRewardShare()
        public
        view
        virtual
        returns (uint256 _reward, uint256 _perShare)
    {
        _reward = cheeseFactory.prePoolMint(ConfigNames.PRIVATE);
        _perShare = rewardPerShare;

        if (totalStake > 0) {
            _perShare = _perShare.add(_reward.mul(1e18).div(totalStake));
        }
        return (_reward, _perShare);
    }

    modifier updateRewardPerShare() {
        if (totalStake > 0 && block.timestamp > lastBlockTimeStamp) {
            (uint256 _reward, uint256 _perShare) = currentRewardShare();
            rewardPerShare = _perShare;
            lastBlockTimeStamp = block.timestamp;
            require(
                _reward == cheeseFactory.poolMint(ConfigNames.PRIVATE),
                "pool mint error"
            );
        }
        _;
    }

    modifier updateUserReward(address user) {
        UserInfo storage userInfo = userInfos[user];
        if (userInfo.amount > 0) {
            uint256 debt = userInfo.amount.mul(rewardPerShare).div(1e18);
            uint256 userReward = debt.sub(userInfo.debt);
            userInfo.reward = userInfo.reward.add(userReward);
            userInfo.debt = debt;
        }
        _;
    }

    function stake(uint256 amount)
        external
        virtual
        onlyWhitelisted
        nonReentrant
        updateRewardPerShare()
        updateUserReward(msg.sender)
    {
        if (amount > 0) {
            UserInfo storage userInfo = userInfos[msg.sender];
            userInfo.amount = userInfo.amount.add(amount);
            userInfo.debt = userInfo.amount.mul(rewardPerShare).div(1e18);
            totalStake = totalStake.add(amount);
            address(token).safeTransferFrom(msg.sender, address(this), amount);
            emit Stake(msg.sender, amount);
        }
    }

    function withdraw(uint256 amount)
        external
        virtual
        nonReentrant
        updateRewardPerShare()
        updateUserReward(msg.sender)
    {
        if (amount > 0) {
            UserInfo storage userInfo = userInfos[msg.sender];
            require(userInfo.amount >= amount, "Insufficient balance");
            userInfo.amount = userInfo.amount.sub(amount);
            userInfo.debt = userInfo.amount.mul(rewardPerShare).div(1e18);
            totalStake = totalStake.sub(amount);
            address(token).safeTransfer(msg.sender, amount);
            emit Withdraw(msg.sender, amount);
        }
    }

    function claim()
        external
        virtual
        nonReentrant
        updateRewardPerShare()
        updateUserReward(msg.sender)
    {
        UserInfo storage userInfo = userInfos[msg.sender];
        if (userInfo.reward > 0) {
            uint256 amount = userInfo.reward;
            userInfo.reward = 0;
            userInfo.totalIncome = userInfo.totalIncome.add(amount);
            address(token).safeTransfer(msg.sender, amount);
            emit Claimed(msg.sender, amount);
        }
    }

    function calculateIncome(address user)
        external
        view
        virtual
        returns (uint256)
    {
        UserInfo storage userInfo = userInfos[user];
        uint256 _rewardPerShare = rewardPerShare;

        if (block.timestamp > lastBlockTimeStamp && totalStake > 0) {
            (, _rewardPerShare) = currentRewardShare();
        }
        uint256 userReward = userInfo.amount.mul(_rewardPerShare).div(1e18).sub(userInfo.debt);
        return userInfo.reward.add(userReward);
    }
}
