// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "../modules/FlashMintModule.sol";
import "../periphery/DutchAuctionLiquidator.sol";
import "./ISwapper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice A simple contract used by keepers to liquidate CDPs using flash loans
contract SimpleKeeperProxy is IERC3156FlashBorrower {
    YSS public immutable stablecoin;
    FlashMintModule public immutable flashMintModule;
    CDPModule public immutable cdpModule;
    DutchAuctionLiquidator public immutable liquidatorModule;
    IERC20 public immutable collateral;
    ISwapper public immutable swapper;

    /// @notice Initializes the contract
    /// @param _stablecoin Stablecoin
    /// @param _flashMintModule Flash mint module
    /// @param _cdpModule CDP module
    /// @param _liquidatorModule Liquidator module
    /// @param _collateral Collateral token
    /// @param _swapper Swapper
    constructor(
        YSS _stablecoin,
        FlashMintModule _flashMintModule,
        CDPModule _cdpModule,
        DutchAuctionLiquidator _liquidatorModule,
        IERC20 _collateral,
        ISwapper _swapper
    ) {
        stablecoin = _stablecoin;
        flashMintModule = _flashMintModule;
        cdpModule = _cdpModule;
        liquidatorModule = _liquidatorModule;
        collateral = _collateral;
        swapper = _swapper;
    }

    /// @notice Liquidates a vault and claims the auction using a flash loan and pockets the profit
    /// @param vaultId Vault ID
    /// @param maxPrice Maximum price to pay to claim the collateral
    function liquidateAndClaim(uint256 vaultId, uint256 maxPrice) external {
        cdpModule.liquidate(vaultId);
        uint256 auctionId = liquidatorModule.getLastAuctionId();
        uint256 auctionPrice = liquidatorModule.getPrice(auctionId);
        flashMintModule.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(stablecoin),
            auctionPrice,
            encodeFlashLoanData(auctionId, maxPrice, msg.sender)
        );
    }

    /// @notice Resets and claims an auction using a flash loan and pockets the profit
    /// @param auctionId Auction ID
    /// @param maxPrice Maximum price to pay to claim the collateral
    function resetAndClaim(uint256 auctionId, uint256 maxPrice) external {
        liquidatorModule.resetAuction(auctionId);
        uint256 newAuctionId = liquidatorModule.getLastAuctionId();
        uint256 auctionPrice = liquidatorModule.getPrice(newAuctionId);
        flashMintModule.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(stablecoin),
            auctionPrice,
            encodeFlashLoanData(newAuctionId, maxPrice, msg.sender)
        );
    }
    
    /// @notice Claims an auction using a flash loan and pockets the profit
    /// @param auctionId Auction ID
    /// @param maxPrice Maximum price to pay to claim the collateral
    function claimAuction(uint256 auctionId, uint256 maxPrice) external {
        uint256 auctionPrice = liquidatorModule.getPrice(auctionId);
        flashMintModule.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(stablecoin),
            auctionPrice,
            encodeFlashLoanData(auctionId, maxPrice, msg.sender)
        );
    }

    /// @notice Callback function for flash loans
    /// @param initiator Initiator of the flash loan
    /// @param token Token address
    /// @param amount Amount of tokens borrowed
    /// @param fee Fee
    /// @param data Data
    /// @return hash keccak256("ERC3156FlashBorrower.onFlashLoan")
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32 hash) {
        fee; token;
        require(msg.sender == address(flashMintModule), "SimpleLiquidator: Not flashMintModule");
        require(initiator == address(this), "SimpleLiquidator: Initiator not this");
        (uint256 auctionId, uint256 maxPrice, address executor) = decodeFlashLoanData(data);

        uint256 collateralAmount = liquidatorModule.getCollateralAmount(auctionId);
        liquidatorModule.claim(auctionId, maxPrice);
        collateral.approve(address(swapper), collateralAmount);
        uint256 profit = swapper.swapToYama(collateralAmount, amount) - amount;

        stablecoin.approve(address(flashMintModule), amount);
        stablecoin.transfer(executor, profit);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @notice Encodes flash loan data
    /// @param auctionId Auction ID
    /// @param maxPrice Maximum price to pay to claim the collateral
    /// @param executor Executor
    /// @return data Encoded data
    function encodeFlashLoanData(
        uint256 auctionId,
        uint256 maxPrice,
        address executor
    ) internal pure returns (bytes memory data) {
        return abi.encode(
            auctionId,
            maxPrice,
            executor
        );
    }

    /// @notice Decodes flash loan data
    /// @param data Encoded data
    /// @return auctionId Auction ID
    /// @return maxPrice Maximum price to pay to claim the collateral
    /// @return executor Executor
    function decodeFlashLoanData(
        bytes memory data
    ) internal pure returns (
        uint256 auctionId,
        uint256 maxPrice,
        address executor
    ) {
        return abi.decode(data, (uint256, uint256, address));
    }
}