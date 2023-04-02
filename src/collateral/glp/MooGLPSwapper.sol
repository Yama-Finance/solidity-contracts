// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/utility/ISwapper.sol";
import "src/YSS.sol";
import "src/modules/PegStabilityModule.sol";
import "./IBeefyVault.sol";

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

/// @notice Swaps mooGLP to Yama and vice versa
contract MooGLPSwapper is ISwapper {
    YSS public yama;
    IERC20 public constant sGLP = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);
    IRewardRouter public constant rewardRouter = IRewardRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    address public constant glpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    PegStabilityModule public psm;
    IERC20 public constant usdt = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 public constant usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IBeefyVault public constant beefyVault = IBeefyVault(0x9dbbBaecACEDf53d5Caa295b8293c1def2055Adc);
    ICurvePool public constant curvePool = ICurvePool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    constructor(
        YSS _yama,
        PegStabilityModule _psm
    ) {
        yama = _yama;
        psm = _psm;
    }

    /// @notice Swaps mooGLP to Yama
    /// @param collateralAmount The amount of mooGLP to swap
    /// @param minOutputAmount Minimum Yama received
    /// @return outputAmount The amount of Yama received
    function swapToYama(
        uint256 collateralAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount) {
        beefyVault.transferFrom(msg.sender, address(this), collateralAmount);
        beefyVault.withdraw(collateralAmount);
        uint256 glpAmount = sGLP.balanceOf(address(this));
        uint256 usdcAmount = rewardRouter.unstakeAndRedeemGlp(
            address(usdc), glpAmount, 0, address(this));
        usdc.approve(address(curvePool), usdcAmount);
        uint256 usdtAmount = curvePool.exchange(0, 1, usdcAmount, 0, address(this));
        usdt.approve(address(psm), usdtAmount);
        outputAmount = psm.deposit(usdtAmount);
        checkOutputAmount(minOutputAmount, outputAmount);
        yama.transfer(msg.sender, outputAmount);
    }

    /// @notice Swaps Yama to mooGLP
    /// @param yamaAmount The amount of Yama to swap
    /// @param minOutputAmount Minimum mooGLP received
    /// @return outputAmount The amount of mooGLP received
    function swapToCollateral(
        uint256 yamaAmount,
        uint256 minOutputAmount
    ) external returns (uint256 outputAmount) {
        yama.transferFrom(msg.sender, address(this), yamaAmount);
        uint256 usdtAmount = psm.withdraw(yamaAmount);
        usdt.approve(glpManager, usdtAmount);
        uint256 glpAmount = rewardRouter.mintAndStakeGlp(
            address(usdt), usdtAmount, 0, 0);
        sGLP.approve(address(beefyVault), glpAmount);
        beefyVault.deposit(glpAmount);
        outputAmount = beefyVault.balanceOf(address(this));
        checkOutputAmount(minOutputAmount, outputAmount);
        beefyVault.transfer(msg.sender, outputAmount);
    }

    /// @notice Checks if output amount is sufficient
    /// @param minOutputAmount Minimum output amount
    /// @param outputAmount Output amount
    function checkOutputAmount(
        uint256 minOutputAmount,
        uint256 outputAmount
    ) internal pure {
        require(outputAmount >= minOutputAmount, "MooGLPSwapper: insufficient output amount");
    }
}