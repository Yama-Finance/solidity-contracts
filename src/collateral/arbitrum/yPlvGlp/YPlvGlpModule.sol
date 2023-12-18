// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./PlvGlpCustodian.sol";

abstract contract YPlvGlpModule is YSSModule {
    PlvGlpCustodian public plvGlpCustodian;

    /// @notice Makes sure the caller is an EOA or authorized
    modifier checkEoaOrAuthorized() {
        require(msg.sender == tx.origin || plvGlpCustodian.authorized(msg.sender), "YPlvGlpModule: unauthorized");
        _;
    }

    constructor(
        YSS _stablecoin,
        PlvGlpCustodian _plvGlpCustodian
    ) YSSModule(_stablecoin) {
        plvGlpCustodian = _plvGlpCustodian;
    }

    /// @notice Sets the plvGlpCustodian address
    function setPlvGlpCustodian(PlvGlpCustodian _plvGlpCustodian) external onlyAllowlist {
        plvGlpCustodian = _plvGlpCustodian;
    }
}