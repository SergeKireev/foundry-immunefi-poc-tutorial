// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "../../interfaces/roles/IGatekeeperable.sol";

/// @dev Add the `Gatekeeper` role.
///   Gatekeepers will help ensure the security of the vaults. They can set vault limits, pause deposits or withdraws.
///   For vaults that defined restricted access, they will be able to control the access to these vaults as well.
///   This contract also provides a `onlyGatekeeper` modifier to allow controlling access to functions of the contract.
abstract contract Gatekeeperable is IGatekeeperable, ContextUpgradeable {
  event GatekeeperUpdated(address _guardian);

  /// @notice the address of the guardian for the vault
  /// @dev This contract is used as part of the Vault contract and it is upgradeable.
  ///  which means any changes to the state variables could corrupt the data. Do not modify this at all.
  address public gatekeeper;

  /// @dev make sure msg.sender is the guardian or the governance
  modifier onlyGovernanceOrGatekeeper(address _governance) {
    _onlyGovernanceOrGatekeeper(_governance);
    _;
  }

  // solhint-disable-next-line no-empty-blocks
  constructor() {}

  /// @dev set the initial value for the gatekeeper. The deployer can not be the gatekeeper.
  /// @param _gatekeeper the default address of the guardian
  // solhint-disable-next-line func-name-mixedcase
  function __Gatekeeperable_init_unchained(address _gatekeeper) internal {
    require(_msgSender() != _gatekeeper, "invalid address");
    _updateGatekeeper(_gatekeeper);
  }

  // solhint-disable-next-line func-name-mixedcase
  function __Gatekeeperable_init(address _gatekeeper) internal {
    __Context_init();
    __Gatekeeperable_init_unchained(_gatekeeper);
  }

  ///@dev this can be used internally to update the gatekeep. If you want to expose it, create an external function in the implementation contract and call this.
  function _updateGatekeeper(address _gatekeeper) internal {
    require(_gatekeeper != address(0), "address is not valid");
    require(_gatekeeper != gatekeeper, "already the gatekeeper");
    gatekeeper = _gatekeeper;
    emit GatekeeperUpdated(_gatekeeper);
  }

  function _onlyGovernanceOrGatekeeper(address _governance) internal view {
    require((_msgSender() == _governance) || (gatekeeper != address(0) && gatekeeper == _msgSender()), "!authorised");
  }
}
