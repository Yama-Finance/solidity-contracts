// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./templates/YSSModuleExtended.sol";
import "../interfaces/IPriceSource.sol";
import "../interfaces/ICollateralManager.sol";
import "../interfaces/ILiquidator.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Manages the creation and maintenance of collateralized debt positions
/// (CDPs)
contract CDPModule is YSSModuleExtended {
  using SafeERC20 for IERC20;
  using PRBMathUD60x18 for uint256;

  struct Vault {
    uint256 collateralAmount;
    uint256 collateralTypeId;
    address owner;
    address altOwner;
    uint256 initialDebt;
    bool isLiquidated;
  }

  struct CollateralType {
    IERC20 token;
    IPriceSource priceSource;
    uint256 debtFloor;
    uint256 debtCeiling;
    uint256 collateralRatio;
    uint256 interestRate;  // Debt is multiplied by this value every second. 
    uint256 totalCollateral;
    uint256 lastUpdateTime;
    uint256 initialDebt;
    uint256 cumulativeInterest;
    bool borrowingEnabled;
    bool allowlistEnabled;
  }

  Vault[] public vaults;
  CollateralType[] public collateralTypes;

  /// @notice Called when collateral is added/removed from a vault
  /// @dev Allows governance to stake collateral to other protocols
  ICollateralManager public collateralManager;

  /// @notice A list of liquidators that can accept a liquidation
  ILiquidator[] public liquidators;

  bool public borrowingDisabled;

  mapping(uint256 collateralTypeId => mapping(address borrower => bool isAllowed)) allowedBorrowers;

  mapping(address account => uint256[] ownedVaults) public ownedVaults;

  /// @notice Emitted when a vault's debt is set
  /// @param account The account that owns the vault
  /// @param vaultId The vault's ID
  /// @param debt The new debt amount
  /// @param initialDebt The vault's initial debt amount
  event SetDebt(
    address indexed account,
    uint256 indexed vaultId,
    uint256 debt,
    uint256 initialDebt
  );

  /// @notice Emitted when an account borrows against a vault
  /// @param account The account that borrowed
  /// @param vaultId The vault's ID
  /// @param amount The amount borrowed
  event Borrow(
    address indexed account,
    uint256 indexed vaultId,
    uint256 amount
  );

  /// @notice Emitted when an account repays a vault's debt
  /// @param account The account that repaid
  /// @param vaultId The vault's ID
  /// @param amount The amount repaid
  event Repay(
    address indexed account,
    uint256 indexed vaultId,
    uint256 amount
  );

  /// @notice Emitted when an account adds collateral to a vault
  /// @param account The account that added collateral
  /// @param vaultId The vault's ID
  /// @param amount The amount of collateral added
  event AddCollateral(
    address indexed account,
    uint256 indexed vaultId,
    uint256 amount
  );

  /// @notice Emitted when an account removes collateral from a vault
  /// @param account The account that removed collateral
  /// @param vaultId The vault's ID
  /// @param amount The amount of collateral removed
  event RemoveCollateral(
    address indexed account,
    uint256 indexed vaultId,
    uint256 amount
  );

  /// @notice Emitted when a vault is created
  /// @param owner The account that owns the vault
  /// @param vaultId The vault's ID
  /// @param collateralTypeId The ID of the vault's collateral type
  /// @param collateralAmount The amount of collateral deposited
  /// @param altOwner Another account that can control the vault
  event CreateVault(
    address indexed owner,
    uint256 indexed vaultId,
    uint256 indexed collateralTypeId,
    uint256 collateralAmount,
    address altOwner
  );

  /// @notice Emitted when a vault is liquidated
  /// @param initiator The account that initiated the liquidation
  /// @param liquidated The account that owns the vault
  /// @param vaultId The vault's ID
  /// @param liquidator The account that liquidated the vault
  event Liquidate(
    address indexed initiator,
    address indexed liquidated,
    uint256 indexed vaultId,
    address liquidator
  );

  /// @notice Emitted when a collateral type is added
  /// @param collateralTypeId The ID of the collateral type
  /// @param token The collateral token
  /// @param priceSource The price source for the collateral token
  /// @param debtFloor The minimum amount of debt that can be borrowed
  /// @param debtCeiling The maximum amount of debt that can be borrowed
  /// @param collateralRatio The ratio of collateral to debt
  /// @param interestRate The interest rate for the collateral type
  /// @param borrowingEnabled Whether borrowing is enabled for the collateral type
  /// @param allowlistEnabled Whether the allowlist is enabled for the collateral type
  event AddCollateralType(
    uint256 indexed collateralTypeId,
    address indexed token,
    address priceSource,
    uint256 debtFloor,
    uint256 debtCeiling,
    uint256 collateralRatio,
    uint256 interestRate,
    bool borrowingEnabled,
    bool allowlistEnabled
  );

  /// @notice Emitted when a collateral type is updated
  /// @param collateralTypeId The ID of the collateral type
  /// @param token The collateral token
  /// @param priceSource The price source for the collateral token
  /// @param debtFloor The minimum amount of debt that can be borrowed
  /// @param debtCeiling The maximum amount of debt that can be borrowed
  /// @param collateralRatio The ratio of collateral to debt
  /// @param interestRate The interest rate for the collateral type
  /// @param borrowingEnabled Whether borrowing is enabled for the collateral type
  /// @param allowlistEnabled Whether the allowlist is enabled for the collateral type
  event SetCollateralType(
    uint256 indexed collateralTypeId,
    address indexed token,
    address priceSource,
    uint256 debtFloor,
    uint256 debtCeiling,
    uint256 collateralRatio,
    uint256 interestRate,
    bool borrowingEnabled,
    bool allowlistEnabled
  );

  /// @notice Emitted when a collateral type's interest rate is updated
  /// @param collateralTypeId The ID of the collateral type
  /// @param interestRate The interest rate for the collateral type
  /// @param lastUpdateTime The last time the interest rate was updated
  /// @param cumulativeInterest The cumulative interest
  event UpdateInterest(
    uint256 indexed collateralTypeId,
    uint256 interestRate,
    uint256 lastUpdateTime,
    uint256 cumulativeInterest
  );

  /// @notice Emitted when a liquidated vault is written off
  /// @param vaultId The vault's ID
  event ClearVault(uint256 indexed vaultId);

  /// @notice Verifies that msg.sender owns the vault
  /// @param vaultId The vault's ID
  modifier onlyVaultOwner(uint256 vaultId) {
    require(vaults[vaultId].owner == msg.sender
      || vaults[vaultId].altOwner == msg.sender, "Yama: Must be vault owner");
    _;
  }

  /// @notice Verifies that the vault is not liquidated
  /// @param vaultId The vault's ID
  modifier notLiquidated(uint256 vaultId) {
    require(!vaults[vaultId].isLiquidated, "Yama: Vault already liquidated");
    _;
  }

  /// @notice Initializes the module
  /// @param _stablecoin The YSS contract
  /// @param _balanceSheet The BalanceSheet contract
  /// @param _collateralManager The CollateralManager contract
  constructor(
    YSS _stablecoin,
    BalanceSheetModule _balanceSheet,
    ICollateralManager _collateralManager
  ) YSSModuleExtended(_stablecoin, _balanceSheet) {
    setCollateralManager(_collateralManager);
  }

  /// @notice Creates a vault
  /// @param collateralTypeId The ID of the vault's collateral type
  /// @param collateralAmount The amount of collateral to deposit
  /// @param altOwner Another account that can control the vault
  /// @return vaultId The vault's ID
  function createVault(
    uint256 collateralTypeId,
    uint256 collateralAmount,
    address altOwner
  ) external returns (uint256 vaultId) {
    Vault memory vault;
    vault.collateralTypeId = collateralTypeId;
    vault.owner = msg.sender;
    vault.altOwner = altOwner;
    vaults.push(vault);
    vaultId = vaults.length - 1;

    ownedVaults[msg.sender].push(vaultId);
    if (altOwner != address(0)) {
      ownedVaults[altOwner].push(vaultId);
    }

    emit CreateVault(
      msg.sender,
      vaultId,
      collateralTypeId,
      collateralAmount,
      altOwner
    );
    addCollateral(vaultId, collateralAmount);
  }

  /// @notice Liquidates a vault
  /// @param vaultId The vault's ID
  function liquidate(uint256 vaultId) notLiquidated(vaultId) external {
    Vault storage vault = vaults[vaultId];
    updateInterest(vault.collateralTypeId);
    require(underCollateralized(vaultId), "Yama: Vault not undercollateralized");
    for (uint256 i = 0; i < liquidators.length; i++) {
      if (liquidators[i].liquidate(vaultId)) {
        vault.isLiquidated = true;
        emit Liquidate(
          msg.sender,
          vault.owner,
          vaultId,
          address(liquidators[i])
        );
        return;
      }
    }
    revert("Yama: No liquidator accepted the liquidation");
  }

  /// @notice Used by allowlist contracts to transfer tokens out
  /// @param token The token to transfer
  /// @param to The recipient
  /// @param amount The amount to transfer
  function transfer(
    IERC20 token,
    address to,
    uint256 amount
  ) external onlyAllowlist {
    token.safeTransfer(to, amount);
  }
  
  /// @notice Adds a collateral type
  /// @param token The collateral token
  /// @param priceSource The price source for the collateral token
  /// @param debtFloor The minimum amount of debt that can be borrowed for each vault
  /// @param debtCeiling The maximum amount of debt that can be borrowed by everyone cumulatively
  /// @param collateralRatio The ratio of collateral to debt
  /// @param interestRate The interest rate for the collateral type
  /// @param borrowingEnabled Whether borrowing is enabled for the collateral type
  /// @param allowlistEnabled Whether the allowlist is enabled for the collateral type
  /// @return collateralTypeId The ID of the new collateral type
  function addCollateralType(
    IERC20 token,
    IPriceSource priceSource,
    uint256 debtFloor,
    uint256 debtCeiling,
    uint256 collateralRatio,
    uint256 interestRate,
    bool borrowingEnabled,
    bool allowlistEnabled
  ) external onlyAllowlist returns (uint256 collateralTypeId) {
    CollateralType memory newCollateralType = CollateralType(
      token,
      priceSource,
      debtFloor,
      debtCeiling,
      collateralRatio,
      interestRate,
      0,
      block.timestamp,
      0,
      PRBMathUD60x18.SCALE,
      borrowingEnabled,
      allowlistEnabled
    );
    collateralTypes.push(newCollateralType);
    collateralTypeId = collateralTypes.length - 1;
    emit AddCollateralType(
      collateralTypeId,
      address(token),
      address(priceSource),
      debtFloor,
      debtCeiling,
      collateralRatio,
      interestRate,
      borrowingEnabled,
      allowlistEnabled
    );
  }

  /// @notice Sets a collateral type's parameters
  /// @param collateralTypeId The ID of the collateral type
  /// @param priceSource The price source for the collateral token
  /// @param debtFloor The minimum amount of debt that can be borrowed for each vault
  /// @param debtCeiling The maximum amount of debt that can be borrowed by everyone cumulatively
  /// @param collateralRatio The ratio of collateral to debt
  /// @param interestRate The interest rate for the collateral type
  /// @param borrowingEnabled Whether borrowing is enabled for the collateral type
  /// @param allowlistEnabled Whether the allowlist is enabled for the collateral type
  function setCollateralType(
    uint256 collateralTypeId,
    IPriceSource priceSource,
    uint256 debtFloor,
    uint256 debtCeiling,
    uint256 collateralRatio,
    uint256 interestRate,
    bool borrowingEnabled,
    bool allowlistEnabled
  ) external onlyAllowlist {
    CollateralType storage newCollateralType
      = collateralTypes[collateralTypeId];
    newCollateralType.priceSource = priceSource;
    newCollateralType.debtFloor = debtFloor;
    newCollateralType.debtCeiling = debtCeiling;
    newCollateralType.collateralRatio = collateralRatio;
    newCollateralType.interestRate = interestRate;
    newCollateralType.borrowingEnabled = borrowingEnabled;
    newCollateralType.allowlistEnabled = allowlistEnabled;
    emit SetCollateralType(
      collateralTypeId,
      address(newCollateralType.token),
      address(priceSource),
      debtFloor,
      debtCeiling,
      collateralRatio,
      interestRate,
      borrowingEnabled,
      allowlistEnabled
    );
  }

  /// @notice Sets an allowed borrower for a vault
  /// @param collateralTypeId The ID of the collateral type
  /// @param borrower The borrower
  /// @param isAllowed Whether the borrower is allowed
  function setAllowedBorrower(
    uint256 collateralTypeId, address borrower, bool isAllowed
  ) external onlyAllowlist {
    allowedBorrowers[collateralTypeId][borrower] = isAllowed;
  }

  /// @notice Borrows from a vault
  /// @param vaultId The vault's ID
  /// @param amount The amount to borrow
  function borrow(
    uint256 vaultId,
    uint256 amount
  ) external onlyVaultOwner(vaultId) notLiquidated(vaultId) {
    require(!borrowingDisabled, "Yama: Borrowing disabled");
    CollateralType storage cType = getCollateralType(vaultId);
    uint256 cTypeId = vaults[vaultId].collateralTypeId;
    require(cType.borrowingEnabled, "Yama: Collateral type disabled");
    if (cType.allowlistEnabled) {
      require(allowedBorrowers[cTypeId][msg.sender],
        "Yama: Not allowed borrower");
    }
    updateInterest(cTypeId);
    uint256 newDebt = getDebt(vaultId) + amount;
    requireValidDebtAmount(vaultId, newDebt);

    setDebt(vaultId, newDebt);

    require(getTotalDebt(cTypeId)
      <= cType.debtCeiling, "Yama: Debt ceiling exceeded");
    stablecoin.mint(msg.sender, amount);

    emit Borrow(msg.sender, vaultId, amount);
  }

  /// @notice Repays a vault
  /// @param vaultId The vault's ID
  /// @param amount The amount to repay
  function repay(
    uint256 vaultId,
    uint256 amount
  ) external onlyVaultOwner(vaultId) notLiquidated(vaultId) {
    updateInterest(vaults[vaultId].collateralTypeId);
    uint256 newDebt = getDebt(vaultId) - amount;
    requireValidDebtAmount(vaultId, newDebt);
    stablecoin.burn(msg.sender, amount);
    setDebt(vaultId, newDebt);

    emit Repay(msg.sender, vaultId, amount);
  }

  /// @notice Removes collateral from a vault
  /// @param vaultId The vault's ID
  /// @param amount The amount to remove
  function removeCollateral(
    uint256 vaultId,
    uint256 amount
  ) external onlyVaultOwner(vaultId) notLiquidated(vaultId) {
    updateInterest(vaults[vaultId].collateralTypeId);
    collateralManager.handleCollateralWithdrawal(vaultId, amount);
    vaults[vaultId].collateralAmount -= amount;
    getCollateralType(vaultId).totalCollateral -= amount;
    require(!underCollateralized(vaultId), "Yama: Vault undercollateralized");
    getCollateralType(vaultId).token.safeTransfer(msg.sender, amount);

    emit RemoveCollateral(msg.sender, vaultId, amount);
  }

  /// @notice Used to write off liquidated vaults
  /// @dev Sets collateral to 0 and debt to 0, doesn't call balance sheet
  /// @param vaultId The vault's ID
  function clearVault(uint256 vaultId) external onlyAllowlist {
    Vault storage vault = vaults[vaultId];
    updateInterest(vault.collateralTypeId);
    CollateralType storage cType = getCollateralType(vaultId);
    collateralManager.handleCollateralWithdrawal(
      vaultId, vault.collateralAmount);
    cType.totalCollateral -= vault.collateralAmount;
    vault.collateralAmount = 0;
    setDebt(vaultId, 0);

    emit ClearVault(vaultId);
  }

  /// @notice Sets the liquidators for this module
  /// @param _liquidators The liquidators
  function setLiquidators(
    ILiquidator[] memory _liquidators
  ) external onlyAllowlist {
    liquidators = _liquidators;
  }

  /// @notice Used to enable/disable borrowing.
  /// @param value Whether to enable/disable borrowing
  function setBorrowingDisabled(
    bool value
  ) external onlyAllowlist {
    borrowingDisabled = value;
  }

  /// @notice Determines if a vault has been liquidated
  /// @param vaultId The vault's ID
  function isLiquidated(uint256 vaultId) external view returns (bool) {
    return vaults[vaultId].isLiquidated;
  }

  /// @notice Gets annual interest for a collateral type
  /// @dev Assumes 31536000 seconds in a year
  /// @param collateralTypeId The ID of the collateral type
  /// @return annualInterest The annual interest rate
  function getAnnualInterest(
    uint256 collateralTypeId
  ) external view returns (uint256 annualInterest) {
    return collateralTypes[collateralTypeId].interestRate.powu(31536000);
  }

  /// @notice Gets per-second interest for a collateral type
  /// @param collateralTypeId The ID of the collateral type
  /// @return psInterest The per-second interest rate
  function getPsInterest(
    uint256 collateralTypeId
  ) external view returns (uint256 psInterest) {
    return collateralTypes[collateralTypeId].interestRate;
  }

  /// @notice Obtains the collateralization ratio for a collateral type
  /// @param collateralTypeId The ID of the collateral type
  /// @return collateralRatio The collateralization ratio
  function getCollateralRatio(
    uint256 collateralTypeId
  ) external view returns (uint256 collateralRatio) {
    CollateralType storage cType = collateralTypes[collateralTypeId];
    return cType.collateralRatio;
  }

  /// @notice Obtains the debt floor for a collateral type
  /// @param collateralTypeId The ID of the collateral type
  /// @return debtFloor The debt floor
  function getDebtFloor(
    uint256 collateralTypeId
  ) external view returns (uint256 debtFloor) {
    return collateralTypes[collateralTypeId].debtFloor;
  }

  /// @notice Obtains the debt ceiling for a collateral type
  /// @param collateralTypeId The ID of the collateral type
  /// @return debtCeiling The debt ceiling
  function getDebtCeiling(
    uint256 collateralTypeId
  ) external view returns (uint256 debtCeiling) {
    return collateralTypes[collateralTypeId].debtCeiling;
  }

  /// @notice Gets the vaults owned by an address
  /// @param owner The owner's address
  /// @return ownedVaults_ The vaults owned by the address
  function getOwnedVaults(
    address owner
  ) external view returns (uint256[] memory ownedVaults_) {
    return ownedVaults[owner];
  }

  /// @notice Gets the owner of a vault
  /// @param vaultId The vault's ID
  /// @return owner The owner's address
  function getOwner(
    uint256 vaultId
  ) external view returns (address owner) {
    return vaults[vaultId].owner;
  }

  /// @notice Gets the alternate owner of a vault
  /// @param vaultId The vault's ID
  /// @return altOwner The alternate owner's address
  function getAltOwner(
    uint256 vaultId
  ) external view returns (address altOwner) {
    return vaults[vaultId].altOwner;
  }

  /// @notice Returns the collateral type ID for a vault
  /// @param vaultId The vault's ID
  /// @return collateralTypeId The collateral type ID
  function getCollateralTypeId(
    uint256 vaultId
  ) external view returns (uint256 collateralTypeId) {
    return vaults[vaultId].collateralTypeId;
  }

  /// @notice Returns the collateral token for a vault
  /// @param vaultId The vault's ID
  /// @return collateralToken The collateral token
  function getCollateralToken(
    uint256 vaultId
  ) external view returns (IERC20 collateralToken) {
    return getCollateralType(vaultId).token;
  }


  /// @notice Adds collateral to a vault
  /// @param vaultId The vault's ID
  /// @param amount The amount of collateral to add
  function addCollateral(
    uint256 vaultId,
    uint256 amount
  ) public onlyVaultOwner(vaultId) notLiquidated(vaultId) {
    getCollateralType(vaultId).token.safeTransferFrom(
      msg.sender,
      address(this),
      amount
    );
    vaults[vaultId].collateralAmount += amount;
    getCollateralType(vaultId).totalCollateral += amount;
    collateralManager.handleCollateralDeposit(vaultId, amount);

    emit AddCollateral(msg.sender, vaultId, amount);
  }

  /// @notice Sets the collateral manager
  /// @param _collateralManager The collateral manager
  function setCollateralManager(
    ICollateralManager _collateralManager
  ) public onlyAllowlist {
    collateralManager = _collateralManager;
  }

  /// @notice Determines a vault's debt
  /// @param vaultId The vault's ID
  /// @return debt The vault's debt
  function getDebt(uint256 vaultId) public view returns (uint256 debt) {
    return vaults[vaultId].initialDebt.mul(
      getCollateralType(vaultId).cumulativeInterest);
  }

  /// @notice Obtains the total debt for a collateral type
  /// @param collateralTypeId The ID of the collateral type
  /// @return totalDebt The total debt
  function getTotalDebt(
    uint256 collateralTypeId
  ) public view returns (uint256 totalDebt) {
    CollateralType storage cType = collateralTypes[collateralTypeId];
    return cType.initialDebt.mul(cType.cumulativeInterest);
  }

  /// @notice Updates interest for a collateral type
  /// @param collateralTypeId The ID of the collateral type
  function updateInterest(uint256 collateralTypeId) public {
    CollateralType storage cType = collateralTypes[collateralTypeId];
    uint256 timeDelta = block.timestamp - cType.lastUpdateTime;

    if (timeDelta == 0) {
      return;
    }
    uint256 oldTotalDebt = getTotalDebt(collateralTypeId);
    cType.cumulativeInterest = cType.cumulativeInterest.mul(
      cType.interestRate.powu(timeDelta));

    emit UpdateInterest(
      collateralTypeId,
      cType.interestRate,
      cType.lastUpdateTime,
      cType.cumulativeInterest
    );

    cType.lastUpdateTime = block.timestamp;

    balanceSheet.addSurplus((int256(getTotalDebt(collateralTypeId))
      - int256(oldTotalDebt)));
  }

  /// @notice Returns the collateral amount for a vault
  /// @param vaultId The vault's ID
  /// @return collateralAmount The collateral amount
  function getCollateralAmount(
    uint256 vaultId
  ) public view returns (uint256 collateralAmount) {
    return vaults[vaultId].collateralAmount;
  }

  /// @notice Returns the per-unit price of the vault's collateral
  /// @param vaultId The vault's ID
  /// @return price The collateral price
  function getCollateralPrice(
    uint256 vaultId
  ) public view returns (uint256 price) {
    price = getCollateralType(vaultId).priceSource.price();
  }

  /// @notice Returns the value of a vault's collateral
  /// @param vaultId The vault's ID
  /// @return collateralValue The collateral value
  function getCollateralValue(uint256 vaultId) public view returns (uint256) {
    return getCollateralAmount(vaultId).mul(getCollateralPrice(vaultId));
  }

  /// @notice Multiplies the debt by the collateral ratio for a vault
  /// @param vaultId The vault's ID
  /// @return targetCollateralValue The target collateral value
  function getTargetCollateralValue(
    uint256 vaultId
  ) public view returns (uint256 targetCollateralValue) {
    return getDebt(vaultId).mul(getCollateralType(vaultId).collateralRatio);
  }

  /// @notice Determines if a vault is undercollateralized
  /// @param vaultId The vault's ID
  /// @return undercollateralized True if the vault is undercollateralized
  function underCollateralized(uint256 vaultId) public view returns (bool) {
    return getCollateralValue(vaultId) < getTargetCollateralValue(vaultId);
  }

  /// @notice Sets the debt for a vault
  /// @param vaultId The vault's ID
  /// @param newDebt The new debt
  function setDebt(uint256 vaultId, uint256 newDebt) internal {
    CollateralType storage cType = getCollateralType(vaultId);
    uint256 oldInitialDebt = vaults[vaultId].initialDebt;
    uint256 newInitialDebt = newDebt.div(cType.cumulativeInterest);
    vaults[vaultId].initialDebt = newInitialDebt;

    cType.initialDebt = cType.initialDebt + newInitialDebt - oldInitialDebt;
    emit SetDebt(msg.sender, vaultId, newDebt, newInitialDebt);
  }

  /// @notice Returns the collateral type object for a specific vault
  /// @param vaultId The vault's ID
  /// @return cType The collateral type object
  function getCollateralType(
    uint256 vaultId
  ) internal view returns (CollateralType storage cType) {
    return collateralTypes[vaults[vaultId].collateralTypeId];
  }

  /// @notice Reverts if the debt amount is invalid.
  /// @param vaultId The vault's ID
  /// @param amount The debt amount
  function requireValidDebtAmount(
    uint256 vaultId,
    uint256 amount
  ) internal view {
    require(validDebtAmount(vaultId, amount), "Yama: Invalid debt amount");
  }

  /// @notice Determines if the debt amount is valid.
  /// @param vaultId The vault's ID
  /// @param amount The debt amount
  /// @return isValidDebtAmount True if the debt amount is valid
  function validDebtAmount(
    uint256 vaultId,
    uint256 amount
  ) internal view returns (bool isValidDebtAmount) {
    return (
      amount == 0 ||
      (amount >= getCollateralType(vaultId).debtFloor
       && !underCollateralizedWithNewDebt(vaultId, amount)));
  }

  /// @notice Determines if a vault is undercollateralized with a new debt amount
  /// @param vaultId The vault's ID
  /// @param amount The debt amount
  /// @return isUnderCollateralized True if the vault is undercollateralized
  function underCollateralizedWithNewDebt(
    uint256 vaultId,
    uint256 amount
  ) internal view returns (bool isUnderCollateralized) {
    return getCollateralValue(vaultId) < getTargetCollateralValueWithNewDebt(vaultId, amount);
  }

  /// @notice Multiplies the debt by the collateral ratio for a vault with a new debt amount
  /// @param vaultId The vault's ID
  /// @param amount The debt amount
  /// @return targetCollateralValue The target collateral value
  function getTargetCollateralValueWithNewDebt(
    uint256 vaultId,
    uint256 amount
  ) internal view returns (uint256 targetCollateralValue) {
    return amount.mul(getCollateralType(vaultId).collateralRatio);
  }
}