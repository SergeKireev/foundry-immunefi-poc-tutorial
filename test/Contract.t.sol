// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "StakingV2/contracts/staking/StakingV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ContractTest is Test {
    using stdStorage for StdStorage;

    IERC20 yopToken = IERC20(0xAE1eaAE3F627AAca434127644371b67B18444051);
    StakingV2 staking = StakingV2(0x5B705d7c6362A73fD56D5bCedF09f4E40C2d3670);
    address attacker = address(1);

    function writeTokenBalance(
        address who,
        IERC20 token,
        uint256 amt
    ) internal {
        stdstore
            .target(address(token))
            .sig(token.balanceOf.selector)
            .with_key(who)
            .checked_write(amt);
    }

    function setUp() public {
        writeTokenBalance(attacker, yopToken, 500 ether);
    }

    function testExample() public {
        vm.startPrank(attacker);
        uint8 lock_duration_months = 1;
        yopToken.approve(address(staking), 500 ether);
        staking.stake(500 ether, lock_duration_months);
    }
}
