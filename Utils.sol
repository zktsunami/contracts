// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

// Utils is a library that provides various utility functions for mathematical operations
library Utils {
    uint256 constant GROUP_ORDER = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    uint256 constant FIELD_ORDER = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47;

    // Group addition
    function gAdd(uint256 x, uint256 y) internal pure returns (uint256) {
        return addmod(x, y, GROUP_ORDER);
    }

    // Group multiplication
    function gMul(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulmod(x, y, GROUP_ORDER);
    }

    // Group inverse
    function gInv(uint256 x) internal view returns (uint256) {
        return gExp(x, GROUP_ORDER - 2);
    }

    // Group modulo
    function gMod(uint256 x) internal pure returns (uint256) {
        return x % GROUP_ORDER;
    }

    // Group subtraction
    function gSub(uint256 x, uint256 y) internal pure returns (uint256) {
        return x >= y ? x - y : GROUP_ORDER - y + x;
    }

    // Group negation
    function gNeg(uint256 x) internal pure returns (uint256) {
        return GROUP_ORDER - x;
    }

    // Group exponentiation
    function gExp(uint256 base, uint256 exponent) internal view returns (uint256 output) {
        uint256 order = GROUP_ORDER;
        assembly {
            let m := mload(0x40)
            mstore(m, 0x20)
            mstore(add(m, 0x20), 0x20)
            mstore(add(m, 0x40), 0x20)
            mstore(add(m, 0x60), base)
            mstore(add(m, 0x80), exponent)
            mstore(add(m, 0xa0), order)
            if iszero(staticcall(gas(), 0x05, m, 0xc0, m, 0x20)) {
                revert(0, 0)
            }
            output := mload(m)
        }
    }

    // Field exponentiation
    function fieldExp(uint256 base, uint256 exponent) internal view returns (uint256 output) {
        uint256 order = FIELD_ORDER;
        assembly {
            let m := mload(0x40)
            mstore(m, 0x20)
            mstore(add(m, 0x20), 0x20)
            mstore(add(m, 0x40), 0x20)
            mstore(add(m, 0x60), base)
            mstore(add(m, 0x80), exponent)
            mstore(add(m, 0xa0), order)
            if iszero(staticcall(gas(), 0x05, m, 0xc0, m, 0x20)) {
                revert(0, 0)
            }
            output := mload(m)
        }
    }

    struct ECPoint {
        bytes32 x;
        bytes32 y;
    }

    function pointToTuple(ECPoint memory point) internal pure returns (bytes32[2] memory tuple) {
        tuple[0] = point.x;
        tuple[1] = point.y;
    }

    function tupleToPoint(bytes32[2] memory tuple) internal pure returns (ECPoint memory point) {
        point.x = tuple[0];
        point.y = tuple[1];
    }

    // Addition of two points on the elliptic curve; may revert if gas is insufficient
    function pointAdd(ECPoint memory point1, ECPoint memory point2) internal view returns (ECPoint memory result) {
        assembly {
            let m := mload(0x40)
            mstore(m, mload(point1))
            mstore(add(m, 0x20), mload(add(point1, 0x20)))
            mstore(add(m, 0x40), mload(point2))
            mstore(add(m, 0x60), mload(add(point2, 0x20)))
            // Address of the EC ADD instruction: 0x06
            // Reference: https://eips.ethereum.org/EIPS/eip-196#implementation
            if iszero(staticcall(gas(), 0x06, m, 0x80, result, 0x40)) {
                revert(0, 0)
            }
        }
    }

    // Scalar multiplication of a point on the elliptic curve; may revert if gas is insufficient
    function pointMul(ECPoint memory point, uint256 scalar) internal view returns (ECPoint memory result) {
        assembly {
            let m := mload(0x40)
            mstore(m, mload(point))
            mstore(add(m, 0x20), mload(add(point, 0x20)))
            mstore(add(m, 0x40), scalar)
            // Address of the EC MUL instruction: 0x07
            // Reference: https://eips.ethereum.org/EIPS/eip-196#implementation
            if iszero(staticcall(gas(), 0x07, m, 0x60, result, 0x40)) {
                revert(0, 0)
            }
        }
    }

    function pointNeg(ECPoint memory point) internal pure returns (ECPoint memory) {
        return ECPoint(point.x, bytes32(FIELD_ORDER - uint256(point.y)));
    }

    function pointEqual(ECPoint memory point1, ECPoint memory point2) internal pure returns (bool) {
        return point1.x == point2.x && point1.y == point2.y;
    }

    function generator() internal pure returns (ECPoint memory) {
        return ECPoint(0x077da99d806abd13c9f15ece5398525119d11e11e9836b2ee7d23f6159ad87d4, 0x01485efa927f2ad41bff567eec88f32fb0a0f706588b4e41a8d587d008b7f875);
    }

    function cofactor() internal pure returns (ECPoint memory) {
        return ECPoint(0x01b7de3dcf359928dd19f643d54dc487478b68a5b2634f9f1903c9fb78331aef, 0x2bda7d3ae6a557c716477c108be0d0f94abc6c4dc6b1bd93caccbcceaaa71d6b);
    }
    
    function mapToCurve(uint256 seed) internal view returns (ECPoint memory) {
        uint256 yCoord;
        while (true) {
            uint256 ySquared = fieldExp(seed, 3) + 3;
            yCoord = fieldExp(ySquared, (FIELD_ORDER + 1) / 4);
            if (fieldExp(yCoord, 2) == ySquared) {
                break;
            }
            seed += 1;
        }
        return ECPoint(bytes32(seed), bytes32(yCoord));
    }

    function mapToCurve(string memory input) internal view returns (ECPoint memory) {
        return mapToCurve(uint256(keccak256(abi.encodePacked(input))) % FIELD_ORDER);
    }

    function mapToCurve(string memory input, uint256 index) internal view returns (ECPoint memory) {
        return mapToCurve(uint256(keccak256(abi.encodePacked(input, index))) % FIELD_ORDER);
    }

    function extractSlice(bytes memory input, uint256 startPosition) internal pure returns (bytes32 result) {
        assembly {
            let m := mload(0x40)
            mstore(m, mload(add(add(input, 0x20), startPosition)))
            result := mload(m)
        }
    }

    function uintToString(uint value) internal pure returns (string memory stringValue) {
        if (value == 0) {
            return "0";
        }
        uint tempValue = value;
        uint length = 0;
        while (tempValue != 0) {
            length++;
            tempValue /= 10;
        }
        bytes memory strBytes = new bytes(length);
        uint k = length;
        while (value != 0) {
            strBytes[--k] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(strBytes);
    }

    function bytesToHexString(bytes32 inputBytes) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory hexString = new bytes(inputBytes.length * 2 + 2);
        hexString[0] = '0';
        hexString[1] = 'x';
        for (uint i = 0; i < inputBytes.length; i++) {
            hexString[2 * i + 2] = hexChars[uint8((inputBytes[i] >> 4) & bytes1(0x0f))];
            hexString[2 * i + 3] = hexChars[uint8(inputBytes[i] & bytes1(0x0f))];
        }
        return string(hexString);
    }

}

