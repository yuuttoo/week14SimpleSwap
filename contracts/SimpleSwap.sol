// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "hardhat/console.sol";


contract SimpleSwap is ISimpleSwap, ERC20 {
    // Implement core logic here
    address public tokenA;
    address public tokenB;
    uint256 public reserveA;
    uint256 public reserveB;


    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "SimpleSwap: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor(address _tokenA, address _tokenB) ERC20("SimpSwap", "STK") {
        require(isContract(_tokenA), "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(isContract(_tokenB), "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(_tokenA != _tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        tokenA = _tokenA;
        tokenB = _tokenB;
        // console.log("AAA", tokenA);
        // console.log("BBB", tokenB);
    }


    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external lock returns (uint256 amountOut) {
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");//需要 > 0
        require(tokenIn == tokenA || tokenIn == tokenB, "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenOut == tokenA || tokenOut == tokenB, "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");//進跟出不能是同一種幣

        address sender = _msgSender();
        uint256 totalSupply = totalSupply();
        uint256 k  = reserveA * reserveB;

        IERC20(tokenIn).transferFrom(sender, address(this), amountIn);//user to swap
        //console.log("amountIn", amountIn);
        if(tokenIn == tokenA) {
            uint256 newA = amountIn + reserveA;
            amountOut = ((newA * reserveB) - k) / newA;//計算給出should be able to swap from tokenA to tokenB的B amount
        //console.log("amountOutA", amountOut);
            //B - newB
            // _update(reserveA + amountIn, reserveB - amountOut);
        } else if(tokenIn == tokenB) {
            uint256 newB = amountIn + reserveB;
            amountOut = ((newB * reserveA) - k) / newB;//計算給出的A amount
            //console.log("amountOutB", amountOut);
            //_update(reserveA - amountOut, reserveB + amountIn);
        }
        require(amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");// forces error, when amountOut is zero
        //console.log("amountOutD", amountOut);
        //console.log("reserve0",reserveA, reserveB);

        IERC20(tokenOut).approve(address(this), amountOut);
        IERC20(tokenOut).transferFrom(address(this), sender, amountOut);

        //console.log("reserve1",reserveA, reserveB);

        //做完swap需要update pool才會把值更新上鏈
        if(tokenIn == tokenA) {
            _update(reserveA + amountIn, reserveB - amountOut);
        } else if(tokenIn == tokenB) {
            _update(reserveA - amountOut, reserveB + amountIn);
        }
        //console.log("reserve2",reserveA, reserveB);

        
        //should update here
        emit Swap(sender, tokenIn, tokenOut, amountIn, amountOut);
    }


    function addLiquidity(uint256 amountAIn, uint256 amountBIn)//mint
        external
        lock
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        ){
            require(amountAIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
            require(amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
            address sender = _msgSender();
            uint totalSupply = totalSupply();
           
            if(totalSupply == 0) { //first time 
                liquidity = Math.sqrt(amountAIn * amountBIn);//流動性為池內A,B相乘後開根號，即為常數k(以kLast代稱)開根號
                amountA = amountAIn; //因為原本為0 加入多少就會是多少
                amountB = amountBIn; //因為原本為0 加入多少就會是多少
            } else {//.min選小的
                //流動性選後面二者中較小的:  (池內新加入的tokenA數量*lastK) / 池內tokenA餘額,  (池內新加入的tokenB數量*lastK) / 池內tokenB餘額
                liquidity = Math.min((amountAIn * totalSupply) / reserveA, (amountBIn * totalSupply) / reserveB);
                //因為給出的lp需要與加入的tokenA,B相匹配，需要以lp重新計算加入池內的tokenA, B amount
                amountA = (liquidity * reserveA) / totalSupply;//加入池內的tokenA數量為上面計算的(流動性 * 池內A餘額) / lastK
                amountB = (liquidity * reserveB) / totalSupply;//加入池內的tokenB數量為上面計算的(流動性 * 池內B餘額) / lastK
            }

            // ERC20(tokenA).transferFrom(sender, address(this), amountAIn);
            // ERC20(tokenB).transferFrom(sender, address(this), amountBIn);
            IERC20(tokenA).transferFrom(sender, address(this), amountA); //user轉tokenA到池子
            IERC20(tokenB).transferFrom(sender, address(this), amountB);//user轉tokenB到池子
               

            _mint(sender, liquidity);//發出LP

            _update(reserveA + amountA, reserveB + amountB);   
            emit AddLiquidity(sender, amountA, amountB, liquidity);

        }


    //burn user轉入LP到合約進行燒毀，計算等值amountA amountB退還user
    function removeLiquidity(uint256 liquidity) external lock returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        address sender = _msgSender();
        uint totalSupply = totalSupply();
        
        //user send lp to swap 
        _transfer(sender, address(this), liquidity);

        //計算退回給user的amountA amountB
        amountA = liquidity * reserveA / totalSupply; //退回user的A數量為 (傳回池子的lp份額 * 池內tokenA餘額) / lastK
        amountB = liquidity * reserveB / totalSupply; //退回user的B數量為 (傳回池子的lp份額 * 池內tokenB餘額) / lastK

        //合約退給user
        IERC20(tokenA).transfer(sender, amountA); 
        IERC20(tokenB).transfer(sender, amountB);
        
        //燒毀合約拿到的lp 
        _burn(address(this), liquidity);
        //更新pool餘額
        _update(reserveA - amountA, reserveB - amountB);
        emit RemoveLiquidity(sender, amountA, amountB, liquidity);
    }


    function getTokenA() external view returns (address) {
        return tokenA;
    }

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
    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }


    // This method relies on extcodesize/address.code.length, which returns 0
    // for contracts in construction, since the code is only stored at the end
    // of the constructor execution.
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }    

}
