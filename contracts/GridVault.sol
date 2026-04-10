// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library TransferHelper {
    function safeApprove(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0x095ea7b3, to, value)); // approve(address,uint256)
        require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }

    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0xa9059cbb, to, value)); // transfer(address,uint256)
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0x23b872dd, from, to, value)); // transferFrom(address,address,uint256)
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "ETH_TRANSFER_FAILED");
    }
}

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IV3SwapRouter02Like {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

contract GridVault {
    using TransferHelper for address;

    address public owner;
    address public pendingOwner;
    address public immutable swapRouter;
    bool public paused;

    mapping(address => bool) public allowedToken;
    mapping(uint24 => bool) public allowedFeeTier;

    event OwnershipTransferStarted(address indexed oldOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    event Paused(address indexed by);
    event Unpaused(address indexed by);

    event AllowedTokenSet(address indexed token, bool allowed);
    event AllowedFeeTierSet(uint24 indexed feeTier, bool allowed);

    event TokenDeposited(address indexed token, uint256 amount);
    event NativeDeposited(address indexed from, uint256 amount);

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint24 indexed fee,
        uint256 amountIn,
        uint256 amountOut,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    );

    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);
    event NativeWithdrawn(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "PAUSED");
        _;
    }

    constructor(address _swapRouter, address[] memory initialTokens, uint24[] memory initialFeeTiers) {
        require(_swapRouter != address(0), "ZERO_ROUTER");

        owner = msg.sender;
        swapRouter = _swapRouter;

        emit OwnershipTransferred(address(0), msg.sender);

        for (uint256 i = 0; i < initialTokens.length; i++) {
            require(initialTokens[i] != address(0), "ZERO_TOKEN");
            allowedToken[initialTokens[i]] = true;
            emit AllowedTokenSet(initialTokens[i], true);
        }

        for (uint256 i = 0; i < initialFeeTiers.length; i++) {
            allowedFeeTier[initialFeeTiers[i]] = true;
            emit AllowedFeeTierSet(initialFeeTiers[i], true);
        }
    }

    receive() external payable {
        emit NativeDeposited(msg.sender, msg.value);
    }

    function startOwnershipTransfer(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO_OWNER");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "NOT_PENDING_OWNER");
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, owner);
    }

    function setPaused(bool value) external onlyOwner {
        paused = value;
        if (value) {
            emit Paused(msg.sender);
        } else {
            emit Unpaused(msg.sender);
        }
    }

    function setAllowedToken(address token, bool allowed) external onlyOwner {
        require(token != address(0), "ZERO_TOKEN");
        allowedToken[token] = allowed;
        emit AllowedTokenSet(token, allowed);
    }

    function setAllowedFeeTier(uint24 feeTier, bool allowed) external onlyOwner {
        allowedFeeTier[feeTier] = allowed;
        emit AllowedFeeTierSet(feeTier, allowed);
    }

    function depositToken(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "ZERO_TOKEN");
        require(amount > 0, "ZERO_AMOUNT");
        require(allowedToken[token], "TOKEN_NOT_ALLOWED");

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit TokenDeposited(token, amount);
    }

    function depositNative() external payable onlyOwner {
        require(msg.value > 0, "ZERO_VALUE");
        emit NativeDeposited(msg.sender, msg.value);
    }

    function tokenBalance(address token) external view returns (uint256) {
        return IERC20Minimal(token).balanceOf(address(this));
    }

    function nativeBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        require(token != address(0), "ZERO_TOKEN");
        require(to != address(0), "ZERO_TO");
        require(amount > 0, "ZERO_AMOUNT");

        token.safeTransfer(to, amount);
        emit TokenWithdrawn(token, to, amount);
    }

    function withdrawNative(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "ZERO_TO");
        require(amount > 0, "ZERO_AMOUNT");

        TransferHelper.safeTransferETH(to, amount);
        emit NativeWithdrawn(to, amount);
    }

    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96
    ) external onlyOwner whenNotPaused returns (uint256 amountOut) {
        require(tokenIn != address(0) && tokenOut != address(0), "ZERO_TOKEN");
        require(tokenIn != tokenOut, "IDENTICAL_TOKENS");
        require(allowedToken[tokenIn] && allowedToken[tokenOut], "TOKEN_NOT_ALLOWED");
        require(allowedFeeTier[fee], "FEE_NOT_ALLOWED");
        require(amountIn > 0, "ZERO_AMOUNT");

        uint256 bal = IERC20Minimal(tokenIn).balanceOf(address(this));
        require(bal >= amountIn, "INSUFFICIENT_BALANCE");

        tokenIn.safeApprove(swapRouter, 0);
        tokenIn.safeApprove(swapRouter, amountIn);

        IV3SwapRouter02Like.ExactInputSingleParams memory params =
            IV3SwapRouter02Like.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            });

        amountOut = IV3SwapRouter02Like(swapRouter).exactInputSingle(params);

        tokenIn.safeApprove(swapRouter, 0);

        emit SwapExecuted(
            tokenIn,
            tokenOut,
            fee,
            amountIn,
            amountOut,
            amountOutMinimum,
            sqrtPriceLimitX96
        );
    }
}
