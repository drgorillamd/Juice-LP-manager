// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/Position.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "sqrt/FixedPointMathLib.sol";

contract LPManager {

  struct Position {
    int24 tickLower,
    int24 tickUpper,
    uint128 amount
  }

  IERC20 public immutable JBX;

  IERC20 public immutable WETH;

  // Pool=>Positions[]
  mapping(IUniswapV3Pool=>Position[]) public currentPositions;

  address immutable owner;

  constructor() payable {
    owner = msg.sender;
  }

  function addLP(
    IUniswapV3Pool pool,
  uint256 amount0,
    uint256 amount1
  ) external {

      int24 tickSpacing = pool.tickSpacing();
      () = pool.slot0();
      int24 _tickUpper = _MAX_TICK - (_MAX_TICK % tickSpacing);
      int24 _tickLower = -_tickUpper;

      uint128 _liquidity = LiquidityAmounts.getLiquidityForAmounts(
          ,
          TickMath.getSqrtRatioAtTick(_tickLower),
          TickMath.getSqrtRatioAtTick(_tickUpper),
          amount0,
          amount1
      );

      pool.mint(
          address(this),
          _tickLower,
          _tickUpper,
          _liquidity,
          abi.encode(_donor)
      );

      _positionsLowerTicks.push(_tickLower);
      _positionStorage[_tickLower] = LiquidityPosition(
          _tickLower,
          _tickUpper,
          _liquidity
      );
  }

  function uniswapV3MintCallback(
      uint256 _amount0Owed,
      uint256 _amount1Owed,
      bytes calldata _data
  ) external {
      if (msg.sender != address(pool)) revert PoolManager_OnlyPool();

      address _donor = abi.decode(_data, (address));

      if (_donor == address(0)) {
          // called from updatePositions, should mint needed PRICE
          mintedPrice += _isPriceToken0 ? _amount0Owed : _amount1Owed;

          uint256 _mintable = ITierManager(tierManager).mintableAmount(
              lockManager,
              IPoolManager(address(this))
          );

          if (mintedPrice > _mintable)
              revert PoolManager_OverlimitMint(_mintable, mintedPrice);

          _isPriceToken0
              ? price.mint(address(pool), _amount0Owed)
              : price.mint(address(pool), _amount1Owed);
      } else {
          // called from createAndInitializePoolIfNecessary, should transferFrom PRICE and tokenA from donor
          if (_amount0Owed > 0)
              IERC20(_token0).transferFrom(
                  _donor,
                  address(pool),
                  _amount0Owed
              );
          if (_amount1Owed > 0)
              IERC20(_token1).transferFrom(
                  _donor,
                  address(pool),
                  _amount1Owed
              );
      }
  }

  function collectFees(Position[] calldata _positions) external {}
}
