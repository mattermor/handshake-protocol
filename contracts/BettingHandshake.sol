pragma solidity ^0.4.18;

contract BettingHandshake {
    struct Betor {
        uint value;
        uint winValue;
    }

    enum S { Inited, Shaked, Closed, Cancelled, InitiatorWon, BetorWon, Draw, Accepted, Rejected, Done }

    struct Bet {
        address initiator;
        uint escrow;  
        uint balance;
        uint goal;
        uint deadline;

        S state;
        uint8 result;
        mapping(address => Betor) betors;
        address[] addresses;
        address[] acceptors;
    }

    Bet[] public bets;
    address public referee;
    uint public reviewWindow = 3 days;
    uint public rejectWindow = 1 days;

    constructor() public {
        referee = msg.sender;
    } 

    modifier onlyInitiator(uint hid) {
        require(msg.sender == bets[hid].initiator);
        _;
    }

    modifier onlyBetor(uint hid) {
        require(bets[hid].betors[msg.sender].value > 0);
        _;
    }

    modifier initiatorOrBetors(uint hid) {
        require(bets[hid].betors[msg.sender].value > 0 || msg.sender == bets[hid].initiator);
        _;
    }

    modifier onlyReferee() {
        require(msg.sender == referee);
        _;
    }

    event __init(uint hid, S state, uint balance, uint escrow, bytes32 offchain); 

    /**
     * @dev Create a new bet.
     * @param acceptors address of users will receive bet.
     * @param goal amount money (in Wei) of users join bet.
     * @param escrow money (in Wei) of initor.
     * @param deadline duration (in seconds) event happen.
     * @param offchain key to the offchain database.
     */
    function initBet(address[] acceptors, uint goal, uint escrow, uint deadline, bytes32 offchain) public payable {
        require(msg.value == escrow);

        Bet memory b;
        b.initiator = msg.sender;
        b.goal = goal; 
        b.escrow = escrow;
        b.deadline = now + deadline * 1 seconds;
        b.state = S.Inited;
        b.acceptors = acceptors;
        
        bets.push(b);
        emit __init(bets.length - 1, S.Inited, b.balance, b.escrow, offchain);
    }

    event __shake(uint hid, S state, uint balance, uint escrow, bytes32 offchain);

    // Payer join bet
    function shake(uint hid, bytes32 offchain) public payable {
        Bet storage b = bets[hid];
        require((b.state == S.Inited || b.state == S.Shaked) && msg.value > 0 && now < b.deadline);

        if (b.acceptors.length != 0) {
            require(isValidAcceptor(hid, msg.sender) == true);
        }

        if (b.betors[msg.sender].value == 0) {
            b.addresses.push(msg.sender);
        }
        
        b.betors[msg.sender].value += msg.value;
        b.betors[msg.sender].winValue += ((msg.value * b.escrow) / b.goal);
        b.balance += msg.value;
        require(b.balance <= b.goal);
        
        b.state = S.Shaked;
        emit __shake(hid, b.state, b.balance, b.escrow, offchain);
    }

    event __cancelBet(uint hid, S state, uint balance, uint escrow, bytes32 offchain);

    //  both of initiator or betor can cancel bet if time exceed review window
    function cancelBet(uint hid, bytes32 offchain) public initiatorOrBetors(hid) {
        Bet storage b = bets[hid];
        require(now >= b.deadline + reviewWindow && b.state == S.Shaked);

        b.state = S.Cancelled;
        emit __cancelBet(hid, b.state, b.balance, b.escrow, offchain);
    }

    event __closeBet(uint hid, S state, uint balance, uint escrow, bytes32 offchain);

    // Initiator close bet
    function closeBet(uint hid, bytes32 offchain) public onlyInitiator(hid) {
        Bet storage b = bets[hid];
        require(b.balance < b.goal);
        if (b.addresses.length == 0 && b.state == S.Inited) {
            msg.sender.transfer(b.escrow);
            b.escrow = 0; 
            b.state = S.Closed;

        } else if(b.state == S.Shaked) {
            uint remainingMoney = b.escrow - ((b.balance * b.escrow) / b.goal);
            b.escrow -= remainingMoney;
            b.goal = b.balance;
            msg.sender.transfer(remainingMoney);
        }
        
        emit __closeBet(hid, b.state, b.balance, b.escrow, offchain);
    }

    event __initiatorWon(uint hid, S state, uint balance, uint escrow, bytes32 offchain); 
  
    function initiatorWon(uint hid, bytes32 offchain) public initiatorOrBetors(hid) {
        Bet storage b = bets[hid]; 
        require(b.state == S.Shaked && now > b.deadline * 1 seconds); 
        b.state = S.InitiatorWon; 

        emit __initiatorWon(hid, b.state, b.balance, b.escrow, offchain);
    }

    event __betorWon(uint hid, S state, uint balance, uint escrow, bytes32 offchain); 

    function betorWon(uint hid, bytes32 offchain) public initiatorOrBetors(hid) {
        Bet storage b = bets[hid]; 
        require(b.state == S.Shaked && now > b.deadline * 1 seconds);
        b.state = S.BetorWon;

        emit __betorWon(hid, b.state, b.balance, b.escrow, offchain);
    }

    event __draw(uint hid, S state, uint balance, uint escrow, bytes32 offchain); 

    function draw(uint hid, bytes32 offchain) public initiatorOrBetors(hid) {
        Bet storage b = bets[hid]; 
        require(b.state == S.Shaked && now > b.deadline * 1 seconds); 
        b.state = S.Draw;

        emit __draw(hid, b.state, b.balance, b.escrow, offchain);
    }

    event __withdraw(uint hid, S state, uint balance, uint escrow, bytes32 offchain);

    function withdraw(uint hid, bytes32 offchain) public initiatorOrBetors(hid) {
        Bet storage b = bets[hid]; 
        if (b.state != S.Accepted) {
            if(b.state == S.Cancelled) {
                b.result = uint8(S.Draw);
            } else {
                require(now > b.deadline + rejectWindow);
                if (b.state == S.InitiatorWon || b.state == S.BetorWon || b.state == S.Draw) {
                    b.result = uint8(b.state);
                }
            }
            b.state = S.Accepted;
        }
        require(b.state == S.Accepted);
        if (b.result == uint8(S.InitiatorWon)) {
            require(msg.sender == b.initiator);
            if(b.initiator == msg.sender && b.escrow > 0) {
                b.initiator.transfer(b.escrow + b.balance);
                b.escrow = 0;
                b.balance = 0;
            }
            
        } else if (b.result == uint8(S.BetorWon)) {
            require(b.betors[msg.sender].value > 0);
            if(b.balance > 0) {
                Betor storage p = b.betors[msg.sender];
                b.escrow -= p.winValue;
                b.balance -= p.value;
                msg.sender.transfer(p.winValue);
                p.value = 0;
                p.winValue = 0;
            }
            
        } else if (b.result == uint8(S.Draw)) { 
            if(b.initiator == msg.sender && b.escrow > 0) {
                b.initiator.transfer(b.escrow);
                b.escrow = 0;
                
            } else if (b.betors[msg.sender].value > 0) {
                if(b.balance > 0) {
                    Betor storage p1 = b.betors[msg.sender];
                    b.balance -= p1.value;
                    msg.sender.transfer(p1.value);
                    p1.value = 0;
                    p1.winValue = 0;
                }
            }
        }

        // TODO: transfer 1% fee to referee
        if (b.balance == 0 && b.escrow == 0) {
            b.state = S.Done;   
        }

        emit __withdraw(hid, b.state, b.balance, b.escrow, offchain);
    }

    event __reject(uint hid, S state, uint balance, uint escrow, bytes32 offchain);

    function reject(uint hid, bytes32 offchain) public initiatorOrBetors(hid) {
        Bet storage b = bets[hid]; 
        require(b.state == S.InitiatorWon || b.state == S.Draw || b.state == S.BetorWon); 

        b.state = S.Rejected;
        emit __reject(hid, b.state, b.balance, b.escrow, offchain);
    }

    event __setWinner(uint hid, S state, uint balance, uint escrow, bytes32 offchain);

    // referee will set the winner if there is a dispute    
    function setWinner(uint hid, uint8 result, bytes32 offchain) public onlyReferee() {
        Bet storage b = bets[hid];
        require(b.state == S.Rejected && (result == uint8(S.InitiatorWon) || result == uint8(S.Draw) || result == uint8(S.BetorWon)));
        b.state = S.Accepted;
        b.result = result; 
        emit __setWinner(hid, b.state, b.balance, b.escrow, offchain);
    }
    
    function isValidAcceptor(uint hid, address acceptor) private view returns (bool value) {
        Bet storage b = bets[hid];
        for (uint index = 0; index < b.acceptors.length; index++) {
            if (b.acceptors[index] == acceptor) {
                value = true;
                return;
            }
        }
    }

    function getWinValue(uint hid) public view returns (uint) {
        Bet storage b = bets[hid];
        if (msg.sender == b.initiator) {
            return b.balance;
        }
        return b.betors[msg.sender].winValue;
    }
}
