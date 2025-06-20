// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Project {
    // Events
    event TransactionSubmitted(uint256 indexed transactionId, address indexed submitter, address indexed to, uint256 value);
    event TransactionConfirmed(uint256 indexed transactionId, address indexed confirmer);
    event TransactionRevoked(uint256 indexed transactionId, address indexed revoker);
    event TransactionExecuted(uint256 indexed transactionId, address indexed executor);
    event OwnerAdded(address indexed newOwner);
    event OwnerRemoved(address indexed removedOwner);
    event RequirementChanged(uint256 newRequirement);

    // Structs
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmationCount;
        mapping(address => bool) confirmations;
    }

    // State variables
    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public required;
    uint256 public transactionCount;
    mapping(uint256 => Transaction) public transactions;

    // Modifiers
    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }

    modifier transactionExists(uint256 _transactionId) {
        require(_transactionId < transactionCount, "Transaction does not exist");
        _;
    }

    modifier notExecuted(uint256 _transactionId) {
        require(!transactions[_transactionId].executed, "Transaction already executed");
        _;
    }

    modifier notConfirmed(uint256 _transactionId) {
        require(!transactions[_transactionId].confirmations[msg.sender], "Transaction already confirmed by sender");
        _;
    }

    modifier validRequirement(uint256 _ownerCount, uint256 _required) {
        require(_ownerCount > 0 && _required > 0 && _required <= _ownerCount, "Invalid requirement");
        _;
    }

    // Constructor
    constructor(address[] memory _owners, uint256 _required) 
        validRequirement(_owners.length, _required) 
    {
        require(_owners.length > 0, "Owners required");
        
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner address");
            require(!isOwner[owner], "Owner not unique");
            
            isOwner[owner] = true;
            owners.push(owner);
        }
        
        required = _required;
    }

    // Core Function 1: Submit Transaction
    function submitTransaction(address _to, uint256 _value, bytes memory _data) 
        public 
        onlyOwner 
        returns (uint256 transactionId) 
    {
        require(_to != address(0), "Invalid destination address");
        
        transactionId = transactionCount;
        
        Transaction storage transaction = transactions[transactionId];
        transaction.to = _to;
        transaction.value = _value;
        transaction.data = _data;
        transaction.executed = false;
        transaction.confirmationCount = 0;
        
        transactionCount++;
        
        emit TransactionSubmitted(transactionId, msg.sender, _to, _value);
        
        // Automatically confirm the transaction by the submitter
        confirmTransaction(transactionId);
        
        return transactionId;
    }

    // Core Function 2: Confirm Transaction
    function confirmTransaction(uint256 _transactionId) 
        public 
        onlyOwner 
        transactionExists(_transactionId) 
        notConfirmed(_transactionId) 
        notExecuted(_transactionId) 
    {
        Transaction storage transaction = transactions[_transactionId];
        transaction.confirmations[msg.sender] = true;
        transaction.confirmationCount++;
        
        emit TransactionConfirmed(_transactionId, msg.sender);
        
        // Automatically execute if enough confirmations
        if (transaction.confirmationCount >= required) {
            executeTransaction(_transactionId);
        }
    }

    // Core Function 3: Execute Transaction
    function executeTransaction(uint256 _transactionId) 
        public 
        onlyOwner 
        transactionExists(_transactionId) 
        notExecuted(_transactionId) 
    {
        Transaction storage transaction = transactions[_transactionId];
        require(transaction.confirmationCount >= required, "Not enough confirmations");
        require(address(this).balance >= transaction.value, "Insufficient contract balance");
        
        transaction.executed = true;
        
        (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);
        require(success, "Transaction execution failed");
        
        emit TransactionExecuted(_transactionId, msg.sender);
    }

    // Helper functions
    function revokeConfirmation(uint256 _transactionId) 
        public 
        onlyOwner 
        transactionExists(_transactionId) 
        notExecuted(_transactionId) 
    {
        require(transactions[_transactionId].confirmations[msg.sender], "Transaction not confirmed by sender");
        
        Transaction storage transaction = transactions[_transactionId];
        transaction.confirmations[msg.sender] = false;
        transaction.confirmationCount--;
        
        emit TransactionRevoked(_transactionId, msg.sender); // You might want a separate event for revocation
    }

    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    function getTransactionCount(bool _pending, bool _executed) 
        public 
        view 
        returns (uint256 count) 
    {
        for (uint256 i = 0; i < transactionCount; i++) {
            if ((_pending && !transactions[i].executed) || (_executed && transactions[i].executed)) {
                count++;
            }
        }
    }

    function getTransaction(uint256 _transactionId) 
        public 
        view 
        transactionExists(_transactionId) 
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 confirmationCount
        ) 
    {
        Transaction storage transaction = transactions[_transactionId];
        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.confirmationCount
        );
    }

    function getConfirmations(uint256 _transactionId) 
        public 
        view 
        transactionExists(_transactionId) 
        returns (address[] memory confirmingOwners) 
    {
        address[] memory temp = new address[](owners.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < owners.length; i++) {
            if (transactions[_transactionId].confirmations[owners[i]]) {
                temp[count] = owners[i];
                count++;
            }
        }
        
        confirmingOwners = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            confirmingOwners[i] = temp[i];
        }
    }

    function isConfirmed(uint256 _transactionId) 
        public 
        view 
        transactionExists(_transactionId) 
        returns (bool) 
    {
        return transactions[_transactionId].confirmationCount >= required;
    }

    // Fallback function to receive Ether
    receive() external payable {}

    // Function to get contract balance
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
