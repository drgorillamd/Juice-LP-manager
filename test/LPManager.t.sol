// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

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
        lpManager = new LPManager(WETH);

        // Money printer goes brrrr
        deal(address(USDC), caller, 100 ether);
        deal(caller, 100 ether);
    }

    function testExample() public {
        (, int24 _currentTick, , , , , ) = usdcWeth500.slot0();

        int24 _tickSpacing = usdcWeth500.tickSpacing();

        int24 _tickLower = _currentTick - _tickSpacing;
        int24 _tickUpper = _currentTick + _tickSpacing;

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

        lpManager.uniswapV3MintCallback(amounts, 0, _data);

        // lpManager.addLP{value: amounts}(
        //     usdcWeth500,
        //     _tickLower,
        //     _tickUpper,
        //     _liquidity,
        //     _data
        // );

        assertTrue(true);
    }
}
