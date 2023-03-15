// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Utils.sol";
import "./ZKTBase.sol";
import "./TransferVerifier.sol";
import "./BurnVerifier.sol";
import "./ZKTBank.sol";
import "./ZKTFactory.sol";
import "./ZKTLog.sol";

contract Tsunami {

    using Utils for uint256;
    using Utils for Utils.ECPoint;
    using EnumerableMap for EnumerableMap.UintToAddressMap; 
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using ZKTLog for ZKTLog.Chain;

    EnumerableMap.UintToAddressMap private zkts;
    EnumerableSet.Bytes32Set private users;

    ZKTNativeFactory nativeFactory;
    ZKTERC20Factory erc20Factory;

    address public admin;

    mapping(bytes32 => ZKTLog.Chain) logChain; 

    uint public totalTransactions;

    event SetAdminSuccess(address admin);
    event RegisterSuccess(bytes32[2] y_tuple);

    constructor (address _nativeFactory, address _erc20Factory) {
        admin = msg.sender;

        nativeFactory = ZKTNativeFactory(_nativeFactory);
        erc20Factory = ZKTERC20Factory(_erc20Factory);

        address native = nativeFactory.newZKTNative(address(this));
        zkts.set(uint256(bytes32(bytes(nativeFactory.nativeSymbol()))), native); 
        ZKTBase(native).setUnit(10000000000000000);
        ZKTBase(native).setAgency(payable(msg.sender));
        ZKTBase(native).setAdmin(msg.sender);
    }

    /**
     * @dev Throws if called by any account other than the admin.
     */
    modifier onlyAdmin() {
        require(admin == msg.sender, "Caller is not the admin");
        _;
    }

    function setAdmin (address _admin) external onlyAdmin {
        admin = _admin;
        emit SetAdminSuccess(_admin);
    }

    function getSymbols () external view returns (string[] memory) {
        uint256 size = zkts.length();
        string[] memory symbols = new string[](size);
        for (uint256 i = 0; i < size; i++) {
            (uint256 key, ) = zkts.at(i);
            symbols[i] = string(abi.encodePacked(bytes32(key)));
        }
        return symbols;
    }

    function getZKT(string calldata symbol) public view returns (address) {
        (, address zktAddr) = zkts.tryGet(uint256(bytes32(bytes(symbol))));
        return zktAddr;
    }

    function addZKT(string calldata symbol, address token_contract_address) public onlyAdmin {
        bytes32 zktHash = keccak256(abi.encode(symbol));
        uint256 zktId = uint256(zktHash);

        bool zktExists = zkts.contains(zktId);
        if (zktExists) {
            revert("ZKT already exists for this token.");
        }

        address erc20 = erc20Factory.newZKTERC20(address(this), token_contract_address);
        zkts.set(uint256(bytes32(bytes(symbol))), erc20);
        ZKTBase(erc20).setUnit(10000000000000000);
        ZKTBase(erc20).setAgency(payable(msg.sender));
        ZKTBase(erc20).setAdmin(msg.sender);
    }

    function token(string calldata symbol) external view returns (address) {
        return ZKTBase(getZKT(symbol)).token();
    }

    function nativeSymbol() external view returns (string memory) {
        return nativeFactory.nativeSymbol();
    }

    function agency(string calldata symbol) external view returns (address) {
        return ZKTBase(getZKT(symbol)).agency();
    }

    function epochBase(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).epochBase();
    }

    function epochLength(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).epochLength();
    }

    function unit(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).unit();
    }

    function burn_fee_multiplier(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).burn_fee_multiplier();
    }

    function burn_fee_dividend(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).burn_fee_dividend();
    }

    function lastGlobalUpdate(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).lastGlobalUpdate();
    }

    function lastRollOver(string calldata symbol, bytes32 yHash) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).lastRollOver(yHash);
    }

    function totalBalance(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).totalBalance();
    }

    function totalUsers() external view returns (uint256) {
        return users.length(); 
    }

    function totalBurnFee(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).totalBurnFee();
    }

    function totalTransferFee(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).totalTransferFee();
    }

    function totalDeposits(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).totalDeposits();
    }

    function totalFundCount(string calldata symbol) external view returns (uint256) {
        return ZKTBase(getZKT(symbol)).totalFundCount();
    }

    function registered(bytes32 yHash) public view returns (bool) {
        return users.contains(yHash);
    }

    function registered(bytes32[2] calldata y) public view returns (bool) {
        bytes32 yHash = keccak256(abi.encode(y));
        return registered(yHash);
    }

    function register(bytes32[2] calldata y_tuple, uint256 c, uint256 s) external {
        // Calculate y
        Utils.ECPoint memory y = Utils.ECPoint({
            X: y_tuple[0],
            Y: y_tuple[1]
        });

        // Calculate K
        Utils.ECPoint memory K = Utils.g()
            .pMul(s)
            .pAdd(y.pMul(c.gNeg()));

        // Verify the signature
        uint256 challenge = uint256(keccak256(abi.encode(address(this), y, K))).gMod();
        require(challenge == c, "Signature is invalid!");

        // Check if account is already registered
        bytes32 yHash = keccak256(abi.encode(y));
        require(!registered(yHash), "The account has already been registered!");

        // Add user to set of registered users
        users.add(yHash);

        // Update total number of transactions and emit event
        totalTransactions += 1;
        emit RegisterSuccess(y_tuple);
    }

    function getBalance(string calldata symbol, bytes32[2][] calldata y_tuples, uint256 epoch) external view returns (bytes32[2][2][] memory accounts) {
        return ZKTBase(getZKT(symbol)).getBalance(y_tuples, epoch);
    }

    function getAccountState (string calldata symbol, bytes32[2] calldata y) external view returns (bytes32[2][2] memory y_available, bytes32[2][2] memory y_pending) {
        return ZKTBase(getZKT(symbol)).getAccountState(y); 
    }

    function getGuess (string calldata symbol, bytes32[2] memory y) public view returns (bytes memory y_guess) {
        return ZKTBase(getZKT(symbol)).getGuess(y);
    }

    function currentTimestamp() public view returns (uint256) {
        return block.timestamp;
    }

    function currentEpoch(string calldata symbol) public view returns (uint256) {
        return ZKTBase(getZKT(symbol)).currentEpoch();
    }

    function fund(string calldata symbol, bytes32[2] calldata y, uint256 unitAmount, bytes calldata encGuess) external payable {
        require(registered(y), "Account not yet registered.");
        address zktAddr = getZKT(symbol);
        ZKTBase(zktAddr).fund{value: msg.value}(y, unitAmount, encGuess);

        getLogChain(y).push(symbol, ZKTLog.Activity.Fund, msg.sender, zktAddr, unitAmount, block.timestamp);
        totalTransactions += 1;
    }

    function burn(string calldata symbol, bytes32[2] calldata y, uint256 unitAmount, bytes32[2] calldata u, bytes calldata proof, bytes calldata encGuess) external {
        require(registered(y), "Account not yet registered.");
        address zktAddr = getZKT(symbol);
        {
            ZKTBase(zktAddr).burnTo(msg.sender, y, unitAmount, u, proof, encGuess);
        }
        {
            ZKTLog.Item memory item = ZKTLog.Item({
                symbol: symbol, 
                activity: ZKTLog.Activity.Burn, 
                addr1: zktAddr,
                addr2: msg.sender,
                amount: unitAmount,
                timestamp: block.timestamp 
            });
            getLogChain(y).push(item);
        }
        totalTransactions += 1;
    }

    function burnTo(string calldata symbol, address sink, bytes32[2] calldata y, uint256 unitAmount, bytes32[2] memory u, bytes memory proof, bytes memory encGuess) external {
        require(registered(y), "Account not yet registered.");
        address zktAddr = getZKT(symbol);
        {
            ZKTBase(zktAddr).burnTo(sink, y, unitAmount, u, proof, encGuess);
        }
        {
            ZKTLog.Item memory item = ZKTLog.Item({
                symbol: symbol, 
                activity: ZKTLog.Activity.Burn, 
                addr1: zktAddr,
                addr2: sink,
                amount: unitAmount,
                timestamp: block.timestamp 
            });
            getLogChain(y).push(item);
        }
        totalTransactions += 1;
    }


    function transfer(string calldata symbol, bytes32[2][] memory C_tuples, bytes32[2] memory D_tuple, 
                      bytes32[2][] calldata y_tuples, bytes32[2] memory u_tuple, 
                      bytes calldata proof) external payable {
        for (uint i = 0; i < y_tuples.length; i++)
            require(registered(y_tuples[i]), "Account not yet registered.");
        
        address zktAddr = getZKT(symbol);
        {
            ZKTBase(zktAddr).transfer{value: msg.value}(C_tuples, D_tuple, y_tuples, u_tuple, proof);
        }
        {
            for (uint i = 0; i < y_tuples.length; i++) {
                ZKTLog.Item memory item = ZKTLog.Item({
                    symbol: symbol, 
                    activity: ZKTLog.Activity.Transfer, 
                    addr1: zktAddr,
                    addr2: msg.sender,
                    amount: 0,
                    timestamp: block.timestamp 
                });
                getLogChain(y_tuples[i]).push(item);
            }
        }

        totalTransactions += 1;
    }

    function getLogChain(bytes32[2] calldata y) internal view returns (ZKTLog.Chain storage chain) {
        bytes32 yHash = keccak256(abi.encode(y));
        return logChain[yHash]; 
    }

    function recentLog(bytes32[2] calldata y, uint n) external view returns (ZKTLog.Item[] memory items) {
        return getLogChain(y).top(n);
    }

}


