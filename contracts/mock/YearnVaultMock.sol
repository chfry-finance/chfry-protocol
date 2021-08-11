//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/IYearnController.sol";
import "../libraries/TransferHelper.sol";

contract YearnVaultMock is ERC20 {
    using SafeMath for uint256;
    using TransferHelper for address;

    uint256 public min = 9500;
    uint256 public constant max = 10000;

    IYearnController public controller;
    address public token;

    constructor(address _token, address _controller)
        public
        ERC20("yEarn Mock", "yMOCK")
    {
        token = _token;
        controller = IYearnController(_controller);
        _setupDecimals(ERC20(_token).decimals());
    }

    function vdecimals() external view returns (uint8) {
        return decimals();
    }

    function balance() public view returns (uint256) {
        return
            ERC20(token).balanceOf(address(this)).add(
                controller.balanceOf(address(token))
            );
    }

    function available() public view returns (uint256) {
        return ERC20(token).balanceOf(address(this)).mul(min).div(max);
    }

    function earn() external {
        uint256 _bal = available();
        token.safeTransfer(address(controller), _bal);
        controller.earn(address(token), _bal);
    }

    function deposit(uint256 _amount) external returns (uint256) {
        uint256 _pool = balance();
        uint256 _before = ERC20(token).balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = ERC20(token).balanceOf(address(this));
        _amount = _after.sub(_before); // Additional check for deflationary tokens
        uint256 _shares = 0;
        if (totalSupply() == 0) {
            _shares = _amount;
        } else {
            _shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, _shares);
    }

    function withdraw(uint256 _shares, address _recipient)
        external
        returns (uint256)
    {
        uint256 _r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint256 _b = ERC20(token).balanceOf(address(this));
        if (_b < _r) {
            uint256 _withdraw = _r.sub(_b);
            controller.withdraw(address(token), _withdraw);
            uint256 _after = ERC20(token).balanceOf(address(this));
            uint256 _diff = _after.sub(_b);
            if (_diff < _withdraw) {
                _r = _b.add(_diff);
            }
        }

        token.safeTransfer(_recipient, _r);
    }

    function pricePerShare() external view returns (uint256) {
         return balance().mul(10 ** uint256(decimals())).div(totalSupply());
    } 

    function clear() external {
        token.safeTransfer(
            address(controller),
            ERC20(token).balanceOf(address(this))
        );
        controller.earn(address(token), ERC20(token).balanceOf(address(this)));
    }
}
