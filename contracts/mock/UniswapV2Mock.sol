// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV2PairMock {
    function swap(address tokenOut, uint256 amountOut) public {
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }
}

contract UniswapV2Router02Mock {
    uint256 private amount;
    address private pair;
    address public immutable WETH;

    constructor(address _WETH) {
        WETH = _WETH;
    }

    function setupMock(address _pair, uint256 _amountOut) public {
        pair = _pair;
        amount = _amountOut;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        IERC20(path[0]).transferFrom(msg.sender, address(pair), amountIn);
        UniswapV2PairMock(pair).swap(path[path.length - 1], amount);
        IERC20(path[path.length - 1]).transfer(to, amount);
    }
}
