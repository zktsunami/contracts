// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Utils.sol";
import "./ZKTBase.sol";


contract ZKTERC20 is ZKTBase {


    constructor (address _token, address _transfer, address _burn) ZKTBase(_transfer, _burn) {
        bank.token = IERC20(_token);
    }

    function setERC20Token(address _token) public onlyAdmin {
        bank.token = IERC20(_token);

        emit SetERC20TokenSuccess(_token);
    }

    function fund(bytes32[2] calldata y, uint256 unitAmount, bytes calldata encGuess) override external payable {
        ZKTBase.fundBase(y, unitAmount, encGuess);

        uint256 nativeAmount = toNativeAmount(unitAmount);

        require(
            bank.token.transferFrom(tx.origin, address(this), nativeAmount),
            "fund: transferFrom error"
        );

        emit FundSuccess(y, unitAmount);
    }

    function burn(bytes32[2] memory y, uint256 unitAmount, bytes32[2] memory u, bytes memory proof, bytes memory encGuess) override external {
        uint256 nativeAmount = toNativeAmount(unitAmount);
        uint256 fee = nativeAmount * bank.BURN_FEE_MULTIPLIER / bank.BURN_FEE_DIVIDEND; 

        // Burn tokens and check validity of proof
        ZKTBase.burnBase(y, unitAmount, u, proof, encGuess);

        // Charge burn fee
        if (fee > 0) {
            require(bank.token.transfer(bank.agency, fee), "Failed to charge burn fee");
            bank.totalBurnFee += fee;
        }

        // Transfer remaining tokens to sender
        uint256 transferAmount = nativeAmount - fee;
        require(bank.token.transfer(tx.origin, transferAmount), "Failed to transfer tokens to sender");

        emit BurnSuccess(y, unitAmount);
    }


    function burnTo(address sink, bytes32[2] memory y, uint256 unitAmount, bytes32[2] memory u, bytes memory proof, bytes memory encGuess) override external {
        // Convert unit amount to native token amount
        uint256 nativeAmount = toNativeAmount(unitAmount);

        // Calculate fee based on burn fee multiplier and dividend
        uint256 fee = nativeAmount * bank.BURN_FEE_MULTIPLIER / bank.BURN_FEE_DIVIDEND; 

        // Call base burn function
        ZKTBase.burnBase(y, unitAmount, u, proof, encGuess);

        // Charge burn fee if greater than 0
        if (fee > 0) {
            require(bank.token.transfer(bank.agency, fee), "Failed to charge burn fee");
            bank.totalBurnFee += fee;
        }

        // Transfer tokens to sink address
        require(bank.token.transfer(sink, nativeAmount - fee), "Failed to transfer tokens from sender.");

        // Emit burn success event
        emit BurnSuccess(y, unitAmount);
    }

}


