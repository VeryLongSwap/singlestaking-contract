// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import { PancakeFixedStaking } from "../src/PancakeFixedStaking.sol";
contract CounterScript is Script {
    address internal deployer;
    PancakeFixedStaking internal pancakeFixedStaking;
    function setUp() public {
        (deployer, ) = deriveRememberKey(vm.envString("MNEMONIC"), 0);
    }
    function run() public {
        vm.startBroadcast(deployer);
        pancakeFixedStaking = new PancakeFixedStaking();
        vm.stopBroadcast();
    }
}
