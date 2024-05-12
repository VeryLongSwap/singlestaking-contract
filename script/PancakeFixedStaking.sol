// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import { PancakeFixedStaking } from "../src/PancakeFixedStaking.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract CounterScript is Script {
    address deployer = 0xDD47792c1A9f8F12a44c299f1be85FFD72A4B746;
    address owner = 0x0f7bF2e6BEbf3d352405B0f855d4B6fC6Fe50b3F;
    PancakeFixedStaking pancakeFixedStaking;
    TransparentUpgradeableProxy proxy;
    function setUp() public {
    }
    function run() public {
        vm.startBroadcast(deployer);
        pancakeFixedStaking = new PancakeFixedStaking();
        proxy = new TransparentUpgradeableProxy(address(pancakeFixedStaking), deployer, "");
        PancakeFixedStaking(payable(address(proxy))).initialize(owner, address(proxy));
        vm.stopBroadcast();
    }
}
