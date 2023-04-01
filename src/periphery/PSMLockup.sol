// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "../modules/templates/YSSModule.sol";
import "../modules/PegStabilityModule.sol";
import "./SimpleBSH.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@prb/math/contracts/PRBMathUD60x18.sol";

/// @notice Incentivizes locking up an external stablecoin in the PSM
contract PSMLockup is YSSModule, ERC20 {
  using SafeERC20 for IERC20;
  using SafeERC20 for YSS;
  using PRBMathUD60x18 for uint256;

  SimpleBSH public bsh;
  PegStabilityModule public immutable psm;
  IERC20 public immutable psmToken;

  /// @notice Emitted when the external stablecoin is locked up
  /// @param account Account that locked up money
  /// @param extStableAmount Amount of external stablecoin locked up
  /// @param yamaAmount Amount of YSS locked up
  /// @param lockupAmount Amount of PSMLockup tokens minted
  event Lockup(
    address indexed account,
    uint256 extStableAmount,
    uint256 yamaAmount,
    uint256 lockupAmount
  );

  /// @notice Emitted when the external stablecoin is withdrawn
  /// @param account Account that withdrew money
  /// @param yamaAmount Amount of YSS withdrawn
  /// @param lockupAmount Amount of PSMLockup tokens burned
  event Withdraw(
    address indexed account,
    uint256 yamaAmount,
    uint256 lockupAmount
  );

  /// @notice Initializes the PSMLockup
  /// @param _stablecoin YSS token
  /// @param _psm PSM contract
  /// @param _psmToken Token used in the PSM
  /// @param name Name of the PSMLockup token
  /// @param symbol Symbol of the PSMLockup token
  constructor(
    YSS _stablecoin,
    PegStabilityModule _psm,
    IERC20 _psmToken,
    string memory name,
    string memory symbol
  ) YSSModule(_stablecoin) ERC20(name, symbol) {
    psm = _psm;
    psmToken = _psmToken;
  }

  /// @notice Sets the BSH contract
  /// @param _bsh BSH contract
  function setBSH(SimpleBSH _bsh) external onlyAllowlist {
    bsh = _bsh;
  }

  /// @notice Lock up the external stablecoin in the PSM
  /// @param extStableAmount Amount of external stablecoin to lock up
  /// @return lockupAmount Amount of PSMLockup tokens minted
  function lockup(uint256 extStableAmount) external returns (uint256 lockupAmount) {
    if (address(bsh) != address(0)) {
      bsh.processPendingShareAmount();
    }
    psmToken.safeTransferFrom(msg.sender, address(this), extStableAmount);
    psmToken.safeIncreaseAllowance(address(psm), extStableAmount);
    uint256 savedValue = value();
    uint256 yamaAmount = psm.deposit(extStableAmount);
    lockupAmount = yamaAmount.div(savedValue);
    _mint(msg.sender, lockupAmount);
    emit Lockup(
      msg.sender,
      extStableAmount,
      yamaAmount,
      lockupAmount
    );
  }

  /// @notice Withdraw the external stablecoin from the PSM
  /// @param lockupAmount Amount of PSMLockup tokens to burn
  /// @return yamaAmount Amount of YSS withdrawn
  function withdraw(uint256 lockupAmount) external returns (uint256 yamaAmount) {
    yamaAmount = lockupAmount.mul(value());
    _burn(msg.sender, lockupAmount);
    stablecoin.safeTransfer(msg.sender, yamaAmount);
    emit Withdraw(
      msg.sender,
      yamaAmount,
      lockupAmount
    );
  }

  /// @notice Returns the value of the lockup token (how much YAMA given upon
  /// redemption)
  /// @return value_ Value of the lockup token
  function value() public view returns (uint256 value_) {
    if (totalSupply() == 0) {
      return PRBMathUD60x18.SCALE;
    } else {
      return stablecoin.balanceOf(address(this)).div(totalSupply());
    }
  }
}