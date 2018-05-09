pragma solidity ^0.4.3;

interface StateChannel {
    function dispute_length() external returns (uint);
    function get_dispute(uint i) external returns (int256, uint256, uint256);
}

contract Custodian {
    enum Status { PENDING, OK, CHEATED, CLOSED }
    enum Flag { PENDING, OK, DISPUTE, CLOSED }
    Status public flag;

    uint public numCustomers;
    uint public profit;

    struct Customer {
        Flag flag;
        uint256 deposit;
        uint256 t_settle;
    }

    mapping (address => Customer) public customers;

    address public custodian;
    uint256 public d_withdraw;
    uint256 public d_settle;
    uint256 public custodian_deposit;

    event EventSetup(address indexed custodian, uint256 indexed deposit);
    event EventDeposit(address indexed customer, uint256 indexed deposit);
    event EventEvidence(address indexed customer);
    event EventDispute(address indexed customer);
    event EventResolve(address indexed customer);

    modifier onlycustodian { if (msg.sender == custodian) _; else revert(); }

    function verifySignature(address pub, bytes32 h, uint8 v, bytes32 r, bytes32 s) {
        address _signer = ecrecover(h,v,r,s);
        if (pub != _signer) revert();
    }

    function setup (uint32 _d_withdraw, uint32 _d_settle) 
        payable
        public
    {
        require(flag == Status.PENDING);
        custodian = msg.sender;
        custodian_deposit = msg.value;
        d_withdraw = _d_withdraw;
        d_settle = _d_settle;
        flag = Status.OK;
        emit EventSetup(custodian, custodian_deposit);
    }

    function deposit()
        payable
        public
    {
        require(flag == Status.OK || flag == Status.PENDING);
        require(customers[msg.sender].flag != Flag.DISPUTE);

        if (customers[msg.sender].flag == Flag.CLOSED || customers[msg.sender].flag == Flag.PENDING) {
            customers[msg.sender].flag = Flag.OK;
        }

        customers[msg.sender].deposit += msg.value;
        emit EventDeposit(msg.sender, msg.value);
    }

    event DebugState(uint256  indexed pre_image, bytes32 indexed image, bytes32 indexed input);
    function setstate(bytes32 _image, uint256 _coins, uint256 _pre_image, address _customer, uint256[] sigs)
        onlycustodian
        public
    {
        require(flag != Status.CHEATED);
        require(_coins <= customers[_customer].deposit);
        emit DebugState(_pre_image, keccak256(_pre_image), _image);
        require(keccak256(_pre_image) == _image);

        uint8 V = uint8(sigs[0]+27);
        bytes32 R = bytes32(sigs[1]);
        bytes32 S = bytes32(sigs[2]);
        bytes32 _h = keccak256('\x19Ethereum Signed Message:\n32', keccak256(_image, _coins, address(this)));

        verifySignature(_customer, _h, V, R, S);

        profit += _coins;
        _customer.transfer( customers[_customer].deposit - _coins);
        customers[_customer].flag = Flag.CLOSED;
        numCustomers -= 1;
        customers[_customer].deposit = 0;
        customers[_customer].t_settle = 0;

        emit EventEvidence(_customer);
    }

    function triggerdispute() public {
        if (customers[msg.sender].flag == Flag.OK) {
            customers[msg.sender].flag = Flag.DISPUTE;
            customers[msg.sender].t_settle = block.number + uint256(d_settle);
            emit EventDispute(msg.sender);
        }
    }

    function resolve() public {
        if (flag == Status.CHEATED ||
            (customers[msg.sender].t_settle < block.number && customers[msg.sender].flag == Flag.DISPUTE))
        {
            msg.sender.transfer(customers[msg.sender].deposit);
            customers[msg.sender].flag = Flag.CLOSED;
            numCustomers -= 1;
            customers[msg.sender].deposit = 0;
            customers[msg.sender].t_settle = 0;
            emit EventResolve(msg.sender);
        }

    }


    event EventCheated();
    event EventFair();
    function recourse(uint32 _t_start, uint32 _t_expire, address _channel, int256 _round, bytes32 _image, uint256 _pre_image, uint256[] sigs) 
        public
    {
        require(flag != Status.CHEATED);
        require(keccak256(_pre_image) == _image);
        
        bytes32 _h = keccak256('\x19Ethereum Signed Message:\n32', keccak256(_t_start,_t_expire,_channel,address(this),_round,_image));

        verifySignature(custodian, _h, uint8(sigs[0])+27, bytes32(sigs[1]), bytes32(sigs[2])); 

        StateChannel s = StateChannel(_channel);
        int256 dispute_round;
        uint256 dispute_t_start;
        uint256 dispute_t_settle;
        for (uint8 i = 0; i < s.dispute_length(); i++) {
            (dispute_round, dispute_t_start, dispute_t_settle) = s.get_dispute(i);
            if (dispute_t_start > _t_start &&
                _t_expire > dispute_t_settle &&
                _round > dispute_round)
            {
                flag = Status.CHEATED;
                emit EventCheated();
            } else {
                emit EventFair();
            }
        }
    }

}
