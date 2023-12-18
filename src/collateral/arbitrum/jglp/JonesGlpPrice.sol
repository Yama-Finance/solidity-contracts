// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/interfaces/IPriceSource.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";

interface IJGlpViewer {
    function getGlpRatio(uint256 _jGLP) external view returns (uint256);
}

/// @notice The GlpManager contract in the GMX protocol
interface GlpManager {
    function getPrice(bool maximize) external view returns (uint256);
}

/// @notice Returns the price of JGLP for the Yama protocol
contract JonesGlpPrice is IPriceSource {
    using PRBMathUD60x18 for uint256;
    
    IJGlpViewer public constant jglpViewer = IJGlpViewer(0xDd80AC29F4af69fBcAED52049480C7906b2F50Da);
    GlpManager public constant glpManager = GlpManager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);

    /// @notice Returns the price of JGLP in YAMA
    function price() external view override returns (uint256 jglpPrice) {
        return jglpViewer.getGlpRatio(1e18).mul(priceGLP());
    }

    /// @dev Obtains the GLP price directly from the GMX smart contract
    /// @notice Returns the price of GLP
    function priceGLP() internal view returns (uint256) {
        return glpManager.getPrice(false) / 10 ** 12;
    }
}