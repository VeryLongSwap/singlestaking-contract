// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/PancakeFixedStaking.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract CounterTest is Test {
    address deployer = 0xDD47792c1A9f8F12a44c299f1be85FFD72A4B746;
    address owner = 0x0f7bF2e6BEbf3d352405B0f855d4B6fC6Fe50b3F;
    PancakeFixedStaking pancakeFixedStaking;
    TransparentUpgradeableProxy proxy;
    function setUp() public {
        vm.startPrank(deployer);
        pancakeFixedStaking = new PancakeFixedStaking();
        proxy = new TransparentUpgradeableProxy(address(pancakeFixedStaking), deployer, "");
        PancakeFixedStaking(payable(address(proxy))).initialize(owner, address(proxy));
        vm.stopPrank();
    }

    function test_checkOwner() view public {
        assertEq(PancakeFixedStaking(payable(address(proxy))).owner(), owner);
    }
}
