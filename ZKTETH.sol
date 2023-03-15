// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./Utils.sol";
import "./ZKTBase.sol";

contract ZKTETH is ZKTBase {

    // Constructor for the ZKTETH contract
    constructor(address _transfer, address _burn) ZKTBase(_transfer, _burn) {
    }

    // Fund function to deposit native tokens
    function fund(bytes32[2] calldata y, uint256 unitAmount, bytes calldata encGuess) override external payable {
        uint256 tokenAmount = toTokenAmount(msg.value);
        require(unitAmount == tokenAmount, "Incorrect paid amount.");

        // Call the fundBase function from ZKTBase
        ZKTBase.fundBase(y, unitAmount, encGuess);

        // Emit FundSuccess event
        emit FundSuccess(y, unitAmount);
    }

    // Burn function to withdraw native tokens
    function burn(bytes32[2] calldata y, uint256 unitAmount, bytes32[2] calldata u, bytes calldata proof, bytes calldata encGuess) override external {
        uint256 nativeAmount = toNativeAmount(unitAmount);
        uint256 fee = nativeAmount * bank.BURN_FEE_MULTIPLIER / bank.BURN_FEE_DIVIDEND; 

        // Call the burnBase function from ZKTBase
        ZKTBase.burnBase(y, unitAmount, u, proof, encGuess);

        // Charge fee if applicable
        if (fee > 0) {
            require(bank.token.transfer(bank.agency, fee), "Fee charging failed.");
            bank.totalBurnFee += fee;
        }

        // Transfer the remaining native tokens to the caller
        payable(tx.origin).transfer(nativeAmount - fee);

        // Emit the BurnSuccess event
        emit BurnSuccess(y, unitAmount);
    }

    // Burn function to withdraw native tokens to a specified address
    function burnTo(address sink, bytes32[2] calldata y, uint256 unitAmount, bytes32[2] calldata u, bytes calldata proof, bytes calldata encGuess) override external {
        uint256 nativeAmount = toNativeAmount(unitAmount);
        uint256 fee = nativeAmount * bank.BURN_FEE_MULTIPLIER / bank.BURN_FEE_DIVIDEND;

        // Call the burnBase function from ZKTBase
        ZKTBase.burnBase(y, unitAmount, u, proof, encGuess);

        // Charge fee if applicable
        if (fee > 0) {
            bank.agency.transfer(fee);
            bank.totalBurnFee += fee;
        }

        // Transfer the remaining native tokens to the specified address
        payable(sink).transfer(nativeAmount - fee);

        // Emit the BurnSuccess event
        emit BurnSuccess(y, unitAmount);
    }

}


