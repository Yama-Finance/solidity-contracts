// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/modules/templates/YSSModule.sol";

/// @notice Used for jGLP redemptions
interface IJonesGlpVaultRouter {
    function redeemGlp(uint256 _shares, bool _compound) external returns (uint256);
}

/// @notice Used for jGLP deposits
interface IJGlpAdapter {
    function depositGlp(uint256 _assets, bool _compound) external returns (uint256);
}

/// @notice Mints/redeems jGLP on behalf of another contract
contract JonesGlpMinter is YSSModule {
    mapping(address account => bool authorizedToMint) public jGlpMinters;
    IERC20 public constant sGLP = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);
    IERC20 public constant jonesGlp = IERC20(0x7241bC8035b65865156DDb5EdEf3eB32874a3AF6);
    IJonesGlpVaultRouter public constant jonesRouter = IJonesGlpVaultRouter(
        0x2F43c6475f1ecBD051cE486A9f3Ccc4b03F3d713);
    IJGlpAdapter public constant jonesAdapter = IJGlpAdapter(
        0x42EfE3E686808ccA051A49BCDE34C5CbA2EBEfc1
    );

    constructor(YSS _stablecoin) YSSModule(_stablecoin) {}

    /// @notice Sets authorized jGLP minter
    /// @param _contract The contract address to authorize
    /// @param _authorizedToMint Whether the contract is authorized to mint jGLP
    function setAuthorizedJGlpMinter(
        address _contract,
        bool _authorizedToMint
    ) external onlyAllowlist {
        jGlpMinters[_contract] = _authorizedToMint;
    }

    /// @notice Mints jGLP
    /// @param _assets The amount of GLP to deposit
    /// @param _compound Whether to compound the GLP
    /// @return shares The amount of jGLP minted
    function depositGlp(
        uint256 _assets,
        bool _compound
    ) external returns (uint256 shares) {
        require(jGlpMinters[msg.sender], "JonesGlpMinter: Not authorized to mint jGLP");
        sGLP.transferFrom(msg.sender, address(this), _assets);
        sGLP.approve(address(jonesAdapter), _assets);
        shares = jonesAdapter.depositGlp(_assets, _compound);
        jonesGlp.transfer(msg.sender, shares);
    }

    /// @notice Redeems jGLP
    /// @param _shares The amount of jGLP to redeem
    /// @param _compound Whether to compound the GLP
    /// @return assets The amount of GLP received
    function redeemGlp(
        uint256 _shares,
        bool _compound
    ) external returns (uint256 assets) {
        require(jGlpMinters[msg.sender], "JonesGlpMinter: Not authorized to redeem jGLP");
        jonesGlp.transferFrom(msg.sender, address(this), _shares);
        assets = jonesRouter.redeemGlp(_shares, _compound);
        sGLP.transfer(msg.sender, assets);
    }
}