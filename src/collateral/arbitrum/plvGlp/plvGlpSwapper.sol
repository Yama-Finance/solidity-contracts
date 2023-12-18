// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/utility/ISwapper.sol";
import "src/YSS.sol";
import "src/modules/PegStabilityModule.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../yPlvGlp/YPlvGlpModule.sol";

/// @notice A utility contract provided by GMX to mint/redeem GLP
interface IRewardRouter {
    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);
}

/// @notice A Curve pool
interface ICurvePool {
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy,
        address receiver
    ) external returns (uint256);
}

/// @notice Swaps plvGLP to Yama and vice versa
contract PlvGlpSwapper is ISwapper, YPlvGlpModule {
    IERC20 public constant oldSGlp = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);
    IERC20 public constant sGLP = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);
    IRewardRouter public constant rewardRouter = IRewardRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    address public constant glpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    PegStabilityModule public psm;
    IERC20 public constant usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 public constant usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC4626 public constant plvGlp = IERC4626(0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1);
    ICurvePool public constant curvePool = ICurvePool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    constructor(
        YSS _stablecoin,
        PegStabilityModule _psm,
        PlvGlpCustodian _plvGlpCustodian
    ) YPlvGlpModule(_stablecoin, _plvGlpCustodian) {
        stablecoin = _stablecoin;
        psm = _psm;
        plvGlpCustodian = _plvGlpCustodian;
    }

    /// @notice Swaps plvGLP to Yama
    /// @param collateralAmount The amount of plvGLP to swap
    /// @param minOutputAmount Minimum Yama received
    /// @return outputAmount The amount of Yama received
    function swapToYama(
        uint256 collateralAmount,
        uint256 minOutputAmount
    ) external checkEoaOrAuthorized returns (uint256 outputAmount) {
        plvGlp.transferFrom(msg.sender, address(this), collateralAmount);
        plvGlp.approve(address(plvGlpCustodian), collateralAmount);
        plvGlpCustodian.redeem(collateralAmount);
        uint256 glpAmount = sGLP.balanceOf(address(this));
        uint256 usdcAmount = rewardRouter.unstakeAndRedeemGlp(
            address(usdc), glpAmount, 0, address(this));
        usdc.approve(address(curvePool), usdcAmount);
        uint256 usdtAmount = curvePool.exchange(0, 1, usdcAmount, 0, address(this));
        usdt.approve(address(psm), usdtAmount);
        outputAmount = psm.deposit(usdtAmount);
        checkOutputAmount(minOutputAmount, outputAmount);
        stablecoin.transfer(msg.sender, outputAmount);
    }

    /// @notice Swaps Yama to plvGLP
    /// @param stablecoinAmount The amount of Yama to swap
    /// @param minOutputAmount Minimum plvGLP received
    /// @return outputAmount The amount of plvGLP received
    function swapToCollateral(
        uint256 stablecoinAmount,
        uint256 minOutputAmount
    ) external checkEoaOrAuthorized returns (uint256 outputAmount) {
        stablecoin.transferFrom(msg.sender, address(this), stablecoinAmount);
        uint256 usdtAmount = psm.withdraw(stablecoinAmount);
        usdt.approve(glpManager, usdtAmount);
        try rewardRouter.mintAndStakeGlp(address(usdt), usdtAmount, 0, 0) returns (uint256 glpAmount) {
            return processGlp(glpAmount, minOutputAmount);
        } catch {
            usdt.approve(address(curvePool), usdtAmount);
            uint256 usdcAmount = curvePool.exchange(1, 0, usdtAmount, 0, address(this));
            usdc.approve(glpManager, usdcAmount);
            uint256 glpAmount = rewardRouter.mintAndStakeGlp(
                address(usdc), usdcAmount, 0, 0);
            return processGlp(glpAmount, minOutputAmount);
        }
    }

    function processGlp(
        uint256 glpAmount,
        uint256 minOutputAmount
    ) internal returns (uint256 outputAmount) {
        oldSGlp.approve(address(plvGlpCustodian), glpAmount);
        plvGlpCustodian.deposit(glpAmount);
        outputAmount = plvGlp.balanceOf(address(this));
        checkOutputAmount(minOutputAmount, outputAmount);
        plvGlp.transfer(msg.sender, outputAmount);
    }

    /// @notice Checks if output amount is sufficient
    /// @param minOutputAmount Minimum output amount
    /// @param outputAmount Output amount
    function checkOutputAmount(
        uint256 minOutputAmount,
        uint256 outputAmount
    ) internal pure {
        require(outputAmount >= minOutputAmount, "plvGlpSwapper: insufficient output amount");
    }
}