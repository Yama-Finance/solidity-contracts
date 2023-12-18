// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/interfaces/IPriceSource.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice The GlpManager contract in the GMX protocol
interface GlpManager {
    function getPrice(bool maximize) external view returns (uint256);
}

/// @notice Returns the price of plvGLP for the Yama protocol
contract PlvGlpPrice is IPriceSource {
    using PRBMathUD60x18 for uint256;
    IERC4626 public constant plvGlp = IERC4626(0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1);
    GlpManager public constant glpManager = GlpManager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);

    /// @notice Returns the price of plvGLP in GLP
    function price() external view returns (uint256) {
        return plvGlp.convertToAssets(PRBMathUD60x18.scale()).mul(priceGLP());
    }

    /// @dev Obtains the price directly from the GMX smart contract
    /// @notice Returns the price of GLP
    function priceGLP() internal view returns (uint256) {
        return glpManager.getPrice(false) / 10 ** 12;
    }
}