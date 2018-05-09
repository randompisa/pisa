pragma solidity ^0.4.7;

interface Application {
    function update(bytes32 _state, bytes32 _aux_in, bytes32[] _inputs) external returns(bytes32);
    function transition(uint256 balanceA, uint256 balanceB, uint32[] cmds, uint256[] inputs) external returns(uint32,uint32);
    function handleOutputs(bytes32 _state) external;
}

contract StateChannel {
    address[] public players;
    mapping (address => uint256) playermap;

    // State, indexed by round
    int256 public bestRound = -1;

    enum Status { PENDING, OK, DISPUTE}

    Status public status;
    uint256 public t_start;
    uint256 public deadline;
    mapping ( uint256 => uint256[] ) public inputs;
    mapping ( uint256 => uint32[] ) public cmds;
    mapping ( uint256 => bool ) public applied;

    struct Dispute {
        int256 round;
        uint256 t_start;
        uint256 t_settle;
    }

    Dispute[] disputes;

    bytes32 public aux_in;
    uint32 public stateA;
    uint32 public stateB;
    bytes32 public hstate;

    event EventPending (uint32 indexed round, uint32 indexed deadline);
    event EventOnchain (uint32 indexed round);
    event EventOffchain(uint32 indexed round);
    event EventInput   (address indexed player, uint32 cmd, uint256 _input);
    event EventDispute (uint256 indexed deadline);
    event EventResolve (uint256 indexed balanceA, uint256 indexed balanceB, int256 indexed bestround);

    uint256 public T1;
    uint256 public T2;

    address public shit;
    Application public application;

    modifier after_ (uint256 T) { if (T > 0 && block.number >= T) _; else revert(); }
    modifier before (uint256 T) { if (T == 0 || block.number <  T) _; else revert(); }
    modifier onlyplayers { if (playermap[msg.sender] > 0) _; else revert(); }
    modifier beforeTrigger { if (T1 == 0) _; else revert(); }
    
    function dispute_length() public returns (uint) {
        return disputes.length;
    }

    function get_dispute(uint i) public returns (int256, uint256, uint256) {
        return (disputes[i].round, disputes[i].t_start, disputes[i].t_settle);
    }

    function latestClaim() constant after_(T1) public returns(int) {
        return(bestRound);
    }

    event DebugSigner(address indexed signer, address indexed sender);
    function verifySignature(address pub, bytes32 h, uint8 v, bytes32 r, bytes32 s) {
        address _signer = ecrecover(h,v,r,s);
        if (pub != _signer) revert();
    }

    function StateChannel(address[] _players, address _application) payable {
        for (uint i = 0; i < _players.length; i++) {
            players.push(_players[i]);
            playermap[_players[i]] = (i+1);
        }

        application = Application(_application);
        shit = _application;
    }

    event DebugInput(int256 indexed round, uint256 indexed n, uint256[] indexed data);
    function input(uint32 _cmd, uint256 _input) onlyplayers public {
        require( status == Status.DISPUTE );
        uint i = playermap[msg.sender];

        if (inputs[uint(bestRound+1)].length == 0) {
            inputs[uint(bestRound+1)].push(0);
            inputs[uint(bestRound+1)].push(0);
            cmds[uint(bestRound+1)].push(0);
            cmds[uint(bestRound+1)].push(0);
        }
        
        inputs[uint(bestRound+1)][i] = _input;
        cmds[uint(bestRound+1)][i] = _cmd;
        emit EventInput(msg.sender, _cmd, _input);
    }

    function triggerdispute(uint256[3] sig) onlyplayers public {
        require( status == Status.OK );
        uint8 V = uint8(sig[0])+27;
        bytes32 R = bytes32(sig[1]);
        bytes32 S = bytes32(sig[2]);
        bytes32 _h = keccak256("dispute", bestRound, address(this));
        _h = keccak256('\x19Ethereum Signed Message:\n32', _h);
        verifySignature(msg.sender, _h, V, R, S);
        status = Status.DISPUTE;
        t_start = block.number;
        deadline = block.number + 10;
        emit EventDispute(deadline);
    }
    
    function _triggerdispute(uint256[3] sig, address player) public {
        require( playermap[player] > 0);
        require( status == Status.OK );
        uint8 V = uint8(sig[0])+27;
        bytes32 R = bytes32(sig[1]);
        bytes32 S = bytes32(sig[2]);
        bytes32 _h = keccak256("dispute", bestRound, address(this));
        _h = keccak256('\x19Ethereum Signed Message:\n32', _h);
        verifySignature(player, _h, V, R, S);
        status = Status.DISPUTE;
        deadline = block.number + 10;
        emit EventDispute(deadline);
    }

    function setstate(uint256[] sigs, int256 r, uint256 _hstate) {
        require(r > bestRound && !applied[uint256(r)]);
        
        bytes32 _h = keccak256(r, _hstate);
        _h = keccak256('\x19Ethereum Signed Message:\n32', _h);
        for (uint i = 0; i < players.length; i++) {
            uint8 V = uint8(sigs[i*3+0])+27;
            bytes32 R = bytes32(sigs[i*3+1]);
            bytes32 S = bytes32(sigs[i*3+2]);
            verifySignature(players[i], _h, V, R, S);
        }

        bestRound = r;
        hstate = bytes32(_hstate);
        status = Status.OK;
    }


    function resolve(uint256 _balanceA, uint256 _balanceB, uint32 _round) onlyplayers public {
        require( block.number > deadline);
        require( keccak256(_balanceA, _balanceB) == hstate );
        require( _round == bestRound );

        if (status == Status.DISPUTE) {
            (stateA, stateB) = application.transition(_balanceA, _balanceB, cmds[_round+1], inputs[_round+1]);
            status = Status.OK;
            bestRound = _round + 1;
            disputes.push( Dispute(bestRound, t_start, deadline));
            emit EventResolve(_balanceA, _balanceB, bestRound);
        }
    }

}
