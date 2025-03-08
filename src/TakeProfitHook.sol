// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

// TAKE PROFIT HOOK is hook that take profit order for futures: Its a type of hook where user tells "I want to sell 1 ETH for 3500 USDC"
// given that current price of ETH is 3000USDC (assumption).abi

//MEchanism design:
// At very high level Our hook can
// 1: User can place an order
// 2: User can cancel that order if that order is not filled
// 3: Ability to withraw/Redeem token if the Order is executed

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

contract TakeProfitHook is BaseHook, ERC1155 {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using FixedPointMathLib for uint256;
    using StateLibrary for IPoolManager;

    error NotEnoughToCancel();
    error NothingToClaim();
    error NotEnoughToClaim();

    mapping(PoolId poolId => mapping(int24 tickToSellAt => mapping(bool zeroForOne => uint256 inputAmount))) public
        pendingOrders;
    mapping(PoolId poolId => int24 lastTick) lastTicks;

    mapping(uint256 positionId => uint256 claimsSupply) public claimsTotalSupply;
    mapping(uint256 positionId => uint256 outputClaimable) public claimableOutputToken;
    // constructor set up

    constructor(IPoolManager _manager) BaseHook(_manager) ERC1155("") {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
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

    function _afterInitialize(address, PoolKey calldata key, uint160, int24 tick) internal override returns (bytes4) {
        lastTicks[key.toId()] = tick;
        return (this.afterInitialize.selector);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // need to handle the case of recursion other wise Transaction can reach Block gAs limit
        if (sender == address(this)) return (this.afterSwap.selector, 0);
        bool tryMore = true;
        int24 currentTick;

        while (tryMore) {
            (tryMore, currentTick) = tryExecutingOrders(key, !params.zeroForOne);
        }
        lastTicks[key.toId()] = currentTick;
        return (this.afterSwap.selector, 0);
    }

    function tryExecutingOrders(PoolKey calldata key, bool executeZeroForOne) internal returns (bool, int24) {
        // there can be two case : whether currnet tick > last tick
        int24 lastTick = lastTicks[key.toId()];
        (, int24 currentTick,,) = poolManager.getSlot0(key.toId());
        int24 tickSpacing = key.tickSpacing;

        if (currentTick > lastTick) {
            for (int24 tick = lastTick; tick < currentTick; tick += tickSpacing) {
                uint256 inputAmount = pendingOrders[key.toId()][tick][executeZeroForOne];

                if (inputAmount > 0) {
                    executeOrder(key, tick, executeZeroForOne, inputAmount);
                    return (true, currentTick);
                }
            }
        } else {
            for (int24 tick = lastTick; tick > currentTick; tick -= tickSpacing) {
                uint256 inputAmount = pendingOrders[key.toId()][tick][executeZeroForOne];

                if (inputAmount > 0) {
                    executeOrder(key, tick, executeZeroForOne, inputAmount);
                    return (true, currentTick);
                }
            }
        }

        return (false, currentTick);
    }

    //Placing an order:
    function placeOrder(PoolKey calldata key, bool zeroForOne, int24 tickToSellAt, uint256 inputAmount)
        external
        returns (int24)
    {
        //1: get the usable tick
        //2: pending amount mapping has been created
        // 3: somewhere we need to create a way to get unique ID for each type of order
        //3: we need to mint some tokens to user which represents their order
        //4: transfer the right token from user to contract

        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);

        pendingOrders[key.toId()][tick][zeroForOne] += inputAmount;

        uint256 positionId = getPositionId(key, tick, zeroForOne);

        // also need to keep track the amount of token we are minting to a user

        claimsTotalSupply[positionId] += inputAmount;

        address sellToken = zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);

        _mint(msg.sender, positionId, inputAmount, "");

        // need to get the right token first

        IERC20(sellToken).transferFrom(msg.sender, address(this), inputAmount);

        return tick;
    }

    function getPositionId(PoolKey calldata key, int24 tick, bool zeroForOne)
        public
        pure
        returns (uint256 positionId)
    {
        return uint256(keccak256(abi.encode(key, tick, zeroForOne)));
    }

    // since we are not clear about the input tick we need to create a function which will give us the closest tick for the inputed tick params

    function getLowerUsableTick(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        // tick -120  spacing = 50
        int24 intervals = tick / tickSpacing; // 2

        if (tick < 0 && tick % tickSpacing != 0) intervals--;

        return intervals * tickSpacing;
    }

    // for canceling the order

    function cancelOrder(PoolKey calldata key, bool zeroForOne, int24 tickToSellAt, uint256 amountToCancel) external {
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);

        uint256 positionId = getPositionId(key, tick, zeroForOne);

        // check if the msg.sender has enough amount to these ERC1155 tokens of a particular psoitionId;

        uint256 positionToken = balanceOf(msg.sender, positionId);

        if (positionToken < amountToCancel) revert NotEnoughToCancel();

        pendingOrders[key.toId()][tick][zeroForOne] -= amountToCancel;

        claimsTotalSupply[positionId] -= amountToCancel;

        Currency tokenCurrency = zeroForOne ? key.currency0 : key.currency1;

        _burn(msg.sender, positionId, amountToCancel);

        tokenCurrency.transfer(msg.sender, amountToCancel);
    }

    // for redeeming the token:

    function redeem(PoolKey calldata key, bool zeroForOne, int24 tickToSellAt, uint256 inputAmountToClaimFor)
        external
    {
        int24 tick = getLowerUsableTick(tickToSellAt, key.tickSpacing);

        uint256 positionId = getPositionId(key, tick, zeroForOne);

        // if the no out claimable tokens are theere that means currently the order has not been filled.
        if (claimableOutputToken[positionId] == 0) revert NothingToClaim();

        uint256 positionTokens = balanceOf(msg.sender, positionId);
        // revert if the user doesn't have enough balance of ERC1155 tokens i.e representation tokens.
        if (inputAmountToClaimFor > positionTokens) revert NotEnoughToClaim();

        uint256 totalClaimableForPosition = claimableOutputToken[positionId];
        uint256 totalInputAmountForPosition = claimsTotalSupply[positionId];

        uint256 outputToken = inputAmountToClaimFor.mulDivDown(totalClaimableForPosition, totalInputAmountForPosition);

        claimableOutputToken[positionId] -= outputToken;
        claimsTotalSupply[positionId] -= inputAmountToClaimFor;

        _burn(msg.sender, positionId, inputAmountToClaimFor);

        Currency token = zeroForOne ? key.currency1 : key.currency0;
        token.transfer(msg.sender, outputToken);
    }

    ///we also need to create a excute order fucntion whoch can handle logic after the actual swap has happened

    function executeOrder(PoolKey calldata key, int24 tick, bool zeroForOne, uint256 inputAmount) internal {
        //  bool zeroForOne;
        // /// The desired input amount if negative (exactIn), or the desired output amount if positive (exactOut)
        // int256 amountSpecified;
        // /// The sqrt price at which, if reached, the swap will stop executing
        // uint160 sqrtPriceLimitX96;

        BalanceDelta delta = swapAndSettleBalances(
            key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                // since the swap is exact input for output swap , we will give a negative to it
                amountSpecified: -int256(inputAmount),
                // No slippage limits (maximum slippage possible)
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            })
        );

        pendingOrders[key.toId()][tick][zeroForOne] -= inputAmount;

        //get the output amount of tokens from balance Delta
        uint256 outputAmount = zeroForOne ? uint256(int256(delta.amount1())) : uint256(int256(delta.amount0()));

        uint256 positionId = getPositionId(key, tick, zeroForOne);
        //update the state of the contracts
        claimableOutputToken[positionId] += outputAmount;
    }

    function swapAndSettleBalances(PoolKey calldata key, IPoolManager.SwapParams memory params)
        internal
        returns (BalanceDelta delta)
    {
        delta = poolManager.swap(key, params, "");

        // if the swap is zero to one than there must two situation if
        if (params.zeroForOne) {
            if (delta.amount0() < 0) {
                _settle(key.currency0, uint128(-delta.amount0()));
            }
            if (delta.amount1() > 0) {
                _take(key.currency1, uint128(delta.amount1()));
            }
        } else {
            if (delta.amount1() < 0) {
                _settle(key.currency1, uint128(-delta.amount1()));
            }
            if (delta.amount0() > 0) {
                _take(key.currency0, uint128(delta.amount0()));
            }
        }
    }

    function _settle(Currency currency, uint128 amount) internal {
        // sync the pool manager : alert the pool manager regarding deposit
        poolManager.sync(currency);
        currency.transfer(address(poolManager), amount);
        poolManager.settle();
    }

    function _take(Currency currency, uint128 amount) internal {
        // take tokens out of the pool contract to out Hook contract
        poolManager.take(currency, address(this), amount);
    }
}
