// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

interface IERC20Burnable {
    function burn(uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}
