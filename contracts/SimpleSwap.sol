// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";


contract SimpleSwap is ISimpleSwap, ERC20 {
    // Implement core logic here
    address public tokenA;
    address public tokenB;

    uint256 private reserveA;
    uint256 private reserveB;

    

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));




    constructor(address _tokenA, address _tokenB) ERC20("SimpSwap", "STK") {
        require(isContract(_tokenA), "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(isContract(_tokenB), "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(_tokenA != _tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        tokenA = _tokenA;
        tokenB = _tokenB;
        // console.log("AAA", tokenA);
        // console.log("BBB", tokenB);
    }





    /// @notice Swap tokenIn for tokenOut with amountIn
    /// @param tokenIn The address of the token to swap from
    /// @param tokenOut The address of the token to swap to
    /// @param amountIn The amount of tokenIn to swap
    /// @return amountOut The amount of tokenOut received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");//需要 > 0
        require(tokenIn == tokenA || tokenIn == tokenB, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == tokenA || tokenOut == tokenB, "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");//進跟出不能是同一種幣

        address sender = _msgSender();
        uint256 _totalSupply = totalSupply();
        uint256 k  = reserveA * reserveB;

        ERC20(tokenIn).transferFrom(sender, address(this), amountIn);//user to swap
        console.log("amountIn", amountIn);
        if(tokenIn == tokenA) {
            uint256 newA = amountIn + reserveA;
            amountOut = ((newA * reserveB) - k) / newA;//計算給出的B amount
            console.log("amountOutA", amountOut);
            // _update(reserveA + amountIn, reserveB - amountOut);
        } else if(tokenIn == tokenB) {
            uint256 newB = amountIn + reserveB;
            amountOut = ((newB * reserveA) - k) / newB;//計算給出的A amount
            console.log("amountOutB", amountOut);
            //_update(reserveA - amountOut, reserveB + amountIn);
        }
        require(amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");// forces error, when amountOut is zero
        //console.log("amountOutD", amountOut);
        ERC20(tokenOut).approve(address(this), amountOut);
        ERC20(tokenOut).transferFrom(address(this), sender, amountOut);
        //should update here
        emit Swap(sender, tokenIn, tokenOut, amountIn, amountOut);
    }





    /// @notice Add liquidity to the pool
    /// @param amountAIn The amount of tokenA to add
    /// @param amountBIn The amount of tokenB to add
    /// @return amountA The actually amount of tokenA added
    /// @return amountB The actually amount of tokenB added
    /// @return liquidity The amount of liquidity minted
    function addLiquidity(uint256 amountAIn, uint256 amountBIn)//mint?
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        ){
            require(amountAIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
            require(amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
            //(uint256 _reserveA, uint256 _reserveB) = getReserves();
            address sender = _msgSender();
            uint _totalSupply = totalSupply();
           
            if(_totalSupply == 0) { //first time 
                liquidity = Math.sqrt(amountAIn * amountBIn);
                amountA = amountAIn;
                amountB = amountBIn;
            } else {//.min選小的
                liquidity = Math.min(amountAIn * _totalSupply / reserveA, amountBIn * _totalSupply / reserveB);
                amountA = (liquidity * reserveA) / _totalSupply;
                amountB = (liquidity * reserveB) / _totalSupply;
            }

        
            ERC20(tokenA).transferFrom(sender, address(this), amountAIn);
            ERC20(tokenB).transferFrom(sender, address(this), amountBIn);
               

            _mint(sender, liquidity);//發出LP

            _update(reserveA + amountAIn, reserveB + amountBIn);   
            emit AddLiquidity(sender, amountAIn, amountAIn, liquidity);
        }

    /// @notice Remove liquidity from the pool
    /// @param liquidity The amount of liquidity to remove
    /// @return amountA The amount of tokenA received
    /// @return amountB The amount of tokenB received
    //burn
    function removeLiquidity(uint256 liquidity) external returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        //require(balanceA > amountA || balanceB < amountB, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        uint balanceA = ERC20(tokenA).balanceOf(address(this));
        uint balanceB = ERC20(tokenB).balanceOf(address(this));
        address sender = _msgSender();
        uint _totalSupply = totalSupply();
        
        //計算退回的amountA amountB
        amountA = liquidity * balanceA / _totalSupply;
        amountB = liquidity * balanceB / _totalSupply;

        require(amountA > 0 && amountB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        
        
        ERC20(tokenA).transfer(sender, amountA);
        ERC20(tokenB).transfer(sender, amountB);

        _burn(address(this), liquidity);

        _update(reserveA - amountA, reserveB - amountB);
        emit RemoveLiquidity(sender, amountA, amountB, liquidity);


    }


    /// @notice Get the address of tokenA
    /// @return tokenA The address of tokenA
    function getTokenA() external view returns (address) {
        return tokenA;
    }

    /// @notice Get the address of tokenB
    /// @return tokenB The address of tokenB
    function getTokenB() external view returns (address) {
        return tokenB;
    }


    //update reserves and, on the first call per block, price accumulators
    function _update(uint256 _reserveA, uint256 _reserveB) private {
        reserveA = _reserveA;
        reserveB = _reserveB;
    }

    // @notice Get the reserves of the pool
    // @return reserveA The reserve of tokenA
    // @return reserveB The reserve of tokenB
    function getReserves() external view returns (uint256 _reserveA, uint256 _reserveB) {
        _reserveA = reserveA;
        _reserveB = reserveB;
    }



    // This method relies on extcodesize/address.code.length, which returns 0
    // for contracts in construction, since the code is only stored at the end
    // of the constructor execution.
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }    

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SimpleSwap: TRANSFER_FAILED");
    }    
}
