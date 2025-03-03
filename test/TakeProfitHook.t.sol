// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {TakeProfitHook} from "../src/TakeProfitHook.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

contract TestTakeProfitHook is Test, Deployers {
    using CurrencyLibrary for Currency;

    Currency token0;
    Currency token1;

    TakeProfitHook hook;

    function setUp() public {
        //deploy v4-core
        deployFreshManagerAndRouters();
        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        (token0, token1) = deployMintAndApprove2Currencies();

        address hookAddress = address(uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG));

        deployCodeTo("TakeProfitHook", abi.encode(manager), hookAddress);

        hook = TakeProfitHook(hookAddress);

        // Approve our hook tokens to approve these tokens as well:

        MockERC20(Currency.unwrap(token0)).approve(address(hook), type(uint256).max);

        MockERC20(Currency.unwrap(token1)).approve(address(hook), type(uint256).max);

        //initialize these pools with these two tokens

        (key,) = initPool(token0, token1, hook, 3000, SQRT_PRICE_1_1);

        //add initial liquidity to the pool

        // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        // Some liquidity from -120 to +120 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        // some liquidity for full range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }
}
