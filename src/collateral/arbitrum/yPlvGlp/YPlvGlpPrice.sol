// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/interfaces/IPriceSource.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";
import "src/collateral/arbitrum/plvGlp/plvGlpPrice.sol";
import "@beefy/contracts/interfaces/beefy/IVault.sol";

/// @notice Returns the price of YPlvGlp
contract YPlvGlpPrice is IPriceSource {
    using PRBMathUD60x18 for uint256;
    
    PlvGlpPrice public immutable plvGlpPrice;
    IVault public immutable vault;

    constructor(PlvGlpPrice _plvGlpPrice, IVault _vault) {
        plvGlpPrice = _plvGlpPrice;
        vault = _vault;
    }

    /// @notice Returns the price of YPlvGlp
    function price() external view override returns (uint256) {
        return plvGlpPrice.price().mul(vault.getPricePerFullShare());
    }
}