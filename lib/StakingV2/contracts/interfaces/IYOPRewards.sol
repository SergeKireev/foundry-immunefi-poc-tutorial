// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

interface IYOPRewards {
  /// @notice Returns the current emission rate (per epoch) for vault rewards and the current number of epoch (start from 1).
  function rate() external view returns (uint256 _rate, uint256 _epoch);

  /// @notice Returns the current ratio of community emissions for vault users
  function vaultsRewardsWeight() external view returns (uint256);

  /// @notice Returns the current ratio of community emissions for staking users
  function stakingRewardsWeight() external view returns (uint256);

  /// @notice Set the ratios of community emission for vaults and staking respectively. Governance only. Should emit an event.
  function setRewardsAllocationWeights(uint256 _weightForVaults, uint256 _weightForStaking) external;

  /// @notice Get the weight of a Vault
  function perVaultRewardsWeight(address vault) external view returns (uint256);

  /// @notice Set the weights for vaults. Governance only. Should emit events.
  function setPerVaultRewardsWeight(address[] calldata vaults, uint256[] calldata weights) external;

  /// @notice Calculate the rewards for the given user in the given vault. Vaults Only.
  /// This should be called by every Vault every time a user deposits or withdraws.
  function calculateVaultRewards(address _user) external;

  /// @notice Calculate the rewards for the given stake id in the staking contract.
  function calculateStakingRewards(uint256 _stakeId) external;

  /// @notice Allow a user to claim the accrued rewards from both vaults and staking, and transfer the YOP tokens to the given account.
  function claimAll(address _to) external;

  /// @notice Calculate the unclaimed rewards for the calling user
  function allUnclaimedRewards(address _user)
    external
    view
    returns (
      uint256 totalRewards,
      uint256 vaultsRewards,
      uint256 stakingRewards
    );
}

interface IYOPRewardsV2 {
  function claimRewardsForStakes(uint256[] calldata _stakeIds) external returns (uint256, uint256[] memory);

  function claimVaultRewardsForUsers(address[] calldata _users) external returns (uint256, uint256[] memory);
}
