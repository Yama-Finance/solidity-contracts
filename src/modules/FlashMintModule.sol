// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./templates/YSSModule.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";


/// @notice Issues flash loans denominated in Yama.
contract FlashMintModule is YSSModule, IERC3156FlashLender {

  /// @notice Maximum flash loan amount
  uint256 public max;

  bytes32 constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

  /// @notice Verifies the token is Yama
  /// @param token Token to verify
  modifier onlyYama(address token) {
    require(token == address(stablecoin), "Yama: Not YSS");
    _;
  }

  /// @notice Initializes the module
  /// @param _stablecoin Stablecoin
  /// @param _max Maximum flash loan amount
  constructor(YSS _stablecoin, uint256 _max) YSSModule(_stablecoin) {
    max = _max;
  }

  /// @notice Returns the maximum flash loan amount
  /// @param token Token
  /// @return Maximum flash loan amount
  function maxFlashLoan(
    address token
  ) onlyYama(token) external view override returns (uint256) {
    return max;
  }

  /// @notice Returns the fee for a given flash loan amount. Fee is always 0
  /// @param token Token
  /// @param amount Amount
  /// @return Fee
  function flashFee(
    address token,
    uint256 amount
  ) onlyYama(token) external view override returns (uint256) {
    amount;
    return 0;
  }

  /// @notice Executes an ERC3165 flash loan
  /// @param receiver Receiver of the flash loan
  /// @param token Token
  /// @param amount Amount
  /// @param data Data
  /// @return success Success
  /// @notice This function can re-enter, but it doesn't pose a risk because the tokens
  /// are burned regardless
  function flashLoan(
    IERC3156FlashBorrower receiver,
    address token,
    uint256 amount,
    bytes calldata data
  ) onlyYama(token) external override returns (bool success) {
    require(amount <= max, "Yama: Flash loan exceeds max");
    stablecoin.mint(address(receiver), amount);
    require(
      receiver.onFlashLoan(msg.sender, token, amount, 0, data) == CALLBACK_SUCCESS,
      "Yama: Callback failed"
    );
    uint256 allowance = stablecoin.allowance(address(receiver), address(this));
    require(
      allowance >= amount,
      "Yama: Insufficient allowance"
    );
    stablecoin.burn(address(receiver), amount);
  
    // Not the ERC20 approve function, so SafeERC20 not required.
    stablecoin.approve(
      address(receiver),
      address(this),
      allowance - amount
    );
    return true;
  }

  /// @notice Sets the maximum flash loan amount
  /// @param _max Maximum flash loan amount
  function setMax(uint256 _max) external onlyAllowlist {
    max = _max;
  }
}