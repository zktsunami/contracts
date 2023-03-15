// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./ZKTETH.sol";
import "./ZKTERC20.sol";

contract ZKTNativeFactory {

    string symbol;
    address transfer;
    address burn;

    constructor(string memory _symbol, address _transfer, address _burn) {
        symbol = _symbol;
        transfer = _transfer;
        burn = _burn;
    }

    function nativeSymbol () public view returns (string memory) {
        return symbol;
    }

    function newZKTNative (address admin) public returns (address) {
        ZKTETH zktETH = new ZKTETH(transfer, burn);
        zktETH.setAdmin(admin);
        return address(zktETH);
    }

}

contract ZKTERC20Factory {
    address transfer;
    address burn;

    constructor(address _transfer, address _burn) {
        transfer = _transfer;
        burn = _burn;
    }

    function newZKTERC20 (address admin, address _token) public returns (address) {
        ZKTERC20 zktERC20 = new ZKTERC20(_token, transfer, burn);
        zktERC20.setAdmin(admin);
        return address(zktERC20);
    }

}
