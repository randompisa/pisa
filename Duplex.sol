pragma solidity ^0.4.3;

contract Duplex {

    address[2] public players;
    mapping (address => uint) playermap;

    // State, indexed by round
    int public bestRound = -1;
    int public net;
    uint[2] public balances;

    // Can only be incremented by deposit() function
    uint[2] public deposits;

    // Can only be incremented by withdraw() function
    uint[2] public withdrawn;

    event LogInit();
    event LogTriggered(uint T1, uint T2);
    event LogNewClaim(int r);
    event LogPlayerOutcome(uint player, string outcome, uint payment);
    event LogOutcome(int round, string outcome);
    event LogPayment(uint player, uint payment);

    address owner = msg.sender;

    enum Command { PAYALICE, PAYBOB, WITHDRAWALICE, WITHDRAWBOB, END }
    modifier onlyplayers { if (playermap[msg.sender] > 0) _; else throw; }
    modifier onlyowner { if (msg.sender == owner) _; else throw; }

    function get_balance() constant returns(uint) {
        return address(this).balance;
    }
    
    function assert(bool b) internal {
        if (!b) throw;
    }

    function verifySignature(address pub, bytes32 h, uint8 v, bytes32 r, bytes32 s) {
        if (pub != ecrecover(h,v,r,s)) throw;
    }

    function Duplex(address[2] _players, uint256 _balance) payable {
        // Assume this channel is funded by the sender
        for (uint i = 0; i < 2; i++) {
            players[i] = _players[i];
            playermap[_players[i]] = (i+1);
            balances[i] = _balance;
        }
        emit LogInit();
    }


    function deposit() onlyplayers payable {
	    deposits[playermap[msg.sender]-1] += msg.value;
    }

    function transition(uint256 _balanceA, uint256 _balanceB, uint32[] _cmds, uint256[] _inputs) onlyowner
        returns(uint256, uint256) 
    {
        uint32 _alice_cmd = _cmds[0];
        uint32 _bob_cmd = _cmds[1];
        uint256 _newA = _balanceA;
        uint256 _newB = _balanceB;
        if (Command(_alice_cmd) == Command.PAYBOB) {
            if (_newA >= _inputs[0]) {
                _newA -= _inputs[0];
                _newB += _inputs[0];
            }
        } else if (Command(_alice_cmd) == Command.WITHDRAWALICE) {
            if (_newA >= _inputs[0]) {
                _newA -= _inputs[0];
                players[0].transfer(_inputs[0]);
            }
        }

        if (Command(_bob_cmd) == Command.PAYALICE) {
            if (_newB >= _inputs[1]) {
                _newA += _inputs[1];
                _newB -= _inputs[1];
            }
        } else if (Command(_bob_cmd) == Command.WITHDRAWBOB) {
            if (_newB >= _inputs[1]) {
                _newB -= _inputs[1];
                players[1].transfer(_inputs[1]);
            }
        }

        return (_newA, _newB);
    }
}
