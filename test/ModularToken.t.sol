
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "src/ModularToken.sol";

contract ModularTokenTest is Test {
  // Define any needed constants
  address constant owner = 0x5AEDA56215b167893e80B4fE645BA6d5Bab767DE;
  address constant spender = 0xE7775a6e9cb0B677D2cfca1CA43f04D905c1EdAC;

  // Initialize our module
  ModularToken modularToken;
  function setUp() public {
    vm.prank(owner);
    modularToken = new ModularToken(0, "TT", "TestToken");
  }

  // Run test to make sure the allowlist is populated with the owner
  function testAllowlist() public {
    assertEq(modularToken.allowlist(owner), true, "Owner should be on allowlist");
  }

  // Run test to make sure the owner is allowed to approve tokens
  function testApprove() public {
    vm.prank(owner);
    modularToken.approve(owner, spender, 10000);

    assertEq(modularToken.allowance(owner, spender), 10000, "Owner should be able to approve tokens");
  }

  // Run test to make sure a non-allowed address cannot modify token allowances
  function testApproveFail() public {
    vm.prank(spender);
    vm.expectRevert(bytes("ModularToken: Sender not allowed"));
    modularToken.approve(owner, spender, 10000);
  }

  // Make sure the owner can mint the token
  function testMint() public {
    vm.prank(owner);
    modularToken.mint(spender, 10000);

    assertEq(modularToken.balanceOf(spender), 10000, "Owner should be able to mint tokens");
  }

  // Make sure a non-allowed address cannot mint the token
  function testMintFail() public {
    vm.prank(spender);
    vm.expectRevert(bytes("ModularToken: Sender not allowed"));
    modularToken.mint(spender, 10000);
  }

  // Make sure the owner can burn the token
  function testBurn() public {
    vm.prank(owner);
    modularToken.mint(spender, 10000);
    vm.prank(owner);
    modularToken.burn(spender, 5000);

    assertEq(modularToken.balanceOf(spender), 5000,
      "Owner should be able to burn tokens");
  }

  // Make sure a non-allowed address cannot burn the token
  function testBurnFail() public {
    vm.prank(spender);
    vm.expectRevert(bytes("ModularToken: Sender not allowed"));
    modularToken.burn(spender, 5000);
  }

  // Make sure owner can add addresses to the allowlist
  function testSetAllowlist() public {
    vm.prank(owner);
    modularToken.setAllowlist(spender, true);
    assertEq(modularToken.allowlist(spender), true,
      "Owner should be able to add to the allowlist");
  }

  // Make sure a non-owner cannot add addresses to the allowlist
  function testSetAllowlistFail() public {
    vm.prank(spender);
    vm.expectRevert(bytes("ModularToken: Sender not allowed"));
    modularToken.setAllowlist(spender, true);
  }
}