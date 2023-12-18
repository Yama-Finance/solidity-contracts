// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/utility/ISwapper.sol";
import "src/YSS.sol";
import "src/modules/templates/YSSModule.sol";

import "../snrLlp/SnrLlpSwapper.sol";
import "@beefy/contracts/vaults/BeefyVaultV7.sol";

/// @notice Swaps YSnrLlp to Yama and vice versa
contract YSnrLlpSwapper is ISwapper, YSSModule {
    SnrLlpSwapper public snrLlpSwapper;
    BeefyVaultV7 public ySnrLlp;
    IERC20 public constant snrLlp = IERC20(0x5573405636F4b895E511C9C54aAfbefa0E7Ee458);
    
    constructor(
        YSS _stablecoin,
        SnrLlpSwapper _snrLlpSwapper,
        BeefyVaultV7 _ySnrLlp
    ) YSSModule(_stablecoin) {
        snrLlpSwapper = _snrLlpSwapper;
        ySnrLlp = _ySnrLlp;
    }

    /// @notice Sets the snrLlpSwapper address
    function setSnrLlpSwapper(SnrLlpSwapper _snrLlpSwapper) external onlyAllowlist {
        snrLlpSwapper = _snrLlpSwapper;
    }

    /// @notice Swaps YSnrLlp to Yama
    /// @param collateralAmount Amount of YSnrLlp to swap
    /// @param minOutputAmount Minimum amount of Yama to receive
    /// @return outputAmount Amount of Yama received
    function swapToYama(
        uint256 collateralAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount) {
        ySnrLlp.transferFrom(msg.sender, address(this), collateralAmount);
        ySnrLlp.withdraw(collateralAmount);
        uint256 snrLlpAmount = snrLlp.balanceOf(address(this));
        snrLlp.approve(address(snrLlpSwapper), snrLlpAmount);
        outputAmount = snrLlpSwapper.swapToYama(snrLlpAmount, minOutputAmount);
        stablecoin.transfer(msg.sender, outputAmount);
    }

    /// @notice Swaps Yama to YSnrLlp
    /// @param stablecoinAmount The amount of Yama to swap
    /// @param minOutputAmount Minimum YSnrLlp received
    /// @return outputAmount The amount of YSnrLlp received
    function swapToCollateral(
        uint256 stablecoinAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount) {
        stablecoin.transferFrom(msg.sender, address(this), stablecoinAmount);
        stablecoin.approve(address(snrLlpSwapper), stablecoinAmount);
        uint256 snrLlpAmount = snrLlpSwapper.swapToCollateral(stablecoinAmount, minOutputAmount);
        snrLlp.approve(address(ySnrLlp), snrLlpAmount);
        ySnrLlp.deposit(snrLlpAmount);
        outputAmount = ySnrLlp.balanceOf(address(this));
        checkOutputAmount(minOutputAmount, outputAmount);
        ySnrLlp.transfer(msg.sender, outputAmount);
    }
    /// @notice Checks if output amount is sufficient
    /// @param minOutputAmount Minimum output amount
    /// @param outputAmount Output amount
    function checkOutputAmount(
        uint256 minOutputAmount,
        uint256 outputAmount
    ) internal pure {
        require(outputAmount >= minOutputAmount, "YSnrLlpSwapper: insufficient output amount");
    }
}