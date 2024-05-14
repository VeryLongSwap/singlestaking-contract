// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/PancakeFixedStaking.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract CounterTest is Test {
    // set deployer address
    address deployer = 0xe71636e8A0a905Dfb863c2C76cf9E84428b62285;
    // set owner address
    address owner = 0xdD582e30e986a1a8d38cfd90c1eBd97DDcf8ab96;
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
