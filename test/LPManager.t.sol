// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import "../src/LPManager.sol";
import "../src/interfaces/external/IWETH9.sol";

contract TestLPManager is Test {
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IWETH9 WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IUniswapV3Pool usdcWeth500 =
        IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);

    LPManager lpManager;

    address caller = address(69420);

    function setUp() public {
        vm.prank(caller);
        lpManager = new LPManager(WETH);

        // Money printer goes brrrr
        deal(address(USDC), caller, 100 ether);
        deal(caller, 100 ether);

        vm.label(address(USDC), "USDC");
        vm.label(address(WETH), "WETH");
        vm.label(address(usdcWeth500), "usdcWeth500");
        vm.label(address(lpManager), "lpManager");
        vm.label(address(caller), "caller");
    }

    function testCreateCenteredLP() public {
        (uint160 sqrtRatioX96, int24 _currentTick, , , , , ) = usdcWeth500
            .slot0();

        int24 _tickSpacing = usdcWeth500.tickSpacing();

        int24 _tickLower = (_currentTick - 1 * _tickSpacing) -
            (_currentTick % _tickSpacing);
        int24 _tickUpper = (_currentTick + 1 * _tickSpacing) +
            (_tickSpacing - (_currentTick % _tickSpacing));

        uint256 amounts = 1 ether;

        uint128 _liquidity = lpManager.getLiquidityForAmounts(
            amounts, //usdc
            amounts, //weth
            _tickLower,
            _tickUpper,
            usdcWeth500
        );

        bytes memory _data = abi.encode(
            caller,
            usdcWeth500.factory(),
            address(USDC),
            address(WETH),
            uint24(500)
        );

        vm.startPrank(caller);

        USDC.approve(address(lpManager), amounts);

        uint256 USDCBalanceBefore = USDC.balanceOf(caller);
        uint256 ETHBalanceBefore = caller.balance;

        lpManager.addLP{value: amounts}(
            usdcWeth500,
            _tickLower,
            _tickUpper,
            _liquidity,
            _data
        );

        vm.stopPrank();

        (
            uint256 amount0theoricForLiquidity,
            uint256 amount1theoricForLiquidity
        ) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(_tickLower),
                TickMath.getSqrtRatioAtTick(_tickUpper),
                _liquidity
            );

        assertApproxEqRel(
            USDCBalanceBefore - USDC.balanceOf(caller),
            amount0theoricForLiquidity,
            10E13 //0.000001%
        );
        assertApproxEqRel(
            ETHBalanceBefore - caller.balance,
            amount1theoricForLiquidity,
            10E13
        );
    }

    function testRemoveLP() public {
        (uint160 sqrtRatioX96, int24 _currentTick, , , , , ) = usdcWeth500
            .slot0();

        int24 _tickSpacing = usdcWeth500.tickSpacing();

        int24 _tickLower = (_currentTick - 1 * _tickSpacing) -
            (_currentTick % _tickSpacing);
        int24 _tickUpper = (_currentTick + 1 * _tickSpacing) +
            (_tickSpacing - (_currentTick % _tickSpacing));

        uint256 amounts = 1 ether;

        uint128 _liquidity = lpManager.getLiquidityForAmounts(
            amounts, //usdc
            amounts, //weth
            _tickLower,
            _tickUpper,
            usdcWeth500
        );

        bytes memory _data = abi.encode(
            caller,
            usdcWeth500.factory(),
            address(USDC),
            address(WETH),
            uint24(500)
        );

        vm.startPrank(caller);

        USDC.approve(address(lpManager), amounts);

        uint256 USDCBalanceBefore = USDC.balanceOf(caller);
        uint256 ETHBalanceBefore = caller.balance;

        lpManager.addLP{value: amounts}(
            usdcWeth500,
            _tickLower,
            _tickUpper,
            _liquidity,
            _data
        );

        uint256 USDCBalanceAfter = USDC.balanceOf(caller);
        uint256 ETHBalanceAfter = caller.balance;

        lpManager.removeLP(
            _tickLower,
            _tickUpper,
            _liquidity,
            usdcWeth500,
            USDC,
            WETH
        );

        vm.stopPrank();

        assertApproxEqRel(USDC.balanceOf(caller), USDCBalanceBefore, 10E13);
        assertApproxEqRel(WETH.balanceOf(caller), amounts, 10E13);
    }
}
