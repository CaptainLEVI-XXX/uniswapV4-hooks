// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract CSMM is BaseHook {
    using CurrencySettler for Currency;

    error InvalidPath();

   struct CallbackData{
    uint256 amountEach;
    Currency token0;
    Currency token1;
    address sender;
   }


    constructor(IPoolManager _manager) BaseHook(_manager){}

     function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,               // don't allow adding liquidity normally
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,                       // change the swap logic to x+y=k
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,             //Allow before swap to return custom delta
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

       function _beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        pure
        internal
        override
        returns (bytes4)
    {
        revert InvalidPath();
    }

     function _beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
       /// @dev- todo 
    }


    function addLiquidity(PoolKey calldata key , uint256 amountEach) external {

        poolManager.unlock(abi.encode(CallbackData(amountEach,key.currency0,key.currency1,msg.sender)));

    }

    function _unlockCallback(bytes calldata data) internal override returns(bytes memory){
        
    }




     




}
