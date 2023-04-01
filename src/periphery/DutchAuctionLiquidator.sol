// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/modules/templates/YSSModuleExtended.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";
import "src/modules/CDPModule.sol";

/// @notice Liquidates CDPs with a dutch auction.
contract DutchAuctionLiquidator is YSSModuleExtended, ILiquidator {
  using PRBMathUD60x18 for uint256;

  /// @custom:type Collateral type parameters.
  struct CTypeParams {
    // Multiplies the collateral value to determine starting price.
    uint256 initialPriceRatio;

    // How many seconds between each price drop.
    uint256 timeInterval;

    // PRBMathUD60x18.SCALE - (PRBMathUD60x18.SCALE / 100), which represents
    // 0.99 is a 1% price drop every timeInterval seconds
    uint256 changeRate;

    // After resetThreshold * timeInterval seconds, no one can bid and the
    // auction must be reset.
    uint256 resetThreshold;

    // Used to check if this struct is used instead of the default CTypeParams.
    // If this is the default CTypeParams, this field is unused.
    bool enabled;
  }

  struct Auction {
    uint256 vaultId;
    uint256 startPrice;
    uint256 startTime;
    bool done; // Claimed or reset.
  }

  /// @notice Includes all auctions, even those that have been claimed or reset.
  Auction[] public auctions;

  CDPModule public immutable cdpModule;

  mapping(uint256 collateralTypeId => CTypeParams cTypeParams) public cTypeParamsMapping;

  CTypeParams public defaultCTypeParams;

  /// @notice Emitted when an auction is initialized
  /// @param vaultId The vault ID
  /// @param auctionId The auction ID
  /// @param startPrice The starting price
  /// @param startTime The starting time
  event InitializeAuction(
    uint256 indexed vaultId,
    uint256 indexed auctionId,
    uint256 startPrice,
    uint256 startTime
  );
  
  /// @notice Emitted when an auction is reset
  /// @param initiator The initiator of the reset
  /// @param vaultId The vault ID
  /// @param auctionId The auction ID
  event ResetAuction(
    address indexed initiator,
    uint256 indexed vaultId,
    uint256 indexed auctionId
  );

  /// @notice Emitted when an auction is claimed
  /// @param claimer The claimer of the auction
  /// @param vaultId The vault ID
  /// @param auctionId The auction ID
  /// @param price The price of the auction
  event ClaimAuction(
    address indexed claimer,
    uint256 indexed vaultId,
    uint256 indexed auctionId,
    uint256 price
  );

  /// @notice Emitted when the default collateral type parameters are set
  /// @param initialPriceRatio The initial price ratio
  /// @param timeInterval The time interval
  /// @param changeRate The change rate
  /// @param resetThreshold The reset threshold
  event SetDefaultCTypeParams(
    uint256 initialPriceRatio,
    uint256 timeInterval,
    uint256 changeRate,
    uint256 resetThreshold
  );
  
  /// @notice Emitted when the collateral type parameters are set
  /// @param collateralTypeId The collateral type ID
  /// @param initialPriceRatio The initial price ratio
  /// @param timeInterval The time interval
  /// @param changeRate The change rate
  /// @param resetThreshold The reset threshold
  /// @param enabled Whether the collateral type is enabled
  event SetCTypeParams(
    uint256 indexed collateralTypeId,
    uint256 initialPriceRatio,
    uint256 timeInterval,
    uint256 changeRate,
    uint256 resetThreshold,
    bool enabled
  );

  /// @notice Verifies that the auction has not been claimed or reset
  modifier notDone(uint256 auctionId) {
    require(!auctions[auctionId].done, "Yama: Auction done");
    _;
  }

  /// @notice Initializes this contract
  /// @param _stablecoin The YSS contract
  /// @param _balanceSheet The BalanceSheet contract
  /// @param _cdpModule The CDPModule contract
  /// @param defaultInitialPriceRatio The default initial price ratio
  /// @param defaultTimeInterval The default time interval
  /// @param defaultChangeRate The default change rate
  /// @param defaultResetThreshold The default reset threshold
  constructor(
    YSS _stablecoin,
    BalanceSheetModule _balanceSheet,
    CDPModule _cdpModule,
    uint256 defaultInitialPriceRatio,
    uint256 defaultTimeInterval,
    uint256 defaultChangeRate,
    uint256 defaultResetThreshold
  ) YSSModuleExtended(_stablecoin, _balanceSheet) {
    cdpModule = _cdpModule;
    defaultCTypeParams = CTypeParams(
      defaultInitialPriceRatio,
      defaultTimeInterval,
      defaultChangeRate,
      defaultResetThreshold,
      true
    );
    emit SetDefaultCTypeParams(
      defaultInitialPriceRatio,
      defaultTimeInterval,
      defaultChangeRate,
      defaultResetThreshold
    );
  }

  /// @notice Sets the liquidation parameters for a collateral type
  /// @param collateralTypeId The collateral type ID
  /// @param initialPriceRatio The initial price ratio
  /// @param timeInterval The time interval
  /// @param changeRate The change rate
  /// @param resetThreshold The reset threshold
  /// @param enabled Whether the collateral type is enabled
  function setCTypeParams(
    uint256 collateralTypeId,
    uint256 initialPriceRatio,
    uint256 timeInterval,
    uint256 changeRate,
    uint256 resetThreshold,
    bool enabled
  ) external onlyAllowlist {
    cTypeParamsMapping[collateralTypeId] = CTypeParams(
      initialPriceRatio,
      timeInterval,
      changeRate,
      resetThreshold,
      enabled
    );
    emit SetCTypeParams(
      collateralTypeId,
      initialPriceRatio,
      timeInterval,
      changeRate,
      resetThreshold,
      enabled
    );
  }

  /// @notice Called by the CDP module to liquidate a vault
  /// @param vaultId The vault ID
  /// @return successful Whether the liquidation was successful
  function liquidate(
    uint256 vaultId
  ) external onlyAllowlist returns (bool successful) {
    initializeAuction(vaultId);

    return true;
  }

  /// @notice Used to purchase the auctioned collateral at the current price
  /// @param maxPrice The transaction reverts if the price is above this amount
  function claim(
    uint256 auctionId,
    uint256 maxPrice
  ) external notDone(auctionId) {
    Auction storage auction = auctions[auctionId];
    require(!isExpired(auctionId), "Yama: Auction expired");

    uint256 price = getPrice(auctionId);
    require(price <= maxPrice, "Yama: price > maxPrice");

    stablecoin.burn(msg.sender, price);
    cdpModule.transfer(
      cdpModule.getCollateralToken(auction.vaultId),
      msg.sender,
      cdpModule.getCollateralAmount(auction.vaultId)
    );
    cdpModule.updateInterest(cdpModule.getCollateralTypeId(auction.vaultId));
    balanceSheet.addSurplus(
      int256(price) - int256(cdpModule.getDebt(auction.vaultId)));
    cdpModule.clearVault(auction.vaultId);
    auction.done = true;

    emit ClaimAuction(
      msg.sender,
      auction.vaultId,
      auctionId,
      price
    );
  }

  /// @notice Resets an auction once it has expired
  /// @param auctionId The auction ID
  function resetAuction(
    uint256 auctionId
  ) external notDone(auctionId) {
    require(isExpired(auctionId), "Yama: Auction not expired");

    auctions[auctionId].done = true;

    emit ResetAuction(
      msg.sender,
      auctions[auctionId].vaultId,
      auctionId
    );

    initializeAuction(auctions[auctionId].vaultId);
  }

  /// @notice Obtains the amount of collateral in an auction
  /// @param auctionId The auction ID
  /// @return collateralAmount The amount of collateral
  function getCollateralAmount(
    uint256 auctionId
  ) external view returns (uint256 collateralAmount) {
    return cdpModule.getCollateralAmount(auctions[auctionId].vaultId);
  }

  /// @notice Gets the last auction ID.
  /// @return lastAuctionId The last auction ID
  function getLastAuctionId() external view returns (uint256 lastAuctionId) {
    return auctions.length - 1;
  }

  /// @notice Sets the default liquidation parameters.
  /// @param initialPriceRatio The initial price ratio
  /// @param timeInterval The time interval
  /// @param changeRate The change rate
  /// @param resetThreshold The reset threshold
  function setDefaultCTypeParams(
    uint256 initialPriceRatio,
    uint256 timeInterval,
    uint256 changeRate,
    uint256 resetThreshold
  ) public onlyAllowlist {
    defaultCTypeParams = CTypeParams(
      initialPriceRatio,
      timeInterval,
      changeRate,
      resetThreshold,
      true
    );
    emit SetDefaultCTypeParams(
      initialPriceRatio,
      timeInterval,
      changeRate,
      resetThreshold
    );
  }

  /// @notice Obtains the collateral type ID for an auction
  /// @param auctionId The auction ID
  /// @return collateralTypeId The collateral type ID
  function getCollateralTypeId(
    uint256 auctionId
  ) public view returns (uint256 collateralTypeId) {
    return cdpModule.getCollateralTypeId(auctions[auctionId].vaultId);
  }

  /// @notice Calculates the current price for an auction.
  /// @dev Returns 0 if the auction is not in progress.
  /// @param auctionId The auction ID
  /// @return price The current price
  function getPrice(uint256 auctionId) public view returns (uint256 price) {
    Auction storage auction = auctions[auctionId];

    if (auction.done || isExpired(auctionId)) {
      return 0;
    }

    CTypeParams storage cTypeParams = getAuctionCTypeParams(auctionId);
    
    uint256 intervalsElapsed
      = (block.timestamp - auction.startTime) / cTypeParams.timeInterval;
    
    return auction.startPrice.mul(
      cTypeParams.changeRate.powu(intervalsElapsed));
  }

  function isExpired(uint256 auctionId) public view returns (bool) {
    CTypeParams storage cTypeParams = getAuctionCTypeParams(auctionId);

    return block.timestamp >= (auctions[auctionId].startTime
      + (cTypeParams.timeInterval * cTypeParams.resetThreshold));
  }

  /// @notice Initializes an auction
  /// @param vaultId The vault ID
  function initializeAuction(
    uint256 vaultId
  ) internal {
    CTypeParams storage cTypeParams
      = getCTypeParams(cdpModule.getCollateralTypeId(vaultId));

    Auction memory auction = Auction(
      vaultId,
      cdpModule.getCollateralValue(vaultId).mul(cTypeParams.initialPriceRatio),
      block.timestamp,
      false
    );

    auctions.push(auction);

    emit InitializeAuction(
      vaultId,
      auctions.length - 1,
      auction.startPrice,
      auction.startTime
    );
  }

  /// @notice Obtains CTypeParams for a collateral type (or default CTypeParams)
  /// @param collateralTypeId The collateral type ID
  /// @return cTypeParams The CTypeParams
  function getCTypeParams(
    uint256 collateralTypeId
  ) internal view returns (CTypeParams storage cTypeParams) {
    CTypeParams storage specificCTypeParams
      = cTypeParamsMapping[collateralTypeId];

    if (specificCTypeParams.enabled) {
      return specificCTypeParams;
    } else {
      return defaultCTypeParams;
    }
  }

  /// @notice Obtains CTypeParams for an auction.
  /// @param auctionId The auction ID
  /// @return cTypeParams The CTypeParams
  function getAuctionCTypeParams(
    uint256 auctionId
  ) internal view returns (CTypeParams storage cTypeParams) {
    return getCTypeParams(getCollateralTypeId(auctionId));
  }
}