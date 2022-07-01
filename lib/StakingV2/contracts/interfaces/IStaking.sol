// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

interface IStaking {
  function totalWorkingSupply() external view returns (uint256);

  function workingBalanceOf(address _user) external view returns (uint256);
}

interface IStakingV2 {
  function stakeForUser(
    uint248 _amount,
    uint8 _lockPeriod,
    address _to
  ) external returns (uint256);

  function stakeAndBoostForUser(
    uint248 _amount,
    uint8 _lockPeriod,
    address _to,
    address[] calldata _vaultsToBoost
  ) external returns (uint256);
}
