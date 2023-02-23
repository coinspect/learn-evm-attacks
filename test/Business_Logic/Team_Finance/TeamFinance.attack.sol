// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract SpoofERC20 {

    string constant name = '';
    uint256 constant decimals = 18;
    string constant symbol = '';

    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    uint256 public totalSupply;

    event Approval(address, address, uint256);
    event Transfer(address, address, uint256);

    function approve(address spender, uint256 amount) public {
        require(spender != address(0));

        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
    }

    function transfer(address to, uint256 amount) public {
        require(to != address(0));
        require(balanceOf[to] <= ~ amount);

        balanceOf[to] += amount;

        emit Transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public {
        require(to != address(0));
        require(balanceOf[to] <= ~ amount);

        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }
}