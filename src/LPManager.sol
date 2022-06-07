// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/Position.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH9 is IERC20 {
    /// @notice Deposit ether to get wrapped ether
    function deposit() external payable;

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256) external;
}

contract LPManager {
    address immutable owner;

    IWETH9 immutable WETH;

    constructor(IWETH9 _WETH) payable {
        owner = msg.sender;
        WETH = _WETH;
    }

    function addLP(
        IUniswapV3Pool _pool,
        uint160 _sqrtPriceX96, // offchain reading to save one call
        uint256 _amount0,
        uint256 _amount1,
        int24 _tickLower,
        int24 _tickUpper,
        bytes calldata _data // abi.encode(address _factory, address _token0, address _token1, uint24 _fee)
    ) external payable {
        uint128 _liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(_tickLower),
            TickMath.getSqrtRatioAtTick(_tickUpper),
            _amount0,
            _amount1
        );

        _pool.mint(address(this), _tickLower, _tickUpper, _liquidity, _data);
    }

    function removeLP(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        IUniswapV3Pool pool,
        IERC20 token0,
        IERC20 token1
    ) external {
        if (msg.sender != owner) revert();

        pool.collect(
            owner,
            tickLower,
            tickUpper,
            type(uint128).max,
            type(uint128).max
        );

        (uint256 amount0, uint256 amount1) = pool.burn(
            tickLower,
            tickUpper,
            amount
        );

        token0.transfer(owner, amount0);
        token1.transfer(owner, amount1);
    }

    function collectFees(
        int24 tickLower,
        int24 tickUpper,
        IUniswapV3Pool pool
    ) external {
        if (msg.sender != owner) revert();

        pool.collect(
            owner,
            tickLower,
            tickUpper,
            type(uint128).max,
            type(uint128).max
        );
    }

    function sweep(IERC20 token) external {
        token.transfer(owner, token.balanceOf(address(this)));
        (bool success, ) = owner.call{value: address(this).balance}("");
        success; // Do not revert
    }

    function uniswapV3MintCallback(
        uint256 _amount0Owed,
        uint256 _amount1Owed,
        bytes calldata _data
    ) external {
        (address _factory, address _token0, address _token1, uint24 _fee) = abi
            .decode(_data, (address, address, address, uint24));

        address _pool = PoolAddress.computeAddress(
            _factory,
            PoolAddress.getPoolKey(_token0, _token1, _fee)
        );

        if (msg.sender != _pool) revert();

        if (_amount0Owed > 0) {
            if (_token0 == address(WETH)) {
                WETH.deposit{value: _amount0Owed}();
                WETH.transfer(_pool, _amount0Owed);
            } else IERC20(_token0).transferFrom(tx.origin, _pool, _amount0Owed);
        }
        if (_amount1Owed > 0)
            if (_token1 == address(WETH)) {
                WETH.deposit{value: _amount1Owed}();
                WETH.transfer(_pool, _amount1Owed);
            } else IERC20(_token1).transferFrom(tx.origin, _pool, _amount1Owed);
    }
}
