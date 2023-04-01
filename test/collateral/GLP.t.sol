// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/modules/PegStabilityModule.sol";
import "src/collateral/glp/MooGLPPrice.sol";
import "src/collateral/glp/MooGLPSwapper.sol";

interface IUsdt is IERC20 {
    function bridgeMint(address account, uint256 amount) external;
    function l2Gateway() external view returns (address);
}

contract GlpTest is Test {
    MooGLPSwapper swapper;
    MooGLPPrice priceSource;
    YSS stablecoin;
    PegStabilityModule psm;
    IUsdt usdt = IUsdt(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    function setUp() public {
        stablecoin = new YSS();
        psm = new PegStabilityModule(
            stablecoin,
            IERC20(address(usdt)),
            10_000_000_000 * 10 ** 18,
            18,
            6
        );
        stablecoin.setAllowlist(address(psm), true);

        swapper = new MooGLPSwapper(stablecoin, psm);
        priceSource = new MooGLPPrice();
    }

    function mintUSDT(uint256 amount) public {
        vm.prank(usdt.l2Gateway());
        usdt.bridgeMint(address(this), amount);
    }

    function testSwap() public {
        uint256 amount = 1_000_000 * 10 ** 18;
        mintUSDT(amount);
        usdt.approve(address(psm), amount);
        psm.deposit(amount);
        stablecoin.approve(address(swapper), amount);
        uint256 collatAmount = swapper.swapToCollateral(amount, 0);
        emit log_uint(collatAmount);
        IERC20(swapper.beefyVault()).approve(address(swapper), collatAmount);
        uint256 convertedBack = swapper.swapToYama(collatAmount, 0);
        emit log_uint(convertedBack);
    }

    function testPrice() public {
        emit log_uint(priceSource.price());
    }
}