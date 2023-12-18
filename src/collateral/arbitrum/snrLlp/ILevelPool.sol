// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

interface ILevelPool {
    function addLiquidity(address _tranche, address _token, uint256 _amountIn, uint256 _minLpAmount, address _to)
        external;

    function removeLiquidity(address _tranche, address _tokenOut, uint256 _lpAmount, uint256 _minOut, address _to)
        external;
}