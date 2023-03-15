// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./Utils.sol";
import "./TransferVerifier.sol";
import "./BurnVerifier.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


library ZKTLog {

    enum Activity {
        Fund,
        Burn,
        Transfer
    }

    struct Item {
        string symbol;
        Activity activity;
        address addr1;
        address addr2;
        uint amount; 
        uint timestamp;
    }

    uint constant CHAIN_MAX_LENGTH = 100;
    struct Chain {
        Item[CHAIN_MAX_LENGTH] _logs;
        uint _head;
        uint _length;
    }

    function push (Chain storage chain, string calldata symbol, Activity activity, address addr1, address addr2, uint amount, uint timestamp) internal {
        push(chain,  
             ZKTLog.Item({
                symbol: symbol, 
                activity: activity, 
                addr1: addr1,
                addr2: addr2,
                amount: amount,
                timestamp: timestamp 
            })
        );
    }

    function push (Chain storage chain, Item memory item) internal {
        uint idx = (chain._head + chain._length) % CHAIN_MAX_LENGTH;
        chain._logs[idx] = item;
        if (chain._length < CHAIN_MAX_LENGTH) {
            chain._length += 1;
        }
        else {
            chain._head = (chain._head + 1) % CHAIN_MAX_LENGTH;
        }
    }

    function pop (Chain storage chain) internal returns(Item memory front) {
        require(chain._length > 0, "Empty chain");
        front = chain._logs[chain._head];
        chain._head = (chain._head + 1) % CHAIN_MAX_LENGTH;
        chain._length -= 1;
    }

    function top(Chain storage chain, uint n) internal view returns (Item[] memory items) {
        if (n > chain._length)
            n = chain._length;
        items = new Item[](n); 
        for (uint i = 1; i <= n; i++)
            items[i-1] = chain._logs[(chain._head + chain._length - i) % CHAIN_MAX_LENGTH];
    }


}
