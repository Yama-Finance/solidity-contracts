// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/interfaces/IPriceSource.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";
import "./IBeefyVault.sol";

/// @notice The GlpManager contract in the GMX protocol
interface GlpManager {
    function getPrice(bool maximize) external view returns (uint256);
}

/// @notice Returns the price of mooGLP for the Yama protocol
contract MooGLPPrice is IPriceSource {
    using PRBMathUD60x18 for uint256;
    IBeefyVault public constant beefyVault = IBeefyVault(0x9dbbBaecACEDf53d5Caa295b8293c1def2055Adc);
    GlpManager public constant glpManager = GlpManager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);

    /// @notice Returns the price of mooGLP in YAMA
    function price() external view returns (uint256) {
        return beefyVault.getPricePerFullShare().mul(priceGLP());
    }

    /// @dev Obtains the price directly from the GMX smart contract
    /// @notice Returns the price of GLP
    function priceGLP() internal view returns (uint256) {
        return glpManager.getPrice(false) / 10 ** 12;
    }
}