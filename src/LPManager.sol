// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/Position.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/external/IWETH9.sol";

/**
    @title
    Generic LP manager for Uniswap V3
    
    @notice
    Provide a cheaper access to Uniswap V3 by avoiding minting the associated NFT.
    The positions are owned by this contract and are NOT transferable anymore
*/
contract LPManager {
    // The sole owner of this contract and associated positions
    address immutable owner;

    // Weth
    IWETH9 immutable WETH;

    constructor(IWETH9 _WETH) payable {
        owner = msg.sender;
        WETH = _WETH;
    }

    /**
    @notice
    Create a position/add liquidity to an existing position
    
    @dev
    Approval or msg.value should be set/use accordingly to the amounts desired
    The new position ticks and liquidity is NOT tracked by this contract, instead, use
    offchain accounting (like the Uniswap V3 subgraph, using the following query for instance:
    https://thegraph.com/hosted-service/subgraph/uniswap/uniswap-v3

        {
        positions(skip:0, where: {
            pool: "pool address in lowercase",
            owner: "this contract address"
        })
            {
                owner,
                liquidity,
                tickLower{
                tickIdx
                },
                tickUpper{
                tickIdx
                },
                
            }
        }
    
    @param _pool the uniswap pool address
    @param _tickLower the position lower tick
    @param _tickUpper the position upper tick
    @param _liquidity the liquidity to provide, based on price and amounts (get via a call to getLiquidityForAmounts or
           offchain computation
    @param _data the abi.encode of (address _factory, address _token0, address _token1, uint24 _fee)
    */
    function addLP(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _liquidity,
        bytes calldata _data
    ) external payable {
        _pool.mint(address(this), _tickLower, _tickUpper, _liquidity, _data);
    }

    /**
    @notice
    Interface for the Uniswap V3 method computing a liquidity based on current price and amounts
           
    @param _amount0 the amount of token0
    @param _amount1 the amount of token1
    @param _tickLower the position lower tick
    @param _tickUpper the position upper tick
    @param _pool the uniswap pool address
    @return _liquidity the liquidity based on price and amounts
    */
    function getLiquidityForAmounts(
        uint256 _amount0,
        uint256 _amount1,
        int24 _tickLower,
        int24 _tickUpper,
        IUniswapV3Pool _pool
    ) external view returns (uint128 _liquidity) {
        (uint160 _sqrtPriceX96, , , , , , ) = _pool.slot0();
        _liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(_tickLower),
            TickMath.getSqrtRatioAtTick(_tickUpper),
            _amount0,
            _amount1
        );
    }

    /**
    @notice
    Collect fees and remove liquidity from a position

    @dev
    To collect fees only, use an _amount of 0

    @param _amount the amount of liquidity to remove
    @param _tickLower the position lower tick
    @param _tickUpper the position upper tick
    @param _pool the uniswap pool address
    @param _token0 the pool token0
    @param _token1 the pool token0
    */
    function removeLP(
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _amount,
        IUniswapV3Pool _pool,
        IERC20 _token0,
        IERC20 _token1
    ) external {
        if (msg.sender != owner) revert();

        _pool.collect(
            owner,
            _tickLower,
            _tickUpper,
            type(uint128).max,
            type(uint128).max
        );

        (uint256 _amount0, uint256 _amount1) = _pool.burn(
            _tickLower,
            _tickUpper,
            _amount
        );

        _token0.transfer(owner, _amount0);
        _token1.transfer(owner, _amount1);
    }

    /**
    @notice sweep any dust stuck in this contract
    */
    function sweep(IERC20 _token) external {
        _token.transfer(owner, _token.balanceOf(address(this)));
        (bool success, ) = owner.call{value: address(this).balance}("");
        success; // Do nothing with returned status
    }

    /**
    @notice Uniswap V3 mint callback
    */
    function uniswapV3MintCallback(
        uint256 _amount0Owed,
        uint256 _amount1Owed,
        bytes calldata _data
    ) external {
        // access control: only a valid uniswap pool can be calling this
        (
            address caller,
            address _factory,
            address _token0,
            address _token1,
            uint24 _fee
        ) = abi.decode(_data, (address, address, address, address, uint24));

        address _pool = PoolAddress.computeAddress(
            _factory,
            PoolAddress.getPoolKey(_token0, _token1, _fee)
        );
        //if (msg.sender != _pool) revert();

        if (_amount0Owed > 0)
            if (_token0 == address(WETH)) {
                // ETH should have been passed with msg.value
                WETH.deposit{value: _amount0Owed}();
                WETH.transfer(_pool, _amount0Owed);
            } else IERC20(_token0).transferFrom(caller, _pool, _amount0Owed);

        if (_amount1Owed > 0)
            if (_token1 == address(WETH)) {
                WETH.deposit{value: _amount1Owed}();
                WETH.transfer(_pool, _amount1Owed);
            } else IERC20(_token1).transferFrom(caller, _pool, _amount1Owed);
    }
}
