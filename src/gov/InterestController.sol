// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "src/modules/templates/YSSModule.sol";
import "src/modules/CDPModule.sol";

/// @notice A contract used to set interest rate without going through the timelock
contract InterestController is YSSModule {
  CDPModule public cdp;
  uint256 public minInterestRate;
  uint256 public maxInterestRate;
  address public maintainer;

  event SetMaintainer(address maintainer);
  event SetInterestRateBounds(uint256 minInterestRate, uint256 maxInterestRate);
  event SetInterestRate(uint256 collateralTypeId, uint256 interestRate);

  /// @notice Sets the token, CDP module, and maintainer
  /// @param _stablecoin Stablecoin to set
  /// @param _cdp CDP module to set
  /// @param _maintainer Maintainer to set
  /// @param _minInterestRate Minimum interest rate to set
  /// @param _maxInterestRate Maximum interest rate to set
  constructor(
    YSS _stablecoin,
    CDPModule _cdp,
    address _maintainer,
    uint256 _minInterestRate,
    uint256 _maxInterestRate
  ) YSSModule(_stablecoin) {
    cdp = _cdp;
    setMaintainer(_maintainer);
    setInterestRateBounds(_minInterestRate, _maxInterestRate);
  }

  /// @notice Sets the interest rate
  /// @param collateralTypeId Collateral type ID to set
  /// @param interestRate Interest rate to set
  function setInterestRate(
    uint256 collateralTypeId,
    uint256 interestRate
  ) external {
    require(msg.sender == maintainer, "InterestController: not maintainer");
    require(interestRate >= minInterestRate && interestRate <= maxInterestRate,
      "InterestController: interest rate out of bounds");
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
    ) = cdp.collateralTypes(collateralTypeId);
    cdp.setCollateralType(
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

  /// @notice Sets the maintainer
  /// @param _maintainer Maintainer to set
  function setMaintainer(address _maintainer) public onlyAllowlist {
    maintainer = _maintainer;
    emit SetMaintainer(_maintainer);
  }

  /// @notice Sets the interest rate bounds
  /// @param _minInterestRate Minimum interest rate to set
  /// @param _maxInterestRate Maximum interest rate to set
  function setInterestRateBounds(
    uint256 _minInterestRate,
    uint256 _maxInterestRate
  ) public onlyAllowlist {
    minInterestRate = _minInterestRate;
    maxInterestRate = _maxInterestRate;
    emit SetInterestRateBounds(_minInterestRate, _maxInterestRate);
  }
}