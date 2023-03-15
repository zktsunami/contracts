// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./Utils.sol";
import "./TransferVerifier.sol";
import "./BurnVerifier.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ZKT library containing the ZKTBank struct
library ZKT {

    // ZKTBank struct for managing the zkToken bank state
    struct ZKTBank {
        address admin; // Administrator address
        address payable agency; // Agency address for fee collection
        IERC20 token; // The ERC20 token used in the bank
        TransferVerifier transferverifier; // Transfer verifier contract
        BurnVerifier burnverifier; // Burn verifier contract

        // Main account mapping (ECPoint)
        mapping(bytes32 => Utils.ECPoint[2]) acc;
        // Storage for pending transfers (ECPoint)
        mapping(bytes32 => Utils.ECPoint[2]) pending;
        // Symmetric ciphertext for client decryption
        mapping(bytes32 => bytes) guess;
        mapping(bytes32 => uint256) lastRollOver;

        // Nonce set (array of bytes32)
        bytes32[] nonceSet;

        uint256 lastGlobalUpdate; // Timestamp of the last global update
        uint256 unit; // Number of tokens in one unit
        uint256 MAX; // Maximum units that can be handled by zkToken

        uint256 epochLength; // Length of an epoch
        uint256 epochBase; // Epoch base (0 for block, 1 for second)

        // Burn fee settings
        uint256 BURN_FEE_MULTIPLIER;
        uint256 BURN_FEE_DIVIDEND;

        // Transfer fee settings
        uint256 TRANSFER_FEE_MULTIPLIER;
        uint256 TRANSFER_FEE_DIVIDEND;

        // Bank statistics
        uint256 totalBalance;
        uint256 totalUsers;
        uint256 totalBurnFee;
        uint256 totalTransferFee;
        uint256 totalDeposits;
        uint256 totalFundCount;

        int256 newEpoch; // Indicates a new epoch (-1 by default)
    }

}
