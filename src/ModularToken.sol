// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @notice Template for modular tokens with an allowlist to manage minting/burning
contract ModularToken is ERC20, ERC20Permit {
  /// @notice Allowed addresses can mint/burn the token.
  mapping(address => bool) public allowlist;
  
  /// @notice Emitted when an address is added/removed from the allowlist
  /// @param account Address that was added/removed
  /// @param isAllowed Whether the address is allowed
  event SetAllowlist(address indexed account, bool isAllowed);

  /// @notice Restricts execution of a function to allowed contracts
  modifier onlyAllowlist() {
    require(allowlist[msg.sender], "ModularToken: Sender not allowed");
    _;
  }

  /// @notice Constructor
  /// @param mintAmount Amount of tokens to mint
  /// @param name Name of the token
  /// @param symbol Symbol of the token
  constructor(
    uint256 mintAmount,
    string memory name,
    string memory symbol
  ) ERC20(name, symbol) ERC20Permit(name) {
    _mint(msg.sender, mintAmount);
    allowlist[msg.sender] = true;
    setAllowlist(msg.sender, true);
  }

  /// @notice Sets the allowlist status of an address
  /// @param account Address to set
  /// @param isAllowed Whether the address is allowed
  function setAllowlist(
    address account,
    bool isAllowed
  ) public onlyAllowlist {
    allowlist[account] = isAllowed;

    emit SetAllowlist(account, isAllowed);
  }

  /// @notice Used by allowed contracts to mint tokens
  /// @param account Address that receives tokens
  /// @param amount Amount of tokens to mint
  function mint(
    address account,
    uint256 amount
  ) external onlyAllowlist {
    _mint(account, amount);
  }

  /// @notice Used by allowed contracts to burn tokens
  /// @param account Address where tokens are burned
  /// @param amount Amount of tokens to burn
  function burn(
    address account,
    uint256 amount
  ) external onlyAllowlist {
    _burn(account, amount);
  }

  /// @notice Used by allowed contracts to modify token allowances
  /// @param owner Address that owns the tokens
  /// @param spender Address that is allowed to spend the tokens
  /// @param amount Amount of tokens that are allowed to be spent
  function approve(
    address owner,
    address spender,
    uint256 amount
  ) external onlyAllowlist {
    _approve(owner, spender, amount);
  }
}
