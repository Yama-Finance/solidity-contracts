// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/interfaces/IPriceSource.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";
import "src/collateral/arbitrum/jglp/JonesGlpPrice.sol";
import "@beefy/contracts/interfaces/beefy/IVault.sol";

/// @notice Returns the price of YsnrLLP
contract YSJGlpPrice is IPriceSource {
    using PRBMathUD60x18 for uint256;
    
    JonesGlpPrice public immutable jonesGlpPrice;
    IVault public immutable vault;

    constructor(JonesGlpPrice _jonesGlpPrice, IVault _vault) {
        jonesGlpPrice = _jonesGlpPrice;
        vault = _vault;
    }

    /// @notice Returns the price of YsnrLLP
    function price() external view override returns (uint256) {
        return jonesGlpPrice.price().mul(vault.getPricePerFullShare());
    }
}