// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/utility/ISwapper.sol";
import "src/YSS.sol";

import "../plvGlp/plvGlpSwapper.sol";
import "./YPlvGlpVault.sol";

/// @notice Swaps YPlvGlp to Yama and vice versa
contract YPlvGlpSwapper is ISwapper, YPlvGlpModule {
    PlvGlpSwapper public plvGlpSwapper;
    YPlvGlpVault public yPlvGlp;
    IERC4626 public constant plvGlp = IERC4626(0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1);

    constructor(
        YSS _stablecoin,
        PlvGlpCustodian _plvGlpCustodian,
        PlvGlpSwapper _plvGlpSwapper,
        YPlvGlpVault _yPlvGlp
    ) YPlvGlpModule(_stablecoin, _plvGlpCustodian) {
        plvGlpSwapper = _plvGlpSwapper;
        yPlvGlp = _yPlvGlp;
    }

    /// @notice Sets the plvGlpSwapper address
    function setPlvGlpSwapper(PlvGlpSwapper _plvGlpSwapper) external onlyAllowlist {
        plvGlpSwapper = _plvGlpSwapper;
    }

    /// @notice Swaps YPlvGlp to Yama
    /// @param collateralAmount Amount of YPlvGlp to swap
    /// @param minOutputAmount Minimum amount of Yama to receive
    /// @return outputAmount Amount of Yama received
    function swapToYama(
        uint256 collateralAmount,
        uint256 minOutputAmount
    ) external checkEoaOrAuthorized returns (uint256 outputAmount) {
        yPlvGlp.transferFrom(msg.sender, address(this), collateralAmount);
        yPlvGlp.withdraw(collateralAmount);
        uint256 plvGlpAmount = plvGlp.balanceOf(address(this));
        plvGlp.approve(address(plvGlpSwapper), plvGlpAmount);
        outputAmount = plvGlpSwapper.swapToYama(plvGlpAmount, minOutputAmount);
        stablecoin.transfer(msg.sender, outputAmount);
    }

    /// @notice Swaps Yama to YplvGLP
    /// @param stablecoinAmount The amount of Yama to swap
    /// @param minOutputAmount Minimum plvGLP received
    /// @return outputAmount The amount of plvGLP received
    function swapToCollateral(
        uint256 stablecoinAmount,
        uint256 minOutputAmount
    ) external checkEoaOrAuthorized returns (uint256 outputAmount) {
        stablecoin.transferFrom(msg.sender, address(this), stablecoinAmount);
        stablecoin.approve(address(plvGlpSwapper), stablecoinAmount);
        uint256 plvGlpAmount = plvGlpSwapper.swapToCollateral(stablecoinAmount, minOutputAmount);
        plvGlp.approve(address(yPlvGlp), plvGlpAmount);
        yPlvGlp.deposit(plvGlpAmount);
        outputAmount = yPlvGlp.balanceOf(address(this));
        checkOutputAmount(minOutputAmount, outputAmount);
        yPlvGlp.transfer(msg.sender, outputAmount);
    }

    /// @notice Checks if output amount is sufficient
    /// @param minOutputAmount Minimum output amount
    /// @param outputAmount Output amount
    function checkOutputAmount(
        uint256 minOutputAmount,
        uint256 outputAmount
    ) internal pure {
        require(outputAmount >= minOutputAmount, "YPlvGlpSwapper: insufficient output amount");
    }
}