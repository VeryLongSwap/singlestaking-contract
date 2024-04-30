// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/PancakeFixedStaking.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract CounterTest is Test {
    PancakeFixedStaking public pancakeFixedStaking;
    TransparentUpgradeableProxy public transparentProxy;
    function setUp() public {
        pancakeFixedStaking = new PancakeFixedStaking();
        transparentProxy = new TransparentUpgradeableProxy(address(pancakeFixedStaking), address(this), "");
    }

    function test_checkowner() public {
        console.log(pancakeFixedStaking.owner());
    }
}
