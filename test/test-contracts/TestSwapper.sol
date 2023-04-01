// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "src/YSS.sol";
import "src/utility/ISwapper.sol";

contract TestSwapper is ISwapper {
    YSS public stablecoin;
    ModularToken public collateral;

    constructor(YSS _stablecoin, ModularToken _collateral) {
        stablecoin = _stablecoin;
        collateral = _collateral;
    }

    function swapToYama(
        uint256 collateralAmount,
        uint256 minOutputAmount
    ) external override returns (uint256 outputAmount) {
        require(collateralAmount >= minOutputAmount, "TestSwapper: insufficient output amount");
        collateral.burn(msg.sender, collateralAmount);
        stablecoin.mint(msg.sender, collateralAmount);
        return collateralAmount;
    }

    function swapToCollateral(
        uint256 yamaAmount,
        uint256 minOutputAmount
    ) external override returns (uint256 outputAmount) {
        require(yamaAmount >= minOutputAmount, "TestSwapper: insufficient output amount");
        stablecoin.burn(msg.sender, yamaAmount);
        collateral.mint(msg.sender, yamaAmount);
        return yamaAmount;
    }
}