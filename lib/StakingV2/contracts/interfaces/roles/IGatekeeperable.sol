// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

interface IGatekeeperable {
  function gatekeeper() external view returns (address);
}
