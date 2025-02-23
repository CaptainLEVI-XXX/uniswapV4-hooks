// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";


contract DynamicFeeHook is BaseHook {
    using LPFeeLibrary for uint24;

   // keep track of the moving average gas price
    uint128 public movingAverageGasPrice;


    // Needed as the denominator to update it the next time based on the moving average formula
    uint104 public movingAverageGasPriceCount;

    // The default base fees we will charge
    uint24 public constant BASE_FEE = 5000; // 0.5%   == 

    error MustUseDynamicFee(); 

    constructor(IPoolManager _manager) BaseHook(_manager){
        // update gasPrice
        updateMovingAverage();
    }




    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal pure override returns (bytes4)
    {
        // `.isDynamicFee()` function comes from using
       // the `SwapFeeLibrary` for `uint24` 
        if(!key.fee.isDynamicFee()) revert MustUseDynamicFee();

        return this.beforeInitialize.selector;
    }

     function _beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        //if we want to change the fee for per block or for a longer time we can use poolManager.updateDynamicLPFee(key, fee);
        //{make sure the pool's key is set for update Dynamic fee}

        // in our case we just need to overirde a fee flag

        uint24 fee = getFee();
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, feeWithFlag);
    }


    function _afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
		// in after swap hook we just need to update the moving average 
        updateMovingAverage();
        return (this.afterSwap.selector, 0);
    }

    function updateMovingAverage() internal{

        uint128 gasPrice = uint128(tx.gasprice);

        // New Average = ((Old Average * # of Txns Tracked) + Current Gas Price) / (# of Txns Tracked + 1)
        movingAverageGasPrice =((movingAverageGasPrice * movingAverageGasPriceCount) + gasPrice) / (movingAverageGasPriceCount + 1);
        movingAverageGasPriceCount++; 

    }

    function getFee() internal view returns(uint24){
        uint128 gasPrice = uint128(tx.gasprice);

         // if gasPrice > movingAverageGasPrice * 1.1, then half the fees

        if(gasPrice > movingAverageGasPrice * 11/10) return BASE_FEE/2;

          // if gasPrice < movingAverageGasPrice * 0.9, then double the fees

        if(gasPrice < movingAverageGasPrice * 11/10) return BASE_FEE * 2;

        return BASE_FEE;
        
    }






}
