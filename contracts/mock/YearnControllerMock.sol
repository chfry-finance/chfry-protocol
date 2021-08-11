//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/IYearnController.sol";
import "../libraries/TransferHelper.sol";

contract YearnControllerMock is IYearnController {
    using TransferHelper for address;
    using SafeMath for uint256;

    address public constant blackhole =
        0x000000000000000000000000000000000000dEaD;

    uint256 public withdrawalFee = 0;
    uint256 public constant withdrawalMax = 10000;

    function setWithdrawalFee(uint256 _withdrawalFee) external {
        withdrawalFee = _withdrawalFee;
    }

    function balanceOf(address _token)
        external
        view
        override
        returns (uint256)
    {
        return IERC20(_token).balanceOf(address(this));
    }

    function earn(address _token, uint256 _amount) external override {}

    function withdraw(address _token, uint256 _amount) external override {
        // uint256 _balance = IERC20(_token).balanceOf(address(this));
        uint _fee = _amount.mul(withdrawalFee).div(withdrawalMax);
        _token.safeTransfer(blackhole, _fee);
        _token.safeTransfer(msg.sender, _amount.sub(_fee));
        // _token.safeTransfer(msg.sender, _amount);
    }
}
