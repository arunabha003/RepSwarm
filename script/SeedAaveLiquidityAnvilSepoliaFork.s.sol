// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IWETH9Like {
    function deposit() external payable;
}

interface IAavePoolSupplyLike {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
}

/// @notice Best-effort Aave liquidity seeding for a local Anvil that forks Sepolia (chainId=31337).
/// @dev This is useful when you want flashloan-backed backruns to work deterministically in local E2E runs.
contract SeedAaveLiquidityAnvilSepoliaFork is Script {
    address internal constant AAVE_POOL_SEPOLIA = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address internal constant WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address internal constant DAI = 0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address who = vm.addr(pk);

        uint256 wethSupply = vm.envOr("AAVE_WETH_SUPPLY", uint256(10 ether));
        uint256 daiSupply = vm.envOr("AAVE_DAI_SUPPLY", uint256(100_000 ether));

        uint256 extraWethDeposit = vm.envOr("EXTRA_WETH_DEPOSIT", uint256(0));

        console.log("=== SeedAaveLiquidityAnvilSepoliaFork ===");
        console.log("Seeder:");
        console.log(who);
        console.log("Aave Pool:");
        console.log(AAVE_POOL_SEPOLIA);

        vm.startBroadcast(pk);

        if (extraWethDeposit > 0) {
            IWETH9Like(WETH).deposit{value: extraWethDeposit}();
        }

        // WETH
        if (wethSupply > 0) {
            require(IERC20(WETH).balanceOf(who) >= wethSupply, "insufficient WETH (deposit more first)");
            IERC20(WETH).approve(AAVE_POOL_SEPOLIA, wethSupply);
            (bool ok,) = AAVE_POOL_SEPOLIA.call(
                abi.encodeWithSelector(IAavePoolSupplyLike.supply.selector, WETH, wethSupply, who, 0)
            );
            require(ok, "Aave supply(WETH) failed");
        }

        // DAI
        if (daiSupply > 0) {
            require(IERC20(DAI).balanceOf(who) >= daiSupply, "insufficient DAI (fund first)");
            IERC20(DAI).approve(AAVE_POOL_SEPOLIA, daiSupply);
            (bool ok,) = AAVE_POOL_SEPOLIA.call(
                abi.encodeWithSelector(IAavePoolSupplyLike.supply.selector, DAI, daiSupply, who, 0)
            );
            require(ok, "Aave supply(DAI) failed");
        }

        vm.stopBroadcast();

        console.log("OK: seeded Aave liquidity");
    }
}

