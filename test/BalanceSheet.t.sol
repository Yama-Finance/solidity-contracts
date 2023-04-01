// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/modules/BalanceSheetModule.sol";
import "src/periphery/SimpleBSH.sol";
import "test/test-contracts/TestBSH.sol";

contract BalanceSheetTest is Test {
    YSS stablecoin;
    BalanceSheetModule balanceSheet;

    function setUp() public {
        stablecoin = new YSS();
        balanceSheet = new BalanceSheetModule(stablecoin);
    }

    function testBalanceSheet() public {
        balanceSheet.addDeficit(1000);
        assertEq(balanceSheet.totalSurplus(), -1000);
        balanceSheet.addSurplus(1000);
        assertEq(balanceSheet.totalSurplus(), 0);
        balanceSheet.addSurplus(1000);
        assertEq(balanceSheet.totalSurplus(), 1000);
        balanceSheet.setSurplus(-5000);
        assertEq(balanceSheet.totalSurplus(), -5000);
    }

    function testSimpleBSH() public {
        SimpleBSH bsh = new SimpleBSH(
            stablecoin,
            balanceSheet,
            5000,
            address(this)
        );
        balanceSheet.setHandler(IBalanceSheetHandler(address(bsh)));

        // Testing external call reverts from within SimpleBSH
        // because Foundry's coverage tool cares about that.
        vm.expectRevert("ModularToken: Sender not allowed");
        balanceSheet.addSurplus(1);
        vm.roll(block.number + 1);
        vm.expectRevert("ModularToken: Sender not allowed");
        bsh.processPendingShareAmount();
        stablecoin.setAllowlist(address(bsh), true);
        balanceSheet.addSurplus(0);


        balanceSheet.addSurplus(1000);
        vm.roll(block.number + 1);
        bsh.processPendingShareAmount();
        bsh.processPendingShareAmount();
        assertEq(balanceSheet.totalSurplus(), 500);
        assertEq(stablecoin.balanceOf(address(this)), 500);
        balanceSheet.addDeficit(1000);
        assertEq(balanceSheet.totalSurplus(), -500);
        balanceSheet.addSurplus(1);
        vm.roll(block.number + 1);
        bsh.processPendingShareAmount();
        balanceSheet.addDeficit(1);
        balanceSheet.addSurplus(2);
        vm.roll(block.number + 1);
        bsh.processPendingShareAmount();
        balanceSheet.addSurplus(-1);
        vm.roll(block.number + 1);
        bsh.processPendingShareAmount();
        balanceSheet.addSurplus(1000);
        vm.roll(block.number + 1);
        bsh.processPendingShareAmount();
        assertEq(balanceSheet.totalSurplus(), 0);
        balanceSheet.setSurplus(-5000);
        assertEq(balanceSheet.totalSurplus(), -5000);
        assertEq(stablecoin.balanceOf(address(this)), 1001);

        bsh.setRevenueShare(10_000);
        balanceSheet.addSurplus(5000);
        vm.roll(block.number + 1);
        bsh.processPendingShareAmount();
        assertEq(balanceSheet.totalSurplus(), -5000);
        balanceSheet.addSurplus(-2500);
        vm.roll(block.number + 1);
        bsh.processPendingShareAmount();
        assertEq(balanceSheet.totalSurplus(), -7500);

        vm.expectRevert(bytes("SimpleBSH: Only balance sheet"));
        bsh.onAddSurplus(0);

        bsh.setBalanceSheet(BalanceSheetModule(address(0)));
        vm.expectRevert(bytes("SimpleBSH: Only balance sheet"));
        balanceSheet.addSurplus(0);
        bsh.setBalanceSheet(balanceSheet);

        vm.expectRevert(bytes("SimpleBSH: Exceeds denominator"));
        bsh.setRevenueShare(10_001);

        uint256 oldBalance = stablecoin.balanceOf(address(this));

        balanceSheet.setSurplus(0);
        balanceSheet.addSurplus(100);
        bsh.processPendingShareAmount();
        assertEq(balanceSheet.totalSurplus(), 0);
        assertEq(stablecoin.balanceOf(address(this)), oldBalance);
        vm.roll(block.number + 1);
        bsh.processPendingShareAmount();
        assertEq(stablecoin.balanceOf(address(this)), oldBalance + 100);
    }

    function testTestBSH() public {
        TestBSH bsh = new TestBSH();

        balanceSheet.setHandler(IBalanceSheetHandler(address(bsh)));
        vm.expectRevert(bytes("Zero amount"));
        balanceSheet.addDeficit(0);
    }
}