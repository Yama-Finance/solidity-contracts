// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/modules/templates/YSSModule.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Converts YSS to/from an external stablecoin to stabilize the peg.
contract PegStabilityModule is YSSModule {
  using SafeERC20 for IERC20;

  IERC20 public immutable externalStablecoin;

  /// @notice Maximum amount of external stablecoin that can be held
  uint256 public debtCeiling;

  // Remembering the tokens' decimals is more gas-efficient and reliable than
  // calling decimals() on the tokens.
  uint8 public immutable yssDecimals;
  uint8 public immutable externalDecimals;

  /// @notice Emitted when the debt ceiling is set
  /// @param account Account that set the debt ceiling
  /// @param debtCeiling New debt ceiling
  event SetDebtCeiling(address indexed account, uint256 debtCeiling);

  /// @notice Emitted when the external stablecoin is deposited
  /// @param account Account that deposited the external stablecoin
  /// @param extStableAmount Amount of external stablecoin deposited
  event Deposit(address indexed account, uint256 extStableAmount);

  /// @notice Emitted when the external stablecoin is withdrawn
  /// @param account Account that withdrew the external stablecoin
  /// @param yssAmount Amount of YSS withdrawn
  event Withdraw(address indexed account, uint256 yssAmount);

  /// @notice Initializes the PSM
  /// @param _stablecoin YSS token
  /// @param _externalStablecoin External stablecoin
  /// @param _debtCeiling Maximum amount of external stablecoin that can be held
  /// @param _yssDecimals Number of decimals of YSS
  /// @param _externalDecimals Number of decimals of external stablecoin
  constructor(
    YSS _stablecoin,
    IERC20 _externalStablecoin,
    uint256 _debtCeiling,
    uint8 _yssDecimals,
    uint8 _externalDecimals
  ) YSSModule(_stablecoin) {
    externalStablecoin = _externalStablecoin;
    setDebtCeiling(_debtCeiling);
    yssDecimals = _yssDecimals;
    externalDecimals = _externalDecimals;
  }

  /// @notice Used by allowlist contracts to transfer tokens out
  /// @param token Token to transfer
  /// @param to Recipient of the tokens
  /// @param amount Amount of tokens to transfer
  function transfer(
    IERC20 token,
    address to,
    uint256 amount
  ) external onlyAllowlist {
    token.safeTransfer(to, amount);
  }

  /// @notice Deposits the external stablecoin in exchange for YSS.
  /// @param extStableAmount Amount of external stablecoin to deposit
  /// @return yssAmount Amount of YSS minted
  function deposit(uint256 extStableAmount) external returns (uint256 yssAmount) {
    externalStablecoin.safeTransferFrom(msg.sender, address(this), extStableAmount);
    yssAmount = convertAmount(
      extStableAmount,
      externalDecimals,
      yssDecimals
    );
    stablecoin.mint(msg.sender, yssAmount);
    require(externalStablecoin.balanceOf(address(this)) <= debtCeiling,
      "Yama: PSM exceeds debt ceiling");
    emit Deposit(msg.sender, extStableAmount);
  }

  /// @notice Withdraws the external stablecoin by burning YSS.
  /// @param yssAmount Amount of YSS to burn
  /// @return extStableAmount Amount of external stablecoin withdrawn
  function withdraw(uint256 yssAmount) external returns (uint256 extStableAmount) {
    stablecoin.burn(msg.sender, yssAmount);
    extStableAmount = convertAmount(
      yssAmount,
      yssDecimals,
      externalDecimals
    );
    require(externalStablecoin.balanceOf(address(this)) >= extStableAmount,
      "Yama: PSM reserves insufficient");
    externalStablecoin.safeTransfer(msg.sender, extStableAmount);
    emit Withdraw(msg.sender, yssAmount);
  }

  /// @notice Sets the debt ceiling
  /// @param _debtCeiling New debt ceiling
  function setDebtCeiling(uint256 _debtCeiling) public onlyAllowlist {
    debtCeiling = _debtCeiling;
    emit SetDebtCeiling(msg.sender, debtCeiling);
  }
}