// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "forge-std/Test.sol";
import {UintToString} from "../utils/Strings/StringsLib.sol";
interface IERC20Local {
    function name() external view returns(string memory);
    function decimals() external view returns(uint8);
    function balanceOf(address account) external view returns (uint256);
}
contract TokenBalanceTracker {
    using UintToString for uint256;

    mapping(address => mapping (address => uint256)) public balanceTracker; // tracks: user => (token => amount).
    address[] public trackedTokens;

    // Will look something like this. For simplicity, WETH could be the last token.
    // address[] tokens = [
    //     0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
    //     0x677ddbd918637E5F2c79e164D402454dE7dA8619, // VUSD
    //     0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
    //     0x86ed939B500E121C0C5f493F399084Db596dAd20, // SPC
    //     0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421, // VSP
    //     0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2  // WETH
    // ];

    struct BalanceDeltaReturn {
        string sign;
        uint256 value;
    }

    function addTokensToTracker(address[] memory _tokens) public {
        uint256 tokensLength = _tokens.length;
        for(uint256 i = 0; i < tokensLength; i++){
            addTokenToTracker(_tokens[i]);
        }
    }

    function addTokenToTracker(address _token) public {
        uint256 lenTrackedTokens = trackedTokens.length;
        bool alreadyTracked;
        for(uint256 i = 0; i < lenTrackedTokens; i++ ){
            if(_token == trackedTokens[i]){
                alreadyTracked = true;
            }
        }

        if(!alreadyTracked){
            trackedTokens.push(_token);
        }
    }

    function logBalancesWithLabel(string memory label, address _from) public {
        console.log(label);
        logBalances(_from);
    }

    function logBalances(address _from) public {
        (BalanceDeltaReturn memory nativeTokenDelta, BalanceDeltaReturn[] memory tokensDelta) = calculateBalanceDelta(_from);

        // NATIVE TOKENS HANDLING (12-9)
        if(nativeTokenDelta.value == 0) {
            console.log('Native Tokens: %s', _from.balance.toStringWithDecimals(18));
        } else {
            console.log('Native Tokens: %s (%s%s)', _from.balance.toStringWithDecimals(18), nativeTokenDelta.sign, nativeTokenDelta.value.toStringWithDecimals(18));
        }

        // Other tokens
        uint256 tokensLength = trackedTokens.length;
        if(tokensLength > 0){
            for(uint i = 0; i < tokensLength; i++){
                IERC20Local curToken = IERC20Local(trackedTokens[i]);
                if(tokensDelta[i].value == 0) {
                    console.log('%s: %s', curToken.name(), curToken.balanceOf(_from).toStringWithDecimals(curToken.decimals()));
                } else {
                    string memory deltaAndSign = string.concat(tokensDelta[i].sign, tokensDelta[i].value.toStringWithDecimals(curToken.decimals()));
                    console.log('%s: %s (%s)',  curToken.name(), curToken.balanceOf(_from).toStringWithDecimals(curToken.decimals()), deltaAndSign);
                }
            }
        }

        updateBalanceTracker(_from);
        console.log('\n');
    }

    function updateBalanceTracker(address _user) internal {
        balanceTracker[_user][address(0)] = _user.balance;

        uint256 tokensLength = trackedTokens.length;
        if(tokensLength == 0) return;

        for(uint i = 0; i < tokensLength; i++){
            IERC20Local curToken = IERC20Local(trackedTokens[i]);
            balanceTracker[_user][trackedTokens[i]] = curToken.balanceOf(_user);
        }
    }

    function getBalanceTrackers(address _user) public view returns(uint256 nativeBalance, uint256[] memory tokenBalances){
        nativeBalance = balanceTracker[_user][address(0)];

        uint256 tokensLength = trackedTokens.length;
        if(tokensLength > 0) {
            uint256[] memory memBalances = new uint256[](tokensLength);
            for(uint i = 0; i < tokensLength; i++){
                memBalances[i] = balanceTracker[_user][trackedTokens[i]];
            }
            tokenBalances = memBalances;
        }
    }

    function calculateBalanceDelta(address _user) internal view returns(BalanceDeltaReturn memory nativeDelta, BalanceDeltaReturn[] memory tokenDeltas){
        (uint256 prevNativeBalance, uint256[] memory prevTokenBalance) = getBalanceTrackers(_user);

        nativeDelta.value = _user.balance > prevNativeBalance ? (_user.balance - prevNativeBalance) : (prevNativeBalance - _user.balance);
        nativeDelta.sign = _user.balance > prevNativeBalance ? ('+') : ('-');

        uint256 tokensLength = trackedTokens.length;
        if(tokensLength > 0) {
            BalanceDeltaReturn[] memory memDeltas = new BalanceDeltaReturn[](tokensLength);
            for(uint i = 0; i < tokensLength; i++){
                uint256 currentTokenBalance = IERC20Local(trackedTokens[i]).balanceOf(_user);

                memDeltas[i].value = currentTokenBalance  > prevTokenBalance[i] ? (currentTokenBalance - prevTokenBalance[i]) : (prevTokenBalance[i] - currentTokenBalance);
                memDeltas[i].sign = currentTokenBalance  > prevTokenBalance[i] ? ('+') : ('-');
            }
            tokenDeltas = memDeltas;
        }
    }
}
