pragma solidity ^0.4.11;

/*
Defines ownership of CONTRACT, this should not need to change, but should be ABLE to
change and ( TODO: ) structures built to moderate this
*/
contract owned {
    address public owner;

    function owned() {

        //for allowing anyone with contract to modify build parameters, values and send down the line.  For now, we'll keep it centralized (toggle for testing later)
        owner = msg.sender;
        //for now, setting this to test account mainbase to disable transferownership (but wanted to include this construct)
        //owner = 0xd21215F1b924983944a7211Cb35BF84737FF04bc ;
    }

    modifier onlyOwner {
        if (msg.sender != owner) revert();
        _;
    }

    function transferOwnership(address newOwner) onlyOwner {
        owner = newOwner;
    }
}

/* (s)he who is bestowed kru, hath been kruited, etc. */
contract tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData); }

contract token {
    /* Public characteristics in parameters for test env */
    string public standard = 'Token 0.1';
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    /* addreses / balances of all token owners */
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;

    /*
    Public event: notify all (listening) blockchain clients of change
    this could be:
     ; involved parties
     ; named third parties
     ; miners
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /* Initializes contract (create the coin) with initial kru supply (to the creator of the contract) */
    function token(
    uint256 initialSupply,
    string tokenName,
    uint8 decimalUnits,
    string tokenSymbol
    ) {
        balanceOf[msg.sender] = initialSupply;              // All initial kru created in owner account
        totalSupply = initialSupply;                        /* Update total supply ( so, on re-issuance -
                                                               TODO: current total needs to be considered here) */
        name = tokenName;                                   // Token Name for display purposes (menus, etc)
        symbol = tokenSymbol;                               // Symbol name for display purposes
        decimals = decimalUnits;                            // Amount of decimals for display purposes
    }

    /* Send kru */
    function transfer(address _to, uint256 _value) {
        if (balanceOf[msg.sender] < _value) revert();           // does sender have the kru
        if (balanceOf[_to] + _value < balanceOf[_to]) revert(); // overflow protect
        //TODO: check if unnamed function call as callback can be injected as in backtrack implementation
        balanceOf[msg.sender] -= _value;                     // Subtract from sender
        balanceOf[_to] += _value;                            // Add to recipient
        Transfer(msg.sender, _to, _value);                   // Notify anyone listening that this transfer took place
    }

    /*
      Allow another contract to spend tokens for you (approval required)
      This allows us to more effectively share eth in test environment but we should:
      ( TODO: ) build hook(s) for auto-incentivization here (agency/company) (share) (spending 'rebate')
      */
    function approve(address _spender, uint256 _value)
    returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    /* Approve and then communicate the approved contract in a single tx */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData)
    returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }

    /* A contract attempts to get the coins */
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        if (balanceOf[_from] < _value) revert();                 // does sender have the kru
        if (balanceOf[_to] + _value < balanceOf[_to]) revert();  // overflow protect
        //TODO: check if unnamed function call as callback can be injected as in backtrack implementation
        if (_value > allowance[_from][msg.sender]) revert();     // Check allowance
        balanceOf[_from] -= _value;                           // Subtract value from sender
        balanceOf[_to] += _value;                             // Add to recipient
        allowance[_from][msg.sender] -= _value;               /* sender pays gas  (should we
                                                                TODO: include this in the allowance check?)
                                                                */
        Transfer(_from, _to, _value);                         // execute
        return true;
    }

    /* This unnamed function is called whenever someone tries to send ether to it */
    function () {
        revert();     // Prevents accidental sending of ether
    }
}



/*

token advanced management

*/
contract TestKruToken is owned, token {

    //if we want to modify kru external value for sale
    uint256 public sellPrice;
    uint256 public buyPrice;

    //ensure no one drops below this amount of ether to back transactions
    uint minBalanceForAccounts = 5;

    //map a frozen state for any account with Kru - ability to freeze funds / account
    mapping (address => bool) public frozenAccount;

    /* Create a Public event on the blockchain that will notify clients */
    event FrozenFunds(address target, bool frozen);

    /* This is our Kru.  Iinitialize contract - seed kru to mainbase */
    function TestKruToken(
    uint256 initialSupply,
    string tokenName,
    uint8 decimalUnits,
    string tokenSymbol,
    uint minBalance) token (initialSupply, tokenName, decimalUnits, tokenSymbol) {
        setMinBalance(minBalance);
    }

    /* Send kru */
    function transfer(address _to, uint256 _value) {
        if (balanceOf[msg.sender] < _value) revert();           // Check if the sender has enough
        if (balanceOf[_to] + _value < balanceOf[_to]) revert(); // Check for overflows
        /*TODO: check if unnamed function call as callback can be injected as in backtrack implementation
         (this fix, if needed, should be put into the originating object but I want to note it anyway)*/

        if (frozenAccount[msg.sender]) revert();                // Check if frozen
        //if (!approvedAccount[msg.sender]) revert();            //disabled: whitelisting

        balanceOf[msg.sender] -= _value;                     // Subtract from the sender
        balanceOf[_to] += _value;                            // Add the same to the recipient

        /*
        'NO GAS' policy:
            contract owner (kru bank) additionally pays the added minimum fee required for a
            receiver with NO GAS - so they are able to hold / sell the amount received.
        */
        if(msg.sender.balance<minBalanceForAccounts)
        sell((minBalanceForAccounts-msg.sender.balance)/sellPrice);

        /*
        disabled: 'pay it forward' method / model as an alternative to the above 'No Gas' policy where the sender
        pays the gas for the receivers's SALE if they have less than the gas fee required to make the sale at a
        later date.

            if(_to.balance<minBalanceForAccounts)
            _to.send(sell((minBalanceForAccounts-_to.balance)/sellPrice));
       */



    Transfer(msg.sender, _to, _value);                   // Notify anyone listening that this transfer took place
    }

    /*
     AUTO TOPUP
     for testkru - ensure if anyone's ether gets too low to transfer kru comfortably, the contract
     will auto-topup that user's eth so keep in mind, anyone given testkru is given will also
     always have enough eth to give / trade them away
    */

    function setMinBalance(uint minimumBalanceInFinney) onlyOwner {
        minBalanceForAccounts = minimumBalanceInFinney * 1 finney;
    }

    /* A contract attempts to get the kru */
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        if (frozenAccount[_from]) revert();                       // Check if frozen
        if (balanceOf[_from] < _value) revert();                  // Check if the sender has enough
        if (balanceOf[_to] + _value < balanceOf[_to]) revert();  // Check for overflows
        if (_value > allowance[_from][msg.sender]) revert();     // Check allowance
        balanceOf[_from] -= _value;                           // Subtract from sender
        balanceOf[_to] += _value;                             // Add to recipient
        allowance[_from][msg.sender] -= _value;               /* sender pays gas  (should we be
                                                                TODO: including this in the allowance check?) */
        Transfer(_from, _to, _value);                         // execute
        return true;
    }


    /* Mint new Kru - initially combine new seed round to existing total in owner account */
    function mintToken(address target, uint256 mintedAmount) onlyOwner {
        balanceOf[target] += mintedAmount;
        totalSupply += mintedAmount;
        Transfer(0, this, mintedAmount);
        Transfer(this, target, mintedAmount);
    }

    /*  freeze / unfreeze any account.
        TODO: build safety function to 'FreezeAll' for any type of outtage, issue, etc.
    */
    function freezeAccount(address target, bool freeze) onlyOwner {
        frozenAccount[target] = freeze;
        FrozenFunds(target, freeze);
    }


    /*  disabled:

        this function could be used to replace the implementation of freezing, if we used instead
        a 'moderated' user approach, where all users were NOT allowed to use the network by default
        until they were explicitly 'allowed' via a whitelist... for now, it is disabled
        function freezeAccount(address target, bool freeze) onlyOwner {
            frozenAccount[target] = freeze;
            FrozenFunds(target, freeze);
        }
    */

    /* set initial eth equivalent price for kru */
    function setPrices(uint256 newSellPrice, uint256 newBuyPrice) onlyOwner {
        sellPrice = newSellPrice;
        buyPrice = newBuyPrice;
    }

    /* cash out ... well, 'eth' out */
    function buy() payable {
        uint amount = msg.value / buyPrice;                // calculates the amount
        if (balanceOf[this] < amount) revert();               // checks if it has enough to sell
        balanceOf[msg.sender] += amount;                   // adds the amount to buyer's balance
        balanceOf[this] -= amount;                         // subtracts amount from seller's balance
        Transfer(this, msg.sender, amount);                // execute an event reflecting the change
    }

    function sell(uint256 amount) {
        if (balanceOf[msg.sender] < amount ) revert();        // checks if the sender has enough to sell
        balanceOf[this] += amount;                         // adds the amount to owner's balance
        balanceOf[msg.sender] -= amount;                   // subtracts the amount from seller's balance
        if (!msg.sender.send(amount * sellPrice)) {        // sends ether to the seller. It's important
            revert();                                         // to do this last to avoid recursion attacks
        } else {
            Transfer(msg.sender, this, amount);            // executes an event reflecting the change
        }
    }


    /*
    Disabled:
    basic kru hashing 'Proof of Work' mining capability

    bytes32 public currentChallenge;                         // The initial kru challenge
    uint public timeOfLastProof;                             // Variable to keep track of when rewards were given
    uint public difficulty = 10**32;                         // Difficulty starts reasonably low - set low in the constructor

    function proofOfWork(uint nonce){
        bytes8 n = bytes8(sha3(nonce, currentChallenge));    // Generate a random hash based on input
        if (n < bytes8(difficulty)) revert();                   // Check if it's under the difficulty

        uint timeSinceLastProof = (now - timeOfLastProof);  // Calculate time since last reward was given
        if (timeSinceLastProof <  5 seconds) revert();         // Rewards cannot be given too quickly
        balanceOf[msg.sender] += timeSinceLastProof / 60 seconds;  // The reward to the winner grows by the minute

        difficulty = difficulty * 10 minutes / timeSinceLastProof + 1;  // Adjusts the difficulty
        /*( This is kept to a very low difficulty level by resetting the timeofproof to 'now' in the token constructor )*//*

        timeOfLastProof = now;                              // Reset the counter
        currentChallenge = sha3(nonce, currentChallenge, block.blockhash(block.number-1));  // Save a hash that will be used as the next proof
    }

    End Disabled
    */

 }



/*
ONCE rendered - the address and interface will be placed in these comments for full review

JSON Interface:
[ { "constant": false, "inputs": [ { "name": "newSellPrice", "type": "uint256" }, { "name": "newBuyPrice", "type": "uint256" } ], "name": "setPrices", "outputs": [], "payable": false, "type": "function" }, { "constant": true, "inputs": [], "name": "name", "outputs": [ { "name": "", "type": "string", "value": "TestKru" } ], "payable": false, "type": "function" }, { "constant": false, "inputs": [ { "name": "_spender", "type": "address" }, { "name": "_value", "type": "uint256" } ], "name": "approve", "outputs": [ { "name": "success", "type": "bool" } ], "payable": false, "type": "function" }, { "constant": true, "inputs": [], "name": "totalSupply", "outputs": [ { "name": "", "type": "uint256", "value": "10000" } ], "payable": false, "type": "function" }, { "constant": false, "inputs": [ { "name": "_from", "type": "address" }, { "name": "_to", "type": "address" }, { "name": "_value", "type": "uint256" } ], "name": "transferFrom", "outputs": [ { "name": "success", "type": "bool" } ], "payable": false, "type": "function" }, { "constant": true, "inputs": [], "name": "decimals", "outputs": [ { "name": "", "type": "uint8", "value": "4" } ], "payable": false, "type": "function" }, { "constant": true, "inputs": [], "name": "sellPrice", "outputs": [ { "name": "", "type": "uint256", "value": "0" } ], "payable": false, "type": "function" }, { "constant": true, "inputs": [], "name": "standard", "outputs": [ { "name": "", "type": "string", "value": "Token 0.1" } ], "payable": false, "type": "function" }, { "constant": true, "inputs": [ { "name": "", "type": "address" } ], "name": "balanceOf", "outputs": [ { "name": "", "type": "uint256", "value": "0" } ], "payable": false, "type": "function" }, { "constant": false, "inputs": [ { "name": "target", "type": "address" }, { "name": "mintedAmount", "type": "uint256" } ], "name": "mintToken", "outputs": [], "payable": false, "type": "function" }, { "constant": true, "inputs": [], "name": "buyPrice", "outputs": [ { "name": "", "type": "uint256", "value": "0" } ], "payable": false, "type": "function" }, { "constant": true, "inputs": [], "name": "owner", "outputs": [ { "name": "", "type": "address", "value": "0xd21215f1b924983944a7211cb35bf84737ff04bc" } ], "payable": false, "type": "function" }, { "constant": true, "inputs": [], "name": "symbol", "outputs": [ { "name": "", "type": "string", "value": "%" } ], "payable": false, "type": "function" }, { "constant": false, "inputs": [], "name": "buy", "outputs": [], "payable": true, "type": "function" }, { "constant": false, "inputs": [ { "name": "_to", "type": "address" }, { "name": "_value", "type": "uint256" } ], "name": "transfer", "outputs": [], "payable": false, "type": "function" }, { "constant": true, "inputs": [ { "name": "", "type": "address" } ], "name": "frozenAccount", "outputs": [ { "name": "", "type": "bool", "value": false } ], "payable": false, "type": "function" }, { "constant": false, "inputs": [ { "name": "minimumBalanceInFinney", "type": "uint256" } ], "name": "setMinBalance", "outputs": [], "payable": false, "type": "function" }, { "constant": false, "inputs": [ { "name": "_spender", "type": "address" }, { "name": "_value", "type": "uint256" }, { "name": "_extraData", "type": "bytes" } ], "name": "approveAndCall", "outputs": [ { "name": "success", "type": "bool" } ], "payable": false, "type": "function" }, { "constant": true, "inputs": [ { "name": "", "type": "address" }, { "name": "", "type": "address" } ], "name": "allowance", "outputs": [ { "name": "", "type": "uint256", "value": "0" } ], "payable": false, "type": "function" }, { "constant": false, "inputs": [ { "name": "amount", "type": "uint256" } ], "name": "sell", "outputs": [], "payable": false, "type": "function" }, { "constant": false, "inputs": [ { "name": "target", "type": "address" }, { "name": "freeze", "type": "bool" } ], "name": "freezeAccount", "outputs": [], "payable": false, "type": "function" }, { "constant": false, "inputs": [ { "name": "newOwner", "type": "address" } ], "name": "transferOwnership", "outputs": [], "payable": false, "type": "function" }, { "inputs": [ { "name": "initialSupply", "type": "uint256", "index": 0, "typeShort": "uint", "bits": "256", "displayName": "initial Supply", "template": "elements_input_uint", "value": "10000" }, { "name": "tokenName", "type": "string", "index": 1, "typeShort": "string", "bits": "", "displayName": "token Name", "template": "elements_input_string", "value": "TestKru" }, { "name": "decimalUnits", "type": "uint8", "index": 2, "typeShort": "uint", "bits": "8", "displayName": "decimal Units", "template": "elements_input_uint", "value": "4" }, { "name": "tokenSymbol", "type": "string", "index": 3, "typeShort": "string", "bits": "", "displayName": "token Symbol", "template": "elements_input_string", "value": "%" }, { "name": "minBalance", "type": "uint256", "index": 4, "typeShort": "uint", "bits": "256", "displayName": "min Balance", "template": "elements_input_uint", "value": "5" } ], "payable": false, "type": "constructor" }, { "payable": false, "type": "fallback" }, { "anonymous": false, "inputs": [ { "indexed": false, "name": "target", "type": "address" }, { "indexed": false, "name": "frozen", "type": "bool" } ], "name": "FrozenFunds", "type": "event" }, { "anonymous": false, "inputs": [ { "indexed": true, "name": "from", "type": "address" }, { "indexed": true, "name": "to", "type": "address" }, { "indexed": false, "name": "value", "type": "uint256" } ], "name": "Transfer", "type": "event" } ]

Address:
0x7AeA7E4feB6117E026195D281a82Af5B33c01326
*/
