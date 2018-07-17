pragma solidity ^0.4.24;

contract ExchangeCash {

    address owner;

    constructor() public {
        owner = msg.sender;
    }
    uint fee = 0;// 0%

    enum S { Inited, Shaked, Rejected, Cancelled,Done }
    enum T { Station, Customer }

    struct Exchange {
        address stationOwner;
        address customer;
        uint escrow;
        S state;
        T exType;
    }

    Exchange[] public ex;
    event __setFee(uint fee);

    event __initByStationOwner(uint hid, address stationOwner, uint value,bytes32 offchain);
    event __closeByStationOwner(uint hid, bytes32 offchain);
    event __releasePartialFund(uint hid,address customer,uint amount,bytes32 offchainP,bytes32 offchainC);
    event __addInventory(uint hid, bytes32 offchain);

    event __initByCustomer(uint hid, address customer, address stationOwner, uint value,bytes32 offchain);
    event __cancel(uint hid, bytes32 offchain);
    event __shake(uint hid, bytes32 offchain);
    event __reject(uint hid, bytes32 offchain);
    event __finish(uint hid, bytes32 offchain);
    event __resetAllStation(bytes32 offchain,uint hid);


    //success if sender is stationOwner
    modifier onlyStationOwner(uint hid) {
        require(msg.sender == ex[hid].stationOwner);
        _;
    }

    //success if sender is customer
    modifier onlyCustomer(uint hid) {
        require(msg.sender == ex[hid].customer);
        _;
    }


    //success if sender is stationOwner or customer
    modifier onlyStationOwnerOrCustomer(uint hid) {
        require(msg.sender == ex[hid].stationOwner || msg.sender == ex[hid].customer);
        _;
    }

    //success if sender is owner
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier atState(S _s, uint hid) {
        require(_s == ex[hid].state);
        _;
    }

    /**
        * @dev Initiate exchange fee by owner
        * @param f exchange fee
        */
    function setFee(
        uint f
    )
        public
        onlyOwner()
    {
        fee = f;
        emit __setFee(fee);
    }
    /**
    * @dev Initiate handshake by stationOwner
    * @param offchain record ID in offchain backend database
    */
    function initByStationOwner(
        bytes32 offchain
    )
        public
        payable
    {
        require(msg.value > 0);
        Exchange memory p;
        p.stationOwner = msg.sender;
        p.escrow = msg.value;
        p.state = S.Inited;
        p.exType = T.Station;
        ex.push(p);
        emit __initByStationOwner(ex.length - 1, msg.sender, msg.value, offchain);
    }

    //CashOwner close the transaction after init
    function closeByStationOwner(uint hid, bytes32 offchain) public onlyStationOwner(hid)
        atState(S.Inited, hid)
    {
        Exchange storage p = ex[hid];
        require(p.exType == T.Station);
        p.state = S.Cancelled;
        msg.sender.transfer(p.escrow);
        p.escrow = 0;
        emit __closeByStationOwner(hid, offchain);
    }

    //CashOwner close the transaction after init
    function addInventory(uint hid, bytes32 offchain)
        public
        payable
        onlyStationOwner(hid)
        atState(S.Inited, hid)
    {
        Exchange storage p = ex[hid];
        require(p.exType == T.Station);
        p.escrow += msg.value;
        emit __addInventory(hid, offchain);
    }

    //CoinOwner releaseFundByStationOwner transaction
    function releasePartialFund(uint hid,address customer,uint amount, bytes32 offchainP, bytes32 offchainC) public onlyStationOwner(hid)
        atState(S.Inited, hid)
    {
        require(customer != 0x0 && amount > 0);
        Exchange storage p = ex[hid];
        require(p.exType == T.Station);

        uint f = (amount * fee) / 1000;
        uint t = amount + f;
        require(p.escrow >= t);
        p.escrow -= t;
        owner.transfer(f);
        customer.transfer(amount);
        if (p.escrow == 0) p.state = S.Done;
        emit __releasePartialFund(hid,customer, amount, offchainP, offchainC);
    }



    /**
    * @dev Initiate handshake by Customer
    */
    function initByCustomer(
        address stationOwner,
        bytes32 offchain
    )
        public
        payable
    {
        require(msg.value > 0);
        Exchange memory p;
        p.customer = msg.sender;
        p.stationOwner = stationOwner;
        p.escrow = msg.value;
        p.state = S.Inited;
        p.exType = T.Customer;
        ex.push(p);
        emit __initByCustomer(ex.length - 1, msg.sender,stationOwner,msg.value, offchain);
    }


    //coinOwner cancel the handshake
    function cancel(uint hid, bytes32 offchain) public
        onlyStationOwnerOrCustomer(hid)
        atState(S.Inited, hid)
    {
        Exchange storage p = ex[hid];
        p.state = S.Cancelled;
        msg.sender.transfer(p.escrow);
        p.escrow = 0;
        emit __cancel(hid, offchain);
    }

    //stationOwner agree and make a handshake
    function shake(uint hid, bytes32 offchain) public
        onlyStationOwner(hid)
        atState(S.Inited, hid)
    {
        Exchange storage p = ex[hid];

        require(p.customer != 0x0);
        require(p.exType == T.Customer);

        ex[hid].state = S.Shaked;
        emit __shake(hid, offchain);

    }

    //customer finish transaction for sending the coin to stationOwner
    function finish(uint hid, bytes32 offchain) public onlyCustomer(hid)
        atState(S.Shaked, hid)
    {
        Exchange storage p = ex[hid];
        require(p.escrow > 0);
        require(p.exType == T.Customer);
        uint f = (p.escrow * fee) / 1000;

        p.stationOwner.transfer(p.escrow-f);
        owner.transfer(f);
        p.escrow = 0;
        p.state = S.Done;
        emit __finish(hid, offchain);
    }


    //CashOwner reject the transaction
    function reject(uint hid, bytes32 offchain) public
        onlyStationOwnerOrCustomer(hid)
    {
        Exchange storage p = ex[hid];
        p.state = S.Rejected;
        p.customer.transfer(p.escrow);
        p.escrow = 0;
        emit __reject(hid, offchain);
    }

    //get handshake stage by hid
     function getState(uint hid) public constant returns(uint8){
        Exchange storage p = ex[hid];
        return uint8(p.state);
     }

      //get handshake balance by hid
      function getBalance(uint hid) public constant returns(uint){
         Exchange storage p = ex[hid];
         return p.escrow;
      }

     function resetAllStation(bytes32 offchain) public onlyOwner {

         for (uint i = 0; i < ex.length; i++) {
             Exchange storage p = ex[i];
             if(p.escrow > 0 && (p.state == S.Inited || p.state == S.Shaked)){
                 if(p.exType == T.Station && p.stationOwner != 0x0){
                    p.stationOwner.transfer(p.escrow);
                 }
                 if(p.exType == T.Customer && p.customer != 0x0){
                    p.customer.transfer(p.escrow);
                 }
                 p.escrow = 0;
                 p.state = S.Cancelled;
                 emit __resetAllStation(offchain,i);
             }
         }
     }

}