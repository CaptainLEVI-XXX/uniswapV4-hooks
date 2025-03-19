// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";

contract CSMM is BaseHook {
    using CurrencySettler for Currency;

    error PathNotAccessible();

    struct CallbackData {
        uint256 amountEach;
        Currency currency0;
        Currency currency1;
        address sender;
    }

    constructor(IPoolManager _manager) BaseHook(_manager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        internal
        pure
        override
        returns (bytes4)
    {
        revert PathNotAccessible();
    }

    function addLiquidity(PoolKey calldata params, uint256 amountEach) external {
        poolManager.unlock(abi.encode(CallbackData(amountEach, params.currency0, params.currency1, msg.sender)));
    }

    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        CallbackData memory callbackData = abi.decode(data, (CallbackData));

        callbackData.currency0.settle(poolManager, callbackData.sender, callbackData.amountEach, false);

        callbackData.currency1.settle(poolManager, callbackData.sender, callbackData.amountEach, false);

        callbackData.currency0.take(poolManager, address(this), callbackData.amountEach, true);
        callbackData.currency1.take(poolManager, address(this), callbackData.amountEach, true);

        return "";
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata data
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 amountInOutPositive =
            params.amountSpecified > 0 ? uint256(params.amountSpecified) : uint256(-params.amountSpecified);

        BeforeSwapDelta beforeSwapDelta =
            toBeforeSwapDelta(int128(-params.amountSpecified), int128(params.amountSpecified));

        if (params.zeroForOne) {
            //If user is selling Token 0 and buying Token 1
            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take claim tokens for that Token 0 from the PM and keep it in the hook to create an equivalent credit for ourselves

            key.currency0.take(poolManager, address(this), amountInOutPositive, true);

            // They will be receiving Token 1 from the PM, creating a credit of Token 1 in the PM
            // We will burn claim tokens for Token 1 from the hook so PM can pay the user

            key.currency1.settle(poolManager, address(this), amountInOutPositive, true);
        } else {
            key.currency1.take(poolManager, address(this), amountInOutPositive, true);

            key.currency0.settle(poolManager, address(this), amountInOutPositive, true);
        }

        return (this.beforeSwap.selector, beforeSwapDelta, 0);
    }
}
