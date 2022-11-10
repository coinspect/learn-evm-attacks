// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBalancer {
    function flashLoan(address recipient, address[] memory tokens, uint256[] memory amounts, bytes memory userData) external payable;
}

// To use this flashloan module, just call inherit it and call balancer.flashloan(params)

contract BalancerFlashloan {
        IBalancer public constant balancer = IBalancer(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

}