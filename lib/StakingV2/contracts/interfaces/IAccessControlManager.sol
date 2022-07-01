// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

interface IAccessControlManager {
  function hasAccess(address _user, address _vault) external view returns (bool);
}
