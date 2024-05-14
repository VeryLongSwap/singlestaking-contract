// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import { PancakeFixedStaking } from "../src/PancakeFixedStaking.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract PancakeFixedStakingScript is Script {
    // set deployer address
    address deployer = 0x944C6C8882012CcD4FFd2911a7F1fDC520c9a561;
    // set owner address
    address owner = 0xd6aFA58EE6Fa908bC5321c92704Af23A607cAAea;
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
