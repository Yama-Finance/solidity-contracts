// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/utility/ISwapper.sol";
import "src/YSS.sol";
import "src/modules/templates/YSSModule.sol";

import "../jglp/JonesGlpSwapper.sol";
import "@beefy/contracts/vaults/BeefyVaultV7.sol";

/// @notice Swaps YSnrLlp to Yama and vice versa
contract YSJGlpSwapper is ISwapper, YSSModule {
    JonesGlpSwapper public jonesGlpSwapper;
    BeefyVaultV7 public ySJGlp;
    IERC20 public constant jGlp = IERC20(0x7241bC8035b65865156DDb5EdEf3eB32874a3AF6);
    
    constructor(
        YSS _stablecoin,
        JonesGlpSwapper _jonesGlpSwapper,
        BeefyVaultV7 _ySJGlp
    ) YSSModule(_stablecoin) {
        jonesGlpSwapper = _jonesGlpSwapper;
        ySJGlp = _ySJGlp;
    }

    /// @notice Sets the jonesGlpSwapper address
    function setJonesGlpSwapper(JonesGlpSwapper _jonesGlpSwapper) external onlyAllowlist {
        jonesGlpSwapper = _jonesGlpSwapper;
    }

    /// @notice Swaps YSnrLlp to Yama
    /// @param collateralAmount Amount of YSnrLlp to swap
    /// @param minOutputAmount Minimum amount of Yama to receive
    /// @return outputAmount Amount of Yama received
    function swapToYama(
        uint256 collateralAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount) {
        ySJGlp.transferFrom(msg.sender, address(this), collateralAmount);
        ySJGlp.withdraw(collateralAmount);
        uint256 jGlpAmount = jGlp.balanceOf(address(this));
        jGlp.approve(address(jonesGlpSwapper), jGlpAmount);
        outputAmount = jonesGlpSwapper.swapToYama(jGlpAmount, minOutputAmount);
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
        stablecoin.approve(address(jonesGlpSwapper), stablecoinAmount);
        uint256 jGlpAmount = jonesGlpSwapper.swapToCollateral(stablecoinAmount, minOutputAmount);
        jGlp.approve(address(ySJGlp), jGlpAmount);
        ySJGlp.deposit(jGlpAmount);
        outputAmount = ySJGlp.balanceOf(address(this));
        checkOutputAmount(minOutputAmount, outputAmount);
        ySJGlp.transfer(msg.sender, outputAmount);
    }
    /// @notice Checks if output amount is sufficient
    /// @param minOutputAmount Minimum output amount
    /// @param outputAmount Output amount
    function checkOutputAmount(
        uint256 minOutputAmount,
        uint256 outputAmount
    ) internal pure {
        require(outputAmount >= minOutputAmount, "YJonesGlpSwapper: insufficient output amount");
    }
}