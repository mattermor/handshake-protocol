/*
*
* PredictionExchange is an exchange contract that doesn't accept bets on the outcomes,
* but instead matchedes backers/takers (those betting on odds) with layers/makers 
* (those offering the odds).
*
* Note:
*
*       side: 0 (unknown), 1 (support), 2 (against)
*       role: 0 (unknown), 1 (maker), 2 (taker)
*       state: 0 (unknown), 1 (created), 2 (reported), 3 (disputed)
*       __test__* events will be removed prior to production deployment
*       odds are rounded up (2.25 is 225)
*
*/

pragma solidity ^0.4.24;

contract PredictionHandshake {

        struct Market {

                address creator;
                uint fee; 
                bytes32 source;
                uint closingTime; 
                uint reportTime; 
                uint disputeTime;

                uint state;
                uint outcome;

                uint totalOpenStake;
                uint totalMatchedStake;
                uint disputeMatchedStake;
                bool resolved;

                mapping(address => mapping(uint => Order)) open; // address => side => order
                mapping(address => mapping(uint => Order)) matched; // address => side => order
                mapping(address => bool) disputed;
        }
        
        
        function getMatchedData(uint hid, uint side, address user, uint userOdds) public onlyRoot view returns 
        (
            uint256,
            uint256,
            uint256,
            uint256
        ) 
        {
            Market storage m = markets[hid];
            Order storage o = m.matched[user][side];
            // return (stake, payout, odds, pool size)
            return (o.stake, o.payout, userOdds, o.odds[userOdds]);
        }
        
        function getOpenData(uint hid, uint side, address user, uint userOdds) public onlyRoot view returns 
        (
            uint256,
            uint256,
            uint256,
            uint256
        ) 
        {
            Market storage m = markets[hid];
            Order storage o = m.open[user][side];
            // return (stake, payout, odds, pool size)
            return (o.stake, o.payout, userOdds, o.odds[userOdds]);
        }

        struct Order {
                uint stake;
                uint payout;
                mapping(uint => uint) odds; // odds => pool size
        }

        struct Trial {
                uint hid;
                uint side;
                mapping(uint => uint) amt; // odds => amt
        }

        uint public NETWORK_FEE = 20; // 20%
        uint public ODDS_1 = 100; // 1.00 is 100; 2.25 is 225 
        uint public DISPUTE_THRESHOLD = 5; // 5%
        uint public EXPIRATION = 30 days; 

        Market[] public markets;
        address public root;
        uint256 public total;

        mapping(address => Trial) trial;

        constructor() public {
                root = msg.sender;
        } 


        event __createMarket(uint hid, bytes32 offchain); 

        function createMarket(
                uint fee, 
                bytes32 source,
                uint closingWindow, 
                uint reportWindow, 
                uint disputeWindow,
                bytes32 offchain
        ) 
                public 
        {
                Market memory m;
                m.creator = msg.sender;
                m.fee = fee;
                m.source = source;
                m.closingTime = now + closingWindow * 1 seconds;
                m.reportTime = m.closingTime + reportWindow * 1 seconds;
                m.disputeTime = m.reportTime + disputeWindow * 1 seconds;
                m.state = 1;
                markets.push(m);

                emit __createMarket(markets.length - 1, offchain);
        }


        event __init(uint hid, bytes32 offchain);
        event __test__init(uint stake);

        // market maker
        function init(
                uint hid, 
                uint side, 
                uint odds, 
                bytes32 offchain
        ) 
                public 
                payable 
        {
                _init(hid, side, odds, msg.sender, offchain);
        }


        // market maker. only called by root.  
        function initTestDrive(
                uint hid, 
                uint side, 
                uint odds, 
                address maker, 
                bytes32 offchain
        ) 
                public
                payable
                onlyRoot
        {
                trial[maker].hid = hid;
                trial[maker].side = side;
                trial[maker].amt[odds] += msg.value;

                _init(hid, side, odds, maker, offchain);
        }
        
        event __uninitTestDrive(uint hid, bytes32 offchain);
        
        function uninitTestDrive
        (
            uint hid,
            uint side,
            uint odds,
            address maker,
            uint value,
            bytes32 offchain
        )
            public
            onlyRoot
        {
            // make sure trial is existed and currently betting.
            require(trial[maker].hid == hid && trial[maker].side == side && trial[maker].amt[odds] > 0);
            trial[maker].amt[odds] -= value;
            
            Market storage m = markets[hid];
            
            require(m.open[maker][side].stake >= value);
            require(m.open[maker][side].odds[odds]  >= value);
            require(m.totalOpenStake  >= value);

            m.open[maker][side].stake -= value;
            m.open[maker][side].odds[odds] -= value;
            m.totalOpenStake -= value;

            require(total + value >= total);
            total += value;
            
            emit __uninitTestDrive(hid, offchain);
        }
        
        event __withdrawTrial(uint256 amount);

        function withdrawTrial() public onlyRoot {
            root.transfer(total);
            emit __withdrawTrial(total);
            total = 0;
        }
        
        // market maker cancels order
        function uninit(
                uint hid, 
                uint side, 
                uint stake, 
                uint odds, 
                bytes32 offchain
        ) 
                public 
                onlyPredictor(hid) 
        {
                Market storage m = markets[hid];

                uint trialAmt; 
                if (trial[msg.sender].hid == hid && trial[msg.sender].side == side)
                    trialAmt = trial[msg.sender].amt[odds];

                require(m.open[msg.sender][side].stake - trialAmt >= stake);
                require(m.open[msg.sender][side].odds[odds] - trialAmt >= stake);

                m.open[msg.sender][side].stake -= stake;
                m.open[msg.sender][side].odds[odds] -= stake;
                m.totalOpenStake -= stake;

                msg.sender.transfer(stake);

                emit __uninit(hid, offchain);
                emit __test__uninit(m.open[msg.sender][side].stake);
        }


        function _init(
                uint hid, 
                uint side, 
                uint odds, 
                address maker, 
                bytes32 offchain
        ) 
                private 
        {
                Market storage m = markets[hid];

                require(now < m.closingTime);
                require(m.state == 1);

                m.open[maker][side].stake += msg.value;
                m.open[maker][side].odds[odds] += msg.value;
                m.totalOpenStake += msg.value;

                emit __init(hid, offchain);
                emit __test__init(m.open[maker][side].stake);
        }


        event __uninit(uint hid, bytes32 offchain);
        event __test__uninit(uint stake);

        


        event __shake(uint hid, bytes32 offchain);
        event __test__shake__taker__matched(uint stake, uint payout);
        event __test__shake__maker__matched(uint stake, uint payout);
        event __test__shake__maker__open(uint stake);


        // market taker
        function shake(
                uint hid, 
                uint side, 
                uint takerOdds, 
                address maker, 
                uint makerOdds, 
                bytes32 offchain
        ) 
                public 
                payable 
        {
                _shake(hid, side, msg.sender, takerOdds, maker, makerOdds, offchain);
        }


        function shakeTestDrive(
                uint hid, 
                uint side, 
                address taker,
                uint takerOdds, 
                address maker, 
                uint makerOdds, 
                bytes32 offchain
        ) 
                public 
                payable 
                onlyRoot
        {
                trial[msg.sender].hid = hid;
                trial[msg.sender].side = side;
                trial[msg.sender].amt[takerOdds] += msg.value;

                _shake(hid, side, taker, takerOdds, maker, makerOdds, offchain);
        }


        function _shake(
                uint hid, 
                uint side, 
                address taker,
                uint takerOdds, 
                address maker, 
                uint makerOdds, 
                bytes32 offchain
        ) 
                private 
        {
                require(maker != 0);
                require(takerOdds >= ODDS_1);
                require(makerOdds >= ODDS_1);

                Market storage m = markets[hid];

                require(m.state == 1);
                require(now < m.closingTime);

                uint makerSide = 3 - side;

                uint takerStake = msg.value;
                uint makerStake = m.open[maker][makerSide].stake;

                uint takerPayout = (takerStake * takerOdds) / ODDS_1;
                uint makerPayout = (makerStake * makerOdds) / ODDS_1;

                if (takerPayout < makerPayout) {
                        makerStake = takerPayout - takerStake;
                        makerPayout = takerPayout;
                } else {
                        takerStake = makerPayout - makerStake;
                        takerPayout = makerPayout;
                }

                // check if the odds matching is valid
                require(takerOdds * ODDS_1 >= makerOdds * (takerOdds - ODDS_1));

                // check if the stake is sufficient
                require(m.open[maker][makerSide].odds[makerOdds] >= makerStake);
                require(m.open[maker][makerSide].stake >= makerStake);

                // remove maker's order from open (could be partial)
                m.open[maker][makerSide].odds[makerOdds] -= makerStake;
                m.open[maker][makerSide].stake -= makerStake;
                m.totalOpenStake -=  makerStake;

                // add maker's order to matched
                m.matched[maker][makerSide].odds[makerOdds] += makerStake;
                m.matched[maker][makerSide].stake += makerStake;
                m.matched[maker][makerSide].payout += makerPayout;
                m.totalMatchedStake += makerStake;

                // add taker's order to matched
                m.matched[taker][side].odds[takerOdds] += takerStake;
                m.matched[taker][side].stake += takerStake;
                m.matched[taker][side].payout += takerPayout;
                m.totalMatchedStake += takerStake;

                emit __shake(hid, offchain);

                emit __test__shake__taker__matched(m.matched[taker][side].stake, m.matched[taker][side].payout);
                emit __test__shake__maker__matched(m.matched[maker][makerSide].stake, m.matched[maker][makerSide].payout);
                emit __test__shake__maker__open(m.open[maker][makerSide].stake);

        }


        event __collect(uint hid, bytes32 offchain);
        event __test__collect(uint network, uint market, uint trader);

        function collect(uint hid, bytes32 offchain) public onlyPredictor(hid) {
                _collect(hid, msg.sender, offchain);
        }

        function collectTestDrive(uint hid, address winner, bytes32 offchain) public onlyRoot {
                _collect(hid, winner, offchain);
        }

        // collect payouts & outstanding stakes (if there is outcome)
        function _collect(uint hid, address winner, bytes32 offchain) private {
                Market storage m = markets[hid]; 

                require(m.state == 2);
                require(now > m.disputeTime);

                // calc network commission, market commission and winnings
                uint marketComm = (m.matched[winner][m.outcome].payout * m.fee) / 100;
                uint networkComm = (marketComm * NETWORK_FEE) / 100;

                uint amt = m.matched[winner][m.outcome].payout;

                amt += m.open[winner][1].stake; 
                amt += m.open[winner][2].stake;

                require(amt - marketComm > 0);
                require(marketComm - networkComm > 0);

                // update totals
                m.totalOpenStake -= m.open[winner][1].stake;
                m.totalOpenStake -= m.open[winner][2].stake;
                m.totalMatchedStake -= m.matched[winner][1].stake;
                m.totalMatchedStake -= m.matched[winner][2].stake;

                // wipe data
                m.open[winner][1].stake = 0; 
                m.open[winner][2].stake = 0;
                m.matched[winner][1].stake = 0; 
                m.matched[winner][2].stake = 0;
                m.matched[winner][m.outcome].payout = 0;

                winner.transfer(amt - marketComm);
                m.creator.transfer(marketComm - networkComm);
                root.transfer(networkComm);

                emit __collect(hid, offchain);
                emit __test__collect(networkComm, marketComm - networkComm, amt - marketComm);
        }


        event __refund(uint hid, bytes32 offchain);
        event __test__refund(uint amt);

        // refund stakes when market closes (if there is no outcome)
        function refund(uint hid, bytes32 offchain) public onlyPredictor(hid) {

                Market storage m = markets[hid]; 

                require(m.state == 1);
                require(now > m.reportTime);

                // calc refund amt
                uint amt;
                amt += m.matched[msg.sender][1].stake;
                amt += m.matched[msg.sender][2].stake;
                amt += m.open[msg.sender][1].stake;
                amt += m.open[msg.sender][2].stake;

                require(amt > 0);

                // wipe data
                m.matched[msg.sender][1].stake = 0;
                m.matched[msg.sender][2].stake = 0;
                m.open[msg.sender][1].stake = 0;
                m.open[msg.sender][2].stake = 0;

                msg.sender.transfer(amt);

                emit __refund(hid, offchain);
                emit __test__refund(amt);
        }


        event __report(uint hid, bytes32 offchain);

        // report outcome
        function report(uint hid, uint outcome, bytes32 offchain) public {
                Market storage m = markets[hid]; 
                require(m.closingTime < now && now <= m.reportTime);
                require(msg.sender == m.creator);
                require(m.state == 1);
                m.outcome = outcome;
                m.state = 2;
                emit __report(hid, offchain);
        }


        event __dispute(uint hid, uint state, bytes32 offchain);

        // dispute outcome
        function dispute(uint hid, bytes32 offchain) public onlyPredictor(hid) {
                Market storage m = markets[hid]; 

                require(now <= m.disputeTime);
                require(m.state == 2);
                require(!m.resolved);

                require(!m.disputed[msg.sender]);
                m.disputed[msg.sender] = true;

                m.disputeMatchedStake += m.matched[msg.sender][1].stake;
                m.disputeMatchedStake += m.matched[msg.sender][2].stake;

                // if dispute stakes > 5% of the total stakes
                if (100 * m.disputeMatchedStake > DISPUTE_THRESHOLD * m.totalMatchedStake) {
                        m.state = 3;
                }
                emit __dispute(hid, m.state, offchain);
        }


        event __resolve(uint hid, bytes32 offchain);

        function resolve(uint hid, uint outcome, bytes32 offchain) public onlyRoot {
                Market storage m = markets[hid]; 
                require(m.state == 3);
                m.resolved = true;
                m.outcome = outcome;
                m.state = outcome == 0? 1: 2;
                emit __resolve(hid, offchain);
        }


        event __shutdownMarket(uint hid, bytes32 offchain);

        // TODO: remove this function after 3 months once the system is stable
        function shutdownMarket(uint hid, bytes32 offchain) public onlyRoot {
                require(now > m.disputeTime + EXPIRATION);
                Market storage m = markets[hid];
                msg.sender.transfer(m.totalOpenStake + m.totalMatchedStake);
                emit __shutdownMarket(hid, offchain);
        }


        event __shutdownAllMarkets(bytes32 offchain);

        // TODO: remove this function after 3 months once the system is stable
        function shutdownAllMarkets(bytes32 offchain) public onlyRoot {
                msg.sender.transfer(address(this).balance);
                emit __shutdownAllMarkets(offchain);
        }


        modifier onlyPredictor(uint hid) {
                require(markets[hid].matched[msg.sender][1].stake > 0 || 
                        markets[hid].matched[msg.sender][2].stake > 0 || 
                        markets[hid].open[msg.sender][1].stake > 0 || 
                        markets[hid].open[msg.sender][2].stake > 0);
                _;
        }


        modifier onlyRoot() {
                require(msg.sender == root);
                _;
        }
}
