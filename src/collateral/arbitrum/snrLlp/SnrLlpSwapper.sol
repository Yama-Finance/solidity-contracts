// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/utility/ISwapper.sol";
import "src/YSS.sol";
import "src/modules/PegStabilityModule.sol";
import "./ILevelPool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract SnrLlpSwapper is ISwapper {
    struct BaseAsset {
        IERC20 token;
        bytes mintSwapPath;
        bytes redeemSwapPath;
    }
    YSS public immutable yama;
    PegStabilityModule public immutable psm;

    ILevelPool public constant levelPool = ILevelPool(0x32B7bF19cb8b95C27E644183837813d4b595dcc6);
    IERC20 public constant snrLlp = IERC20(0x5573405636F4b895E511C9C54aAfbefa0E7Ee458);
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IERC20 public constant arb = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);
    IERC20 public constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 public constant usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 public constant wbtc = IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);

    uint256 public constant poolId = 0;

    BaseAsset[] public baseAssets;


    constructor(
        YSS _yama,
        PegStabilityModule _psm,
        bool pushUsdtFirst
    ) {
        yama = _yama;
        psm = _psm;

        if (pushUsdtFirst) {
            baseAssets.push(BaseAsset({
                token: usdt,
                mintSwapPath: bytes(""),
                redeemSwapPath: bytes("")
            }));
        }
        baseAssets.push(BaseAsset({
            token: weth,
            mintSwapPath: abi.encodePacked(usdt, uint24(500), weth),
            redeemSwapPath: abi.encodePacked(weth, uint24(500), usdt)
        }));
        if (!pushUsdtFirst) {
            baseAssets.push(BaseAsset({
                token: usdt,
                mintSwapPath: bytes(""),
                redeemSwapPath: bytes("")
            }));
        }
        baseAssets.push(BaseAsset({
            token: wbtc,
            mintSwapPath: abi.encodePacked(usdt, uint24(500), weth, uint24(500), wbtc),
            redeemSwapPath: abi.encodePacked(wbtc, uint24(500), weth, uint24(500), usdt)
        }));
        baseAssets.push(BaseAsset({
            token: arb,
            mintSwapPath: abi.encodePacked(usdt, uint24(100), usdc, uint24(500), arb),
            redeemSwapPath: abi.encodePacked(arb, uint24(500), usdc, uint24(100), usdt)
        }));
        baseAssets.push(BaseAsset({
            token: usdc,
            mintSwapPath: abi.encodePacked(usdt, uint24(100), usdc),
            redeemSwapPath: abi.encodePacked(usdc, uint24(100), usdt)
        }));
    }

    /// @notice Swaps snrLlp to Yama
    /// @param collateralAmount Amount of snrLlp to swap
    /// @param minOutputAmount Minimum amount of Yama to receive
    /// @return outputAmount Amount of Yama received
    function swapToYama(
        uint256 collateralAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount) {
        snrLlp.transferFrom(msg.sender, address(this), collateralAmount);
        snrLlp.approve(address(levelPool), collateralAmount);
        BaseAsset memory baseAsset;
        uint256 i;
        for (i = 0; i < baseAssets.length; i++) {
            baseAsset = baseAssets[i];
            try levelPool.removeLiquidity(
                address(snrLlp),
                address(baseAsset.token),
                collateralAmount,
                0,
                address(this)
            ) {
                break;
            } catch {}
        }
        if (i == baseAssets.length) {
            revert("SnrLlpSwapper: No base asset works");
        }
        uint256 baseAssetAmount = baseAsset.token.balanceOf(address(this));
        uint256 usdtAmount;
        if (baseAsset.token != usdt) {
            baseAsset.token.approve(address(swapRouter), baseAssetAmount);
            ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: baseAsset.redeemSwapPath,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: baseAssetAmount,
                amountOutMinimum: 0
            });
            usdtAmount = swapRouter.exactInput(params);
        } else {
            usdtAmount = baseAssetAmount;
        }
        usdt.approve(address(psm), usdtAmount);
        outputAmount = psm.deposit(usdtAmount);
        checkOutputAmount(minOutputAmount, outputAmount);
        yama.transfer(msg.sender, outputAmount);
    }

    /// @notice Swaps Yama to snrLLP
    /// @param yamaAmount The amount of Yama to swap
    /// @param minOutputAmount Minimum snrLLP received
    /// @return outputAmount The amount of snrLLP received
    function swapToCollateral(
        uint256 yamaAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount) {
        yama.transferFrom(msg.sender, address(this), yamaAmount);
        yama.approve(address(psm), yamaAmount);
        uint256 usdtAmount = psm.withdraw(yamaAmount);
        uint256 i;
        for (i = 0; i < baseAssets.length; i++) {
            usdt.approve(address(this), usdtAmount);
            try this.swapToCollateralAndMint(usdtAmount, i, address(this)) {
                outputAmount = snrLlp.balanceOf(address(this));
                break;
            } catch {}
        }
        if (i == baseAssets.length) {
            revert("SnrLlpSwapper: No base asset works");
        }
        checkOutputAmount(minOutputAmount, outputAmount);
        snrLlp.transfer(msg.sender, outputAmount);
    }

    /// @notice Swaps USDT to a base asset and mints snrLLP
    /// @param usdtAmount The amount of USDT to swap
    /// @param baseAssetId The id of the base asset to swap to
    /// @param to The address to mint snrLLP to
    function swapToCollateralAndMint(
        uint256 usdtAmount,
        uint256 baseAssetId,
        address to
    ) external {
        usdt.transferFrom(msg.sender, address(this), usdtAmount);
        uint256 baseAssetAmount;
        if (baseAssets[baseAssetId].token != usdt) {
            usdt.approve(address(swapRouter), usdtAmount);
            ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: baseAssets[baseAssetId].mintSwapPath,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: usdtAmount,
                amountOutMinimum: 0
            });
            baseAssetAmount = swapRouter.exactInput(params);
        } else {
            baseAssetAmount = usdtAmount;
        }
        baseAssets[baseAssetId].token.approve(address(levelPool), baseAssetAmount);
        levelPool.addLiquidity(
            address(snrLlp),
            address(baseAssets[baseAssetId].token),
            baseAssetAmount,
            0,
            to
        );
    }


    /// @notice Checks if output amount is sufficient
    /// @param minOutputAmount Minimum output amount
    /// @param outputAmount Output amount
    function checkOutputAmount(
        uint256 minOutputAmount,
        uint256 outputAmount
    ) internal pure {
        require(outputAmount >= minOutputAmount, "SnrLlpSwapper: insufficient output amount");
    }
}
