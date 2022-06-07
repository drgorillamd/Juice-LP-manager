// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/Position.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LPManager {
    struct Position {
        int24 tickLower;
        int24 tickUpper;
        uint128 amount;
    }

    // Pool=>Positions[]
    mapping(IUniswapV3Pool => Position[]) public currentPositions;

    address immutable owner;

    constructor() payable {
        owner = msg.sender;
    }

    function addLP(
        IUniswapV3Pool _pool,
        address token0,
        address token1,
        uint160 _sqrtPriceX96,
        uint256 _amount0,
        uint256 _amount1,
        int24 _tickLower,
        int24 _tickUpper
    ) external {
        uint128 _liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(_tickLower),
            TickMath.getSqrtRatioAtTick(_tickUpper),
            _amount0,
            _amount1
        );

        _pool.mint(
            address(this),
            _tickLower,
            _tickUpper,
            _liquidity,
            abi.encode(_pool, token0, token1)
        );

        currentPositions[_pool].push(
            Position({
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                amount: _liquidity
            })
        );
    }

    function uniswapV3MintCallback(
        uint256 _amount0Owed,
        uint256 _amount1Owed,
        bytes calldata _data
    ) external {
        (address _pool, address _token0, address _token1) = abi.decode(
            _data,
            (address, address, address)
        );
        if (msg.sender != _pool) revert();

        if (_amount0Owed > 0)
            IERC20(_token0).transferFrom(tx.origin, _pool, _amount0Owed);
        if (_amount1Owed > 0)
            IERC20(_token1).transferFrom(tx.origin, _pool, _amount1Owed);
    }

    function collectFees(Position[] calldata _positions) external {}
}
