// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../vaults/roles/Governable.sol";
import "../vaults/roles/Gatekeeperable.sol";

/// @dev Use this contract as the base for contracts that are going to be pauseable and upgradeable.
///  It exposes the common functions used by all these contracts (like Pause, Unpause, setGatekeeper etc) and make sure the right permissions are set for all these methods.
abstract contract BasePauseableUpgradeable is
  GovernableUpgradeable,
  Gatekeeperable,
  PausableUpgradeable,
  UUPSUpgradeable
{
  // solhint-disable-next-line no-empty-blocks
  constructor() {}

  // solhint-disable-next-line func-name-mixedcase
  function __BasePauseableUpgradeable_init(address _governance, address _gatekeeper) internal onlyInitializing {
    __Governable_init(_governance);
    __Gatekeeperable_init_unchained(_gatekeeper);
    __Pausable_init_unchained();
    __UUPSUpgradeable_init();
    __BasePauseableUpgradeable_init_unchained();
  }

  // solhint-disable-next-line func-name-mixedcase no-empty-blocks
  function __BasePauseableUpgradeable_init_unchained() internal onlyInitializing {}

  /// @notice Pause the contract. Can be called by either the governance or gatekeeper.
  function pause() external onlyGovernanceOrGatekeeper(governance) {
    _pause();
  }

  // @notice Unpause the contract. Can only be called by the governance.
  function unpause() external onlyGovernance {
    _unpause();
  }

  /// @notice Set the gatekeeper address of the contract
  function setGatekeeper(address _gatekeeper) external onlyGovernance {
    _updateGatekeeper(_gatekeeper);
  }

  // solhint-disable-next-line no-unused-vars no-empty-blocks
  function _authorizeUpgrade(address implementation) internal view override onlyGovernance {}
}
