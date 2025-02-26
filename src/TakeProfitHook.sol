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
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TakeProfitHook is BaseHook, ERC1155 {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    error NotEnoughToCancel();

    mapping(PoolId poolId => mapping(int24 tickToSellAt => mapping(bool zeroForOne => uint256 inputAmount))) public
        pendingOrders;

    mapping(uint256 positionId => uint256 claimsSupply) public claimsTotalSupply;
    // constructor set up

    constructor(IPoolManager _manager, string memory _uri) BaseHook(_manager) ERC1155(_uri) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
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

    function _afterInitialize(address, PoolKey calldata, uint160, int24) internal override returns (bytes4) {
        return (this.afterInitialize.selector);
    }

    function _afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        return (this.afterSwap.selector, 0);
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
        internal
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
}
