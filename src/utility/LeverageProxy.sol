// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "../modules/FlashMintModule.sol";
import "../modules/CDPModule.sol";
import "./ISwapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../modules/templates/YSSModule.sol";


/// @notice A contract that sets up CDPs on behalf of a user to easily leverage up with flash loans
contract LeverageProxy is IERC3156FlashBorrower, YSSModule {
    using SafeERC20 for IERC20;
    using SafeERC20 for YSS;

    FlashMintModule public immutable flashMintModule;
    CDPModule public immutable cdpModule;

    mapping(uint256 collateralTypeId => IERC20 collateral) public collateralMapping;
    mapping(uint256 collateralTypeId => ISwapper swapper) public swappers;

    /// @notice Verifies that the caller is the owner of the vault
    /// @param vaultId Vault ID
    modifier onlyVaultOwner(uint256 vaultId) {
        require(cdpModule.getAltOwner(vaultId) == msg.sender, "Yama: Not vault owner");
        _;
    }

    /// @notice Initializes the module
    /// @param _stablecoin Stablecoin
    /// @param _flashMintModule Flash mint module
    /// @param _cdpModule CDP module
    constructor(
        YSS _stablecoin,
        FlashMintModule _flashMintModule,
        CDPModule _cdpModule
    ) YSSModule(_stablecoin) {
        flashMintModule = _flashMintModule;
        cdpModule = _cdpModule;
    }

    /// @notice Sets the collateral type config
    /// @param collateralTypeId Collateral type ID
    /// @param collateral Collateral token
    /// @param swapper Swapper
    function setCollateralTypeConfig(
        uint256 collateralTypeId,
        IERC20 collateral,
        ISwapper swapper
    ) external onlyAllowlist {
        swappers[collateralTypeId] = swapper;
        collateralMapping[collateralTypeId] = collateral;
    }

    /// @notice Leverages up a vault
    /// @param vaultId Vault ID
    /// @param yamaBorrowed Amount of Yama borrowed
    /// @param minCollatSwapped Minimum amount of collateral the Yama is swapped to
    function leverageUp(
        uint256 vaultId,
        uint256 yamaBorrowed,
        uint256 minCollatSwapped
    ) external onlyVaultOwner(vaultId) {
        flashMintModule.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(stablecoin),
            yamaBorrowed,
            encodeFlashLoanData(true, vaultId, minCollatSwapped, msg.sender)
        );
    }

    /// @notice Fully leverages down a vault by repaying all debt
    /// @param vaultId Vault ID
    /// @param collatSold Amount of collateral sold
    function leverageDownAll(
        uint256 vaultId,
        uint256 collatSold
    ) external onlyVaultOwner(vaultId) {
        cdpModule.updateInterest(cdpModule.getCollateralTypeId(vaultId));
        uint256 minYamaRepaid = cdpModule.getDebt(vaultId);
        leverageDown(vaultId, collatSold, minYamaRepaid);
    }

    /// @notice Creates a vault managed by this contract
    /// @param collateralTypeId Collateral type ID
    /// @param collatAmount Amount of collateral to add
    /// @return vaultId Vault ID
    function createVault(
        uint256 collateralTypeId,
        uint256 collatAmount
    ) external returns (uint256 vaultId) {
        IERC20 collateral = collateralMapping[collateralTypeId];
        collateral.safeTransferFrom(
            msg.sender,
            address(this),
            collatAmount
        );
        collateral.safeIncreaseAllowance(address(cdpModule), collatAmount);
        vaultId = cdpModule.createVault(
            collateralTypeId,
            collatAmount,
            msg.sender
        );
    }

    /// @notice Callback function for flash loans
    /// @param initiator Initiator of the flash loan
    /// @param token Token borrowed
    /// @param amount Amount borrowed
    /// @param fee Fee
    /// @param data Data
    /// @return hash keccak256("ERC3156FlashBorrower.onFlashLoan")
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32 hash) {
        token;
        require(msg.sender == address(flashMintModule), "SimpleLeverage: Not flashMintModule");
        require(initiator == address(this), "SimpleLeverage: Initiator not this");
        (
            bool isLeveragingUp,
            uint256 vaultId,
            uint256 collatAmount,
            address executor
        ) = decodeFlashLoanData(data);
        // Using the "fee" parameter to represent the collateral type ID to avoid stack limit
        fee = cdpModule.getCollateralTypeId(vaultId);
        IERC20 collateral = collateralMapping[fee];
        ISwapper swapper = swappers[fee];
        if (isLeveragingUp) {
            stablecoin.safeIncreaseAllowance(address(swapper), amount);
            uint256 outputCollatAmount = swapper.swapToCollateral(amount, collatAmount);
            collateral.safeIncreaseAllowance(address(cdpModule), outputCollatAmount);
            cdpModule.addCollateral(vaultId, outputCollatAmount);
            cdpModule.borrow(vaultId, amount);
        } else {
            cdpModule.repay(vaultId, amount);
            cdpModule.removeCollateral(vaultId, collatAmount);
            collateral.safeIncreaseAllowance(address(swapper), collatAmount);
            uint256 profit = swapper.swapToYama(collatAmount, amount) - amount;
            try cdpModule.repay(vaultId, profit) {} catch {
                stablecoin.safeTransfer(executor, profit);
            }
        }
        stablecoin.safeIncreaseAllowance(address(flashMintModule), amount);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @notice Leverages down a vault
    /// @param vaultId Vault ID
    /// @param collatSold Amount of collateral sold
    /// @param minYamaRepaid Minimum amount of Yama repaid
    function leverageDown(
        uint256 vaultId,
        uint256 collatSold,
        uint256 minYamaRepaid
    ) public onlyVaultOwner(vaultId) {
        flashMintModule.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(stablecoin),
            minYamaRepaid,
            encodeFlashLoanData(false, vaultId, collatSold, msg.sender)
        );
    }

    /// @notice Encodes flash loan data
    /// @param isLeveragingUp True if leveraging up
    /// @param vaultId Vault ID
    /// @param collatAmount Amount of collateral
    /// @param executor Executor
    function encodeFlashLoanData(
        bool isLeveragingUp,
        uint256 vaultId,
        uint256 collatAmount,
        address executor
    ) internal pure returns (bytes memory) {
        return abi.encode(
            isLeveragingUp,
            vaultId,
            collatAmount,
            executor
        );
    }

    /// @notice Decodes flash loan data
    /// @param data Data
    /// @return isLeveragingUp True if leveraging up
    /// @return vaultId Vault ID
    /// @return collatAmount Amount of collateral
    /// @return executor Executor
    function decodeFlashLoanData(
        bytes calldata data
    ) internal pure returns (
        bool isLeveragingUp,
        uint256 vaultId,
        uint256 collatAmount,
        address executor
    ) {
        return abi.decode(data, (bool, uint256, uint256, address));
    }
}