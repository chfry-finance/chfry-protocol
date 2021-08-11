// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/Upgradable.sol";
import "./TokenTimeRelease.sol";

/**
 * @dev A token holder contract that will allow a beneficiary to extract the
 * tokens after a given release time.
 *
 * Useful for simple vesting schedules like "advisors get all of their tokens
 * after 1 year".
 */
contract TokenTimeLockManager is UpgradableProduct {
    TokenTimeRelease[] public tokenTimeReleaseList;
    using TransferHelper for address;

    event CreateTokenTimeLock(
        address indexed timeLock,
        address beneficiary,
        uint256 amount,
        uint256 releaseTime
    );

    function create(
        IERC20 token_,
        address beneficiary_,
        uint256 amount_,
        uint256 releaseTime_
    ) external requireImpl {
        TokenTimeRelease tokenTimeRelease =
            new TokenTimeRelease(token_, beneficiary_, releaseTime_, amount_);
        tokenTimeReleaseList.push(tokenTimeRelease);
        address(token_).safeTransferFrom(
            msg.sender,
            address(tokenTimeRelease),
            amount_
        );
        tokenTimeRelease.initialize();
        emit CreateTokenTimeLock(
            address(tokenTimeRelease),
            beneficiary_,
            amount_,
            releaseTime_
        );
    }

    function getTokenTimeLocks()
        external
        view
        returns (
            uint256 count,
            uint256[] memory index,
            address[] memory lockAddress,
            address[] memory token,
            address[] memory beneficiary,
            uint256[] memory income,
            uint256[] memory total,
            uint256[] memory releaseTime
        )
    {
        count = tokenTimeReleaseList.length;
        lockAddress = new address[](count);
        token = new address[](count);
        beneficiary = new address[](count);
        index = new uint256[](count);
        income = new uint256[](count);
        total = new uint256[](count);
        releaseTime = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            TokenTimeRelease tokenTimeLock = tokenTimeReleaseList[i];
            index[i] = i;
            lockAddress[i] = address(tokenTimeLock);
            token[i] = address(tokenTimeLock.token());
            beneficiary[i] = tokenTimeLock.beneficiary();
            income[i] = tokenTimeLock.currentIncome();
            total[i] = tokenTimeLock._releaseTotalAmount();
            releaseTime[i] = tokenTimeLock.releaseTime();
        }

        return (
            count,
            index,
            lockAddress,
            token,
            beneficiary,
            income,
            total,
            releaseTime
        );
    }
}
