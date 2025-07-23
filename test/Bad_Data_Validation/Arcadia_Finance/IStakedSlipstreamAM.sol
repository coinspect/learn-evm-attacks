// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

//https://basescan.org/address/0x1dc7a0f5336f52724b650e39174cfcbbedd67bf1#code
interface IStakedSlipstreamAM {
    function burn(uint256 positionId) external returns (uint256 rewards);
}