// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

interface ISwapperV1 {
    function swapToken(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _minAmountOut,
        address _beneficiary
    ) external;

    function getAmountOutMin(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external view returns (uint256);

}
