// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-periphery/libraries/LiquidityAmounts.sol';
import 'uni-v3-core/libraries/TickMath.sol';
import 'uni-v3-core/libraries/Position.sol';
import 'sqrt/FixedPointMathLib.sol';

contract PoolManager {
  /// @inheritdoc IPoolManager
  IJBTokens public immutable price;

  /// @inheritdoc IPoolManager
  IERC20 public immutable token;

  /// @inheritdoc IPoolManager
  IUniswapV3Pool public pool;

  /// @inheritdoc IPoolManager
  uint24 public immutable fee;

  /// @inheritdoc IPoolManager
  int24 public tickSpacing;

  /// @inheritdoc IPoolManager
  uint256 public mintedPrice;

  /// @notice The sorted token0
  address internal immutable _token0;

  /// @notice The sorted token1
  address internal immutable _token1;

  /// @notice lower tick => Pool positions owned by this contract
  mapping(int24 => LiquidityPosition) internal _positionStorage;

  // @notice The lower tick of the current positions
  int24[] internal _positionsLowerTicks;

  /// @notice True if price token is the token0
  bool private immutable _isPriceToken0;

  /// @notice Address of the uni initializer
  address private constant _UNI_INITIALIZER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

  /// @notice Uniswap's maximum tick
  /// @dev Due to tick spacing, pools with different fees may have differences between _MAX_TICK and tickUpper. Use tickUpper to find the max tick of the pool
  int24 private constant _MAX_TICK = 887272;

  /// @dev payable constructor does not waste gas on checking msg.value
  constructor() payable {
    factory = IPoolManagerFactory(msg.sender);
    (fee, price, token, lockManager, strategyRegistry, tierManager) = factory.constructorArguments();
    (_token0, _token1) = address(token) < address(price) ? (address(token), address(price)) : (address(price), address(token));
    _isPriceToken0 = _token0 == address(price);
  }

  /// @inheritdoc IPoolManager
  function createInitialiseAndAddFullRangePositionIfNecessary(
    address _donor,
    uint256 _priceTokenAmount,
    uint256 _otherTokenAmount
  ) external {
    if (msg.sender != address(factory)) revert PoolManager_OnlyFactory();

    // Calculate the sqrtPrice using sqrt library
    uint160 _sqrtPriceX96 = uint160(
      _isPriceToken0
        ? FixedPointMathLib.sqrt(_otherTokenAmount / _priceTokenAmount) << 96
        : FixedPointMathLib.sqrt(_priceTokenAmount / _otherTokenAmount) << 96
    );

    // Initialize the pool using IPoolInitializer
    pool = IUniswapV3Pool(
      IPoolInitializer(_UNI_INITIALIZER).createAndInitializePoolIfNecessary(address(_token0), address(_token1), fee, _sqrtPriceX96)
    );
    tickSpacing = pool.tickSpacing();
    int24 _tickUpper = _MAX_TICK - (_MAX_TICK % tickSpacing);
    int24 _tickLower = -_tickUpper;

    uint128 _liquidity = LiquidityAmounts.getLiquidityForAmounts(
      _sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(_tickLower),
      TickMath.getSqrtRatioAtTick(_tickUpper),
      _isPriceToken0 ? _priceTokenAmount : _otherTokenAmount,
      _isPriceToken0 ? _otherTokenAmount : _priceTokenAmount
    );

    pool.mint(address(this), _tickLower, _tickUpper, _liquidity, abi.encode(_donor));

    _positionsLowerTicks.push(_tickLower);
    _positionStorage[_tickLower] = LiquidityPosition(_tickLower, _tickUpper, _liquidity);
  }

  /// @inheritdoc IPoolManager
  function updatePositions() external {
    IStrategy.PositionUpdate[] memory _positionsToUpdate = _positionUpdates();
    uint256 _positionIndex;
    uint256 _positionsCount = _positionsToUpdate.length;

    while (_positionIndex < _positionsCount) {
      if (_positionsToUpdate[_positionIndex].isMint) {
        // Lower tick serves as index in stored positions
        int24 _lowerTick = _positionsToUpdate[_positionIndex].lowerTick;
        LiquidityPosition memory _position = _positionStorage[_lowerTick];

        // New position
        if (_position.liquidity == 0) _positionsLowerTicks.push(_lowerTick);

        _positionStorage[_lowerTick] = LiquidityPosition(
          _lowerTick,
          _positionsToUpdate[_positionIndex].upperTick,
          _position.liquidity += _positionsToUpdate[_positionIndex].liquidity
        );

        pool.mint(
          address(this),
          _positionsToUpdate[_positionIndex].lowerTick, // int24
          _positionsToUpdate[_positionIndex].upperTick, // int24
          _positionsToUpdate[_positionIndex].liquidity, // uint128
          abi.encode(address(0)) // bytes calldata
        );
      } else {
        //TODO: DELETE POSITION IN THE ARRAY WHEN BURN
        pool.burn(
          _positionsToUpdate[_positionIndex].lowerTick, // int24
          _positionsToUpdate[_positionIndex].upperTick, // int24
          _positionsToUpdate[_positionIndex].liquidity // uint128
        );
      }

      unchecked {
        ++_positionIndex;
      }
    }
  }

  /// @inheritdoc IPoolManager
  function positionUpdates() external returns (IStrategy.PositionUpdate[] memory _updates) {
    _updates = _positionUpdates();
  }

  /// @inheritdoc IPoolManager
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

      uint256 _mintable = ITierManager(tierManager).mintableAmount(lockManager, IPoolManager(address(this)));

      if (mintedPrice > _mintable) revert PoolManager_OverlimitMint(_mintable, mintedPrice);

      _isPriceToken0 ? price.mint(address(pool), _amount0Owed) : price.mint(address(pool), _amount1Owed);
    } else {
      // called from createAndInitializePoolIfNecessary, should transferFrom PRICE and tokenA from donor
      if (_amount0Owed > 0) IERC20(_token0).transferFrom(_donor, address(pool), _amount0Owed);
      if (_amount1Owed > 0) IERC20(_token1).transferFrom(_donor, address(pool), _amount1Owed);
    }
  }

  /// @inheritdoc IPoolManager
  function collectFees(Position[] calldata _positions) external {}

  /// @notice Gets the relevant strategy from the registry and queries the positions that should be updated
  /// @dev Calls the strategy with `delegatecall` in order to share the `_ownedPositions`
  /// @return _updates List of positions that should be created/deleted/modified
  function _positionUpdates() internal virtual returns (IStrategy.PositionUpdate[] memory _updates) {
    IStrategy _strategy = strategyRegistry.getStrategy(token, fee);
    (bool _success, bytes memory _returnData) = address(_strategy).delegatecall(abi.encodeWithSelector(IStrategy.getPositionChanges.selector));
    if (!_success) revert PoolManager_getPositionChangesFail();
    _updates = abi.decode(_returnData, (IStrategy.PositionUpdate[]));
  }
}
