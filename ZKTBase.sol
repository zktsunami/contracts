// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./ZKTBank.sol";
import "./Utils.sol";
import "./TransferVerifier.sol";
import "./BurnVerifier.sol";

// ZKTBase is the base contract for ZKT operations
abstract contract ZKTBase {

    using Utils for uint256;
    using Utils for Utils.ECPoint;

    ZKT.ZKTBank bank;

    event RegisterSuccess(bytes32[2] y_tuple);
    event FundSuccess(bytes32[2] y, uint256 unitAmount);
    event BurnSuccess(bytes32[2] y, uint256 unitAmount);
    event TransferSuccess(bytes32[2][] parties);
    event SetBurnFeeStrategySuccess(uint256 multiplier, uint256 dividend);
    event SetTransferFeeStrategySuccess(uint256 multiplier, uint256 dividend);
    event SetEpochBaseSuccess(uint256 epochBase);
    event SetEpochLengthSuccess(uint256 epochLength);
    event SetUnitSuccess(uint256 unit);
    event SetAgencySuccess(address agency);
    event SetAdminSuccess(address admin);
    event SetERC20TokenSuccess(address token);

    constructor (address _transfer, address _burn) {
        bank.admin = payable(msg.sender);
        bank.agency = payable(msg.sender);
        bank.transferverifier = TransferVerifier(_transfer);
        bank.burnverifier = BurnVerifier(_burn);
        
        bank.unit = 10**16;
        bank.MAX = 2**32 - 1;
        bank.lastGlobalUpdate = 0;
        bank.epochBase = 0;
        bank.epochLength = 24;
        
        bank.BURN_FEE_MULTIPLIER = 1;
        bank.BURN_FEE_DIVIDEND = 100;
        bank.TRANSFER_FEE_MULTIPLIER = 1;
        bank.TRANSFER_FEE_DIVIDEND = 5;

        bank.totalBalance = 0;
        bank.totalUsers = 0;
        bank.totalBurnFee = 0;
        bank.totalTransferFee = 0;
        bank.totalDeposits = 0;
        bank.totalFundCount = 0;

        bank.newEpoch = -1;
    }

    /**
     * @dev Throws if called by any account other than the admin.
     */
    modifier onlyAdmin() {
        require(admin() == msg.sender, "Caller is not the admin");
        _;
    }

    function toUnitAmount(uint256 nativeAmount) internal view returns (uint256) {
        require(nativeAmount % bank.unit == 0, "error: invalid nativeAmount.");
        uint256 amount = nativeAmount / bank.unit;
        require(0 <= amount && amount <= bank.MAX, "toUnitAmount: out of range."); 
        return amount;
    }

    function toNativeAmount(uint256 unitAmount) internal view returns (uint256) {
        require(0 <= unitAmount && unitAmount <= bank.MAX, "toNativeAmount: out of range");
        return unitAmount * bank.unit;
    }

    function admin() public view returns(address) {
        return bank.admin;
    }

    function agency() public view returns (address) {
        return bank.agency;
    }

    function token() external view returns (address) {
        return address(bank.token);
    }

    function epochBase() external view returns (uint256) {
        return bank.epochBase;
    }

    function epochLength() external view returns (uint256) {
        return bank.epochLength;
    }

    function unit() external view returns (uint256) {
        return bank.unit;
    }

    function burn_fee_multiplier() external view returns (uint256) {
      return bank.BURN_FEE_MULTIPLIER;
    }

    function burn_fee_dividend() external view returns (uint256) {
      return bank.BURN_FEE_DIVIDEND;
    }

    function lastGlobalUpdate() external view returns (uint256) {
        return bank.lastGlobalUpdate;
    }

    function lastRollOver(bytes32 yHash) external view returns (uint256) {
        return bank.lastRollOver[yHash];
    }

    function totalBalance() external view returns (uint256) {
        return bank.totalBalance;
    }

    function totalUsers() external view returns (uint256) {
        return bank.totalUsers;
    }

    function totalBurnFee() external view returns (uint256) {
        return bank.totalBurnFee;
    }

    function totalTransferFee() external view returns (uint256) {
        return bank.totalTransferFee;
    }

    function totalDeposits() external view returns (uint256) {
        return bank.totalDeposits;
    }

    function totalFundCount() external view returns (uint256) {
        return bank.totalFundCount;
    }

    function setBurnFeeStrategy(uint256 multiplier, uint256 dividend) external onlyAdmin {
        bank.BURN_FEE_MULTIPLIER = multiplier;
        bank.BURN_FEE_DIVIDEND = dividend;

        emit SetBurnFeeStrategySuccess(multiplier, dividend);
    }

    function setTransferFeeStrategy(uint256 multiplier, uint256 dividend) external onlyAdmin {
        bank.TRANSFER_FEE_MULTIPLIER = multiplier;
        bank.TRANSFER_FEE_DIVIDEND = dividend;

        emit SetTransferFeeStrategySuccess(multiplier, dividend);
    }

    function setEpochBase (uint256 _epochBase) external onlyAdmin {
        bank.epochBase = _epochBase;
        bank.newEpoch = int256(currentEpoch());

        emit SetEpochBaseSuccess(_epochBase);
    }

    function setEpochLength (uint256 _epochLength) external onlyAdmin {
        bank.epochLength = _epochLength;
        bank.newEpoch = int256(currentEpoch());

        emit SetEpochLengthSuccess(_epochLength);
    }

    function setUnit (uint256 _unit) external onlyAdmin{
        bank.unit = _unit;

        emit SetUnitSuccess(_unit);
    }

    function setAgency (address payable _agency) external onlyAdmin {
        bank.agency = _agency;

        emit SetAgencySuccess(_agency);
    }

    function setAdmin (address _admin) external onlyAdmin {
        bank.admin = _admin;
        emit SetAdminSuccess(_admin);
    }

    function getBalance(bytes32[2][] calldata y_tuples, uint256 epoch) external view returns (bytes32[2][2][] memory accounts) {
        uint256 size = y_tuples.length;
        accounts = new bytes32[2][2][](size);
        for (uint256 i = 0; i < size; i++) {
            bytes32 yHash = keccak256(abi.encode(y_tuples[i]));
            Utils.ECPoint[2] memory account = bank.acc[yHash];
            if (bank.lastRollOver[yHash] < epoch || bank.newEpoch >= 0) {
                Utils.ECPoint[2] memory scratch = bank.pending[yHash];
                account[0] = account[0].pAdd(scratch[0]);
                account[1] = account[1].pAdd(scratch[1]);
            }
            accounts[i] = [[account[0].x, account[0].y], [account[1].x, account[1].y]];
        }
    }

    function getAccountState (bytes32[2] calldata y) external view returns (bytes32[2][2] memory y_available, bytes32[2][2] memory y_pending) {
        bytes32 yHash = keccak256(abi.encode(y));
        Utils.ECPoint[2] memory tmp = bank.acc[yHash];
        y_available = [[tmp[0].x, tmp[0].y], [tmp[1].x, tmp[1].y]];
        tmp = bank.pending[yHash];
        y_pending = [[tmp[0].x, tmp[0].y], [tmp[1].x, tmp[1].y]]; 
    }

    function getGuess (bytes32[2] memory y) public view returns (bytes memory y_guess) {
        bytes32 yHash = keccak256(abi.encode(y));
        y_guess = bank.guess[yHash];
        return y_guess;
    }

    function currentTimestamp() public view returns (uint256) {
        return block.timestamp;
    }

    function currentEpoch() public view returns (uint256) {
        uint256 e = 0;
        if (bank.epochBase == 0)
            e = block.number / bank.epochLength;
        else if (bank.epochBase == 1)
            e = block.timestamp / bank.epochLength;
        else
            revert("currentEpoch: invalid base.");
        return e;
    }

    function rollOver(bytes32 yHash) internal {
        uint256 e = currentEpoch();

        if (bank.lastRollOver[yHash] < e || bank.newEpoch >= 0) {
            Utils.ECPoint[2][2] memory scratch = [bank.acc[yHash], bank.pending[yHash]];
            bank.acc[yHash][0] = scratch[0][0].pAdd(scratch[1][0]);
            bank.acc[yHash][1] = scratch[0][1].pAdd(scratch[1][1]);
            delete bank.pending[yHash]; 
            bank.lastRollOver[yHash] = e;
        }
        if (bank.lastGlobalUpdate < e || bank.newEpoch >= 0) {
            bank.lastGlobalUpdate = e;
            delete bank.nonceSet;
        }
        bank.newEpoch = -1;
    }

    function fundBase(bytes32[2] calldata y, uint256 amount, bytes calldata encGuess) internal {
        require(amount <= bank.MAX && bank.totalBalance + amount <= bank.MAX, "fund: greater than max.");
        bank.totalBalance += amount;
        bank.totalDeposits += amount;
        bank.totalFundCount += 1;

        bytes32 yHash = keccak256(abi.encode(y));
        rollOver(yHash);

        Utils.ECPoint memory scratch = bank.pending[yHash][0];
        scratch = scratch.pAdd(Utils.g().pMul(amount));
        bank.pending[yHash][0] = scratch;

        bank.guess[yHash] = encGuess;
    }

    function fund(bytes32[2] calldata y, uint256 unitAmount, bytes calldata encGuess) virtual external payable;

    function burn(bytes32[2] calldata y, uint256 unitAmount, bytes32[2] calldata u, bytes calldata proof, bytes calldata encGuess) virtual external; 

    function burnTo(address sink, bytes32[2] memory y, uint256 unitAmount, bytes32[2] memory u, bytes memory proof, bytes memory encGuess) virtual external;

    function burnBase(bytes32[2] memory y, uint256 amount, bytes32[2] memory u, bytes memory proof, bytes memory encGuess) internal {

        require(bank.totalBalance >= amount, "Burn fails the sanity check.");
        bank.totalBalance -= amount;
        
        Utils.ECPoint memory yPoint = Utils.toPoint(y);
        Utils.ECPoint memory uPoint = Utils.toPoint(u);

        bytes32 yHash = keccak256(abi.encode(y));
        //require(registered(yHash), "Account not yet registered.");
        rollOver(yHash);

        Utils.ECPoint[2] memory scratch = bank.pending[yHash];
        bank.pending[yHash][0] = scratch[0].pAdd(Utils.g().pMul(amount.gNeg()));

        scratch = bank.acc[yHash]; 
        scratch[0] = scratch[0].pAdd(Utils.g().pMul(amount.gNeg()));

        validateNonce(u);

        bank.guess[yHash] = encGuess;

        require(bank.burnverifier.verifyBurn(scratch[0], scratch[1], yPoint, bank.lastGlobalUpdate, uPoint, proof), "burn: verification failed!");
    }

    function transfer(bytes32[2][] memory C, bytes32[2] memory D, 
                      bytes32[2][] memory y, bytes32[2] memory u, 
                      bytes calldata proof) external payable {

        uint256 startGas = gasleft();
        
        validateNonce(u);
        
        TransferVerifier.TransferStatement memory statement;

        uint256 size = y.length;
        statement.CLn = new Utils.ECPoint[](size);
        statement.CRn = new Utils.ECPoint[](size);
        require(C.length == size, "transfer: length mismatch!");

        statement.C = new Utils.ECPoint[](size);
        statement.y = new Utils.ECPoint[](size);
        for (uint256 i = 0; i < size; i++) {
            statement.C[i] = Utils.toPoint(C[i]);
            statement.y[i] = Utils.toPoint(y[i]);
        }
        statement.D = Utils.toPoint(D);

        for (uint256 i = 0; i < size; i++) {
            bytes32 yHash = keccak256(abi.encode(y[i]));
            rollOver(yHash);

            Utils.ECPoint[2] memory scratch = bank.pending[yHash];

            bank.pending[yHash][0] = scratch[0].pAdd(statement.C[i]);
            bank.pending[yHash][1] = scratch[1].pAdd(statement.D);

            scratch = bank.acc[yHash];
            statement.CLn[i] = scratch[0].pAdd(statement.C[i]); 
            statement.CRn[i] = scratch[1].pAdd(statement.D);
        }


        statement.epoch = bank.lastGlobalUpdate;
        statement.u = Utils.toPoint(u);

        require(bank.transferverifier.verify(statement, proof),
            "Error: Transfer verification failed!");

        {
            uint256 usedGas = startGas - gasleft();
            
            uint256 fee = (usedGas * bank.TRANSFER_FEE_MULTIPLIER / bank.TRANSFER_FEE_DIVIDEND) * tx.gasprice;
            if (fee > 0) {
                require(msg.value >= fee, "Not enough for fees.");
                bank.agency.transfer(fee);
                bank.totalTransferFee = bank.totalTransferFee + fee;
            }
            payable(tx.origin).transfer(msg.value - fee);
        }

        emit TransferSuccess(y);
    }

    function validateNonce(bytes32[2] memory nonce) internal {
        bytes32 uHash = keccak256(abi.encode(nonce));
        for (uint256 i = 0; i < bank.nonceSet.length; i++) {
            require(bank.nonceSet[i] != uHash, "error: nonce has already been used!");
        }
        bank.nonceSet.push(uHash);
    }
}


