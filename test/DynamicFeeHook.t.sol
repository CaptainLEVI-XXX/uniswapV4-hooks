// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {DynamicFeeHook} from "../src/DynamicFeeHook.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import "forge-std/console.sol";

contract TestDynamicFeeHook is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    DynamicFeeHook hook;

    function setUp() public {
        //deploy v4-core
        deployFreshManagerAndRouters();

        // Deploy, mint tokens, and approve all periphery contracts for two tokens
        deployMintAndApprove2Currencies();

        address hookAddress =
            address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG));

        // Set gas price = 10 gwei and deploy our hook-----we are doing this step as initial gas price on local development start from 0 gwei
        vm.txGasPrice(10 gwei);

        deployCodeTo("DynamicFeeHook", abi.encode(manager), hookAddress);

        hook = DynamicFeeHook(hookAddress);

        // Initialize a pool
        (key,) = initPool(
            currency0,
            currency1,
            hook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // Set the `DYNAMIC_FEE_FLAG` in place of specifying a fixed fee
            SQRT_PRICE_1_1
        );

        // Add some liquidity
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 100 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_feeUpdatesWithGasPrice() public {
        // Set up our swap parameters
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -0.00001 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Current gas price is 10 gwei
        // Moving average should also be 10
        uint128 gasPrice = uint128(tx.gasprice);
        uint128 movingAverageGasPrice = hook.movingAverageGasPrice();
        uint104 movingAverageGasPriceCount = hook.movingAverageGasPriceCount();
        assertEq(gasPrice, 10 gwei);
        assertEq(movingAverageGasPrice, 10 gwei);
        assertEq(movingAverageGasPriceCount, 1);

        //conduct a swap at SAME gas fee  = 10 gwei

        uint256 balanceOfToken1Before = currency1.balanceOfSelf();

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        uint256 balaceOfToken1After = currency1.balanceOfSelf();

        uint256 outputFromBaseFeeSwap = balaceOfToken1After - balanceOfToken1Before;

        assertGt(balaceOfToken1After, balanceOfToken1Before);

        //our moving average shouldn't have changed just the count have incremented to 2;

        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();

        assertEq(movingAverageGasPrice, 10 gwei);
        assertEq(movingAverageGasPriceCount, 2);

        // conduct a swap at lower gas price it should take higher swap fees

        vm.txGasPrice(4 gwei);

        balanceOfToken1Before = currency1.balanceOfSelf();

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        balaceOfToken1After = currency1.balanceOfSelf();

        uint256 outputFromIncreasedFeeSwap = balaceOfToken1After - balanceOfToken1Before;

        assertGt(balaceOfToken1After, balanceOfToken1Before);

        //our moving average shouldnt have changed
        //movingAverageGasPrice = (10 * 2) + 4 / (2 + 1) => movingAverageGasPrice = 8 gwei;

        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();

        assertEq(movingAverageGasPrice, 8 gwei);
        assertEq(movingAverageGasPriceCount, 3);

        //at this stage this should also stage true

        assertGt(outputFromBaseFeeSwap, outputFromIncreasedFeeSwap);

        // conduct a swap at Higer gas price it should take higher swap fees

        vm.txGasPrice(12 gwei);

        balanceOfToken1Before = currency1.balanceOfSelf();

        swapRouter.swap(key, params, testSettings, ZERO_BYTES);

        balaceOfToken1After = currency1.balanceOfSelf();

        uint256 outputFromDecreasedFeeSwap = balaceOfToken1After - balanceOfToken1Before;

        assertGt(balaceOfToken1After, balanceOfToken1Before);

        //our moving average shouldnt have changed
        //movingAverageGasPrice = (8 * 3) + 12 / (3 + 1) => movingAverageGasPrice = 9 gwei;

        movingAverageGasPrice = hook.movingAverageGasPrice();
        movingAverageGasPriceCount = hook.movingAverageGasPriceCount();

        assertEq(movingAverageGasPrice, 9 gwei);
        assertEq(movingAverageGasPriceCount, 4);

        //at this stage this should also stage true

        assertGt(outputFromDecreasedFeeSwap, outputFromBaseFeeSwap);

        // 4. Check all the output amounts

        console.log("Base Fee Output", outputFromBaseFeeSwap);
        console.log("Increased Fee Output", outputFromIncreasedFeeSwap);
        console.log("Decreased Fee Output", outputFromDecreasedFeeSwap);
    }
}
