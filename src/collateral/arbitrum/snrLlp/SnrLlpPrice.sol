// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/interfaces/IPriceSource.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

interface ILiquidityCalculator {
    function getTrancheValue(address _tranche, bool _max) external view returns (uint256);
}

/// @notice Returns the price of snrLLP for the Yama protocol
contract SnrLlpPrice is IPriceSource {
    using PRBMathUD60x18 for uint256;
    IERC20 public constant lpToken = IERC20(0x5573405636F4b895E511C9C54aAfbefa0E7Ee458); // snrLlp
    ILiquidityCalculator public constant liquidityCalculator = ILiquidityCalculator(0xdC3a2422007fE2977Fe5D9392701c0a74181d4Ae);


    /// @notice Returns the price of snrLLP in Yama
    function price() external view returns (uint256) {
        uint256 trancheValue = liquidityCalculator.getTrancheValue(address(lpToken), true);
        uint256 lpSupply = lpToken.totalSupply();

        return (trancheValue / 1e12).div(lpSupply);
    }
}