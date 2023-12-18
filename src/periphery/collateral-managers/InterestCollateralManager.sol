// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/modules/CDPModule.sol";
import "src/modules/PegStabilityModule.sol";
import "src/periphery/PSMLockup.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";
import "@prb/math/contracts/PRBMathSD59x18.sol";

/// @notice A collateral manager that sets the interest rates dynamically.
contract InterestCollateralManager is ICollateralManager, YSSModule {
    using PRBMathUD60x18 for uint256;
    using PRBMathSD59x18 for int256;

    CDPModule public immutable cdpModule;
    PegStabilityModule public immutable psm;
    PSMLockup public immutable lockup;

    IERC20 public externalStablecoin;

    uint8 public immutable yssDecimals;
    uint8 public immutable externalDecimals;

    uint256 public maxInterestRate;
    uint256 public minInterestRate;

    /// @notice The y axis is the interest rate and the x axis is the utilization ratio
    struct CTypeInterestParams {
        uint256 slope1;
        uint256 slope2;
        uint256 slope3;
        int256 yIntercept1;
        int256 yIntercept2;
        int256 yIntercept3;
        uint256 utilA;
        uint256 utilB;
    }

    // From a utilization of 0 to utilA, the interest rate varies linearly
    // from interestRateA to interestRateB. From utilA to utilB, the interest
    // rate varies linearly from interestRateB to interestRateC. From utilB to
    // 1, the interest rate varies linearly from interestRateC to interestRateD.
    struct SetCTypeInterestParamsArgs {
        uint256 cTypeId;
        uint256 utilA;
        uint256 utilB;
        uint256 interestRateA;
        uint256 interestRateB;
        uint256 interestRateC;
        uint256 interestRateD;
    }

    uint256[] public cTypeIds;
    mapping(uint256 cTypeId => CTypeInterestParams params) public cTypeInterestParams;

    /// @notice Emitted when the collateral type interest params are set
    event SetCTypeInterestParams(
        uint256 cTypeId,
        uint256 slope1,
        uint256 slope2,
        uint256 slope3,
        int256 yIntercept1,
        int256 yIntercept2,
        int256 yIntercept3,
        uint256 utilA,
        uint256 utilB
    );

    /// @notice Emitted when the collateral type IDs are set
    event SetCTypeIds(uint256[] cTypeIds);

    /// @notice Emitted when the interest rates are set
    event SetInterestRates();

    /// @notice Emitted when the interest rate is set for a collateral type
    event SetInterestRate(uint256 cTypeId, uint256 interestRate);

    /// @notice Emitted when the max or min interest rate is set
    event SetMaxMinInterestRates(uint256 maxInterestRate, uint256 minInterestRate);

    constructor(
        YSS stablecoin,
        CDPModule _cdpModule,
        PegStabilityModule _psm,
        PSMLockup _lockup
    ) YSSModule(stablecoin) {
        cdpModule = _cdpModule;
        psm = _psm;
        lockup = _lockup;
        externalStablecoin = psm.externalStablecoin();
        yssDecimals = psm.yssDecimals();
        externalDecimals = psm.externalDecimals();
    }

    /// @notice Called when collateral is deposited into a CDP and updates the interest rates
    /// @dev No need for access control as anyone can call setInterestRates()
    function handleCollateralDeposit(
        uint256 vaultId,
        uint256 amount
    ) external {
        vaultId;
        amount;
        try this.setInterestRates() {} catch {}
    }

    /// @notice Called when collateral is withdrawn from a CDP and updates the interest rates.
    /// @dev No need for access control as anyone can call setInterestRates()
    function handleCollateralWithdrawal(
        uint256 vaultId,
        uint256 amount
    ) external {
        vaultId;
        amount;
        try this.setInterestRates() {} catch {}
    }

    /// @notice Sets the collateral type IDs
    function setCTypeIds(uint256[] memory _cTypeIds) external onlyAllowlist {
        cTypeIds = _cTypeIds;
        emit SetCTypeIds(_cTypeIds);
    }

    /// @notice Sets the interest rate parameters for a CDP type
    function setCTypeInterestParams(
        SetCTypeInterestParamsArgs memory args
    ) external onlyAllowlist {
        require(0 < args.utilA, "InterestCollateralManager: utilA == 0");
        require(args.utilA < args.utilB, "InterestCollateralManager: utilA >= utilB");
        require(args.utilB < PRBMathUD60x18.scale(), "InterestCollateralManager: utilB >= 1");
        require(PRBMathUD60x18.scale() <= args.interestRateA, "InterestCollateralManager: interestRateA < 1");
        require(args.interestRateA <= args.interestRateB, "InterestCollateralManager: interestRateA > interestRateB");
        require(args.interestRateB <= args.interestRateC, "InterestCollateralManager: interestRateB > interestRateC");
        require(args.interestRateC <= args.interestRateD, "InterestCollateralManager: interestRateC > interestRateD");
        args.interestRateA = normalizeInterestRate(args.interestRateA);
        args.interestRateB = normalizeInterestRate(args.interestRateB);
        args.interestRateC = normalizeInterestRate(args.interestRateC);
        args.interestRateD = normalizeInterestRate(args.interestRateD);
        uint256 slope1 = (args.interestRateB - args.interestRateA).div(args.utilA);
        uint256 slope2 = (args.interestRateC - args.interestRateB).div(args.utilB - args.utilA);
        uint256 slope3 = (args.interestRateD - args.interestRateC).div(PRBMathUD60x18.scale() - args.utilB);
        int256 yIntercept1 = int256(args.interestRateA);
        int256 yIntercept2 = int256(args.interestRateB) - int256(slope2.mul(args.utilA));
        int256 yIntercept3 = int256(args.interestRateC) - int256(slope3.mul(args.utilB));
        cTypeInterestParams[args.cTypeId] = CTypeInterestParams({
            slope1: slope1,
            slope2: slope2,
            slope3: slope3,
            yIntercept1: yIntercept1,
            yIntercept2: yIntercept2,
            yIntercept3: yIntercept3,
            utilA: args.utilA,
            utilB: args.utilB
        });

        emit SetCTypeInterestParams(
            args.cTypeId,
            slope1,
            slope2,
            slope3,
            yIntercept1,
            yIntercept2,
            yIntercept3,
            args.utilA,
            args.utilB
        );
    }

    /// @notice Sets the min and max interest rates
    function setMinMaxInterestRates(
        uint256 _minInterestRate,
        uint256 _maxInterestRate
    ) external onlyAllowlist {
        require(_maxInterestRate >= _minInterestRate, "InterestCollateralManager: maxInterestRate < minInterestRate");
        maxInterestRate = _maxInterestRate;
        minInterestRate = _minInterestRate;
        emit SetMaxMinInterestRates(_maxInterestRate, _minInterestRate);
    }

    /// @notice Sets the interest rate based on the utilization ratio
    function setInterestRates() external {
        uint256 util = getUtilization();
        for (uint256 i = 0; i < cTypeIds.length; i++) {
            uint256 cTypeId = cTypeIds[i];
            cdpModule.updateInterest(cTypeId);
            CTypeInterestParams memory params = cTypeInterestParams[cTypeId];
            if (params.utilA == 0) continue; // If the params are not set, skip the collateral type
            uint256 interestRate = calculateInterest(params, util);
            setInterestRate(cTypeId, interestRate);
        }
        emit SetInterestRates();
    }

    /// @notice Calculates interest for a specific collateral type
    function calculateInterest(
        CTypeInterestParams memory params,
        uint256 util
    ) public pure returns (uint256 interestRate) {
        int256 result;
        if (util < params.utilA) {
            result = int256(params.slope1).mul(int256(util)) + params.yIntercept1;
        } else if (util < params.utilB) {
            result = int256(params.slope2).mul(int256(util)) + params.yIntercept2;
        } else {
            result = int256(params.slope3).mul(int256(util)) + params.yIntercept3;
        }

        if (result < 0) {
            interestRate = 0;
        } else {
            interestRate = uint256(result);
        }

        interestRate = denormalizeInterestRate(interestRate);
    }

    /// @notice Gets the utilization of the PSM (liquidity / total lent)
    function getUtilization() public view returns (uint256) {
        uint256 psmLiquidity = convertAmount(
            externalStablecoin.balanceOf(address(psm)),
            externalDecimals,
            yssDecimals
        );

        uint256 totalLent = lockup.totalSupply().mul(lockup.value());

        if (totalLent == 0) {
            return PRBMathUD60x18.scale();
        }

        if (psmLiquidity >= totalLent) {
            return 0;
        }

        return PRBMathUD60x18.scale() - psmLiquidity.div(totalLent);
    }

    /// @notice Normalizes an interest rate to be used in calculations
    function normalizeInterestRate(uint256 interestRate) public pure returns (uint256) {
        return (interestRate - PRBMathUD60x18.scale()) * 1e8;
    }

    /// @notice Denormalizes a calculated interest rate
    function denormalizeInterestRate(uint256 interestRate) public pure returns (uint256) {
        return (interestRate / 1e8) + PRBMathUD60x18.scale();
    }

    /// @notice Sets the interest rate for a specific collateral type
    function setInterestRate(uint256 collateralTypeId, uint256 interestRate) internal {
        if (interestRate > maxInterestRate) {
            interestRate = maxInterestRate;
        } else if (interestRate < minInterestRate) {
            interestRate = minInterestRate;
        }
        if (interestRate < PRBMathUD60x18.scale()) {
            return;
        }
        (
            ,
            IPriceSource priceSource,
            uint256 debtFloor,
            uint256 debtCeiling,
            uint256 collateralRatio,
            ,
            ,
            ,
            ,
            ,
            bool borrowingEnabled,
            bool allowlistEnabled
        ) = cdpModule.collateralTypes(collateralTypeId);
        cdpModule.setCollateralType(
            collateralTypeId,
            priceSource,
            debtFloor,
            debtCeiling,
            collateralRatio,
            interestRate,
            borrowingEnabled,
            allowlistEnabled
        );
        emit SetInterestRate(collateralTypeId, interestRate);
    }
}