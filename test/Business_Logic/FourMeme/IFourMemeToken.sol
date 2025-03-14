import {IERC20} from '../../interfaces/IERC20.sol';
pragma solidity ^0.8.17;

interface IFourMemeToken is IERC20 {

    function setMode(uint v) external;
}