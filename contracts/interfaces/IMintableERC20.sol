// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;


interface IMintableERC20 {
  function mint(address _recipient, uint256 _amount) external;
  function burnFrom(address account, uint256 amount) external;
  function lowerHasMinted(uint256 amount)external;
}
