// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

contract PointsHook is BaseHook, ERC20 {
    // use currencylibrary and balanceDeltaLibrary to use some helper function
    // over currency and deltaBalance data type

    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    //Initialize the BaseHook and ERC20
    constructor(IPoolManager _manager, string memory name, string memory symbol)
        BaseHook(_manager)
        ERC20(name, symbol, 18)
    {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    //implementataion of afterSwap hook

    function _afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // we'll add the code here shortly

        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);

        if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);

        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 pointsIssued = ethSpendAmount / 5;
        _assignPoints(hookData, pointsIssued);
        return (this.afterSwap.selector, 0);
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        if (!key.currency0.isAddressZero()) return (this.afterAddLiquidity.selector, delta);

        uint256 pointsForAddingLiquidity = uint256(int256(-delta.amount0()));

        _assignPoints(hookData, pointsForAddingLiquidity);

        //add implememtation
        return (this.afterAddLiquidity.selector, delta);
    }

    function _assignPoints(bytes calldata hookData, uint256 points) internal {
        // if no data is passed in no point will be assigned
        if (hookData.length == 0) return;

        //extract the user from the calldata

        address user = abi.decode(hookData, (address));

        if (user == address(0)) return;

        _mint(user, points);
    }
}
