// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/utility/ISwapper.sol";
import "src/YSS.sol";
import "src/modules/PegStabilityModule.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract ArbSwapper is ISwapper {
    using SafeERC20 for IERC20;
    
    YSS public immutable yama;
    PegStabilityModule public immutable psm;
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IERC20 public constant arb = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
    IERC20 public constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    uint24 public constant poolFee = 500;

    constructor(
        YSS _yama,
        PegStabilityModule _psm
    ) {
        yama = _yama;
        psm = _psm;
    }

    /// @notice Swaps ARB to Yama
    /// @param collateralAmount The amount of ARB to swap
    /// @param minOutputAmount Minimum Yama received
    /// @return outputAmount The amount of Yama received
    function swapToYama(
        uint256 collateralAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount) {
        // Swap ARB to USDT, routing through WETH
        arb.safeTransferFrom(msg.sender, address(this), collateralAmount);
        arb.safeApprove(address(swapRouter), collateralAmount);
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(arb, poolFee, weth, poolFee, usdt),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: collateralAmount,
                amountOutMinimum: 0
            });
        uint256 usdtAmount = swapRouter.exactInput(params);
        usdt.safeApprove(address(psm), usdtAmount);
        outputAmount = psm.deposit(usdtAmount);
        checkOutputAmount(minOutputAmount, outputAmount);
        yama.transfer(msg.sender, outputAmount);
    }

    /// @notice Swaps Yama to ARB
    /// @param yamaAmount The amount of Yama to swap
    /// @param minOutputAmount Minimum ARB received
    /// @return outputAmount The amount of ARB received
    function swapToCollateral(
        uint256 yamaAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount) {
        yama.transferFrom(msg.sender, address(this), yamaAmount);
        yama.approve(address(psm), yamaAmount);
        uint256 usdtAmount = psm.withdraw(yamaAmount);
        // Swap USDT to ARB, routing through WETH
        usdt.safeApprove(address(swapRouter), usdtAmount);
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(usdt, poolFee, weth, poolFee, arb),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: usdtAmount,
                amountOutMinimum: 0
            });
        outputAmount = swapRouter.exactInput(params);
        checkOutputAmount(minOutputAmount, outputAmount);
        arb.transfer(msg.sender, outputAmount);
    }

    /// @notice Checks if output amount is sufficient
    /// @param minOutputAmount Minimum output amount
    /// @param outputAmount Output amount
    function checkOutputAmount(
        uint256 minOutputAmount,
        uint256 outputAmount
    ) internal pure {
        require(outputAmount >= minOutputAmount, "ArbSwapper: insufficient output amount");
    }
}