// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./Utils.sol";
import "./InnerProductVerifier.sol";

contract TransferVerifier {
    using Utils for uint256;
    using Utils for Utils.ECPoint;

    uint256 constant UNITY = 0x14a3074b02521e3b1ed9852e5028452693e87be4e910500c7ba9bbddb2f46edd; // primitive 2^28th root of unity modulo q.

    InnerProductVerifier ip;

    struct TransferStatement {
        Utils.ECPoint[] CLn;
        Utils.ECPoint[] CRn;
        Utils.ECPoint[] C;
        Utils.ECPoint D;
        Utils.ECPoint[] y;
        uint256 epoch;
        Utils.ECPoint u;
    }

    struct TransferProof {
        Utils.ECPoint BA;
        Utils.ECPoint BS;
        Utils.ECPoint A;
        Utils.ECPoint B;

        Utils.ECPoint[] CLnG;
        Utils.ECPoint[] CRnG;
        Utils.ECPoint[] C_0G;
        Utils.ECPoint[] DG;
        Utils.ECPoint[] y_0G;
        Utils.ECPoint[] gG;
        Utils.ECPoint[] C_XG;
        Utils.ECPoint[] y_XG;

        uint256[] f;
        uint256 z_A;
        uint256 z_C;
        uint256 z_E;

        Utils.ECPoint[2] tCommits;
        uint256 tHat;
        uint256 mu;

        uint256 c;
        uint256 s_sk;
        uint256 s_r;
        uint256 s_b;
        uint256 s_tau;

        InnerProductVerifier.InnerProductProof ipProof;
    }

    constructor (address _ip) {
        ip = InnerProductVerifier(_ip);
    }

    struct TransferAuxiliaries {
        uint256 y;
        uint256[64] ys;
        uint256 z;
        uint256[2] zs; 
        uint256[64] twoTimesZSquared;
        uint256 zSum;
        uint256 x;
        uint256 t;
        uint256 k;
        Utils.ECPoint tEval;
    }

    struct SigmaAuxiliaries {
        uint256 c;
        Utils.ECPoint A_y;
        Utils.ECPoint A_D;
        Utils.ECPoint A_b;
        Utils.ECPoint A_X;
        Utils.ECPoint A_t;
        Utils.ECPoint gEpoch;
        Utils.ECPoint A_u;
    }

    struct AnonAuxiliaries {
        uint256 m;
        uint256 N;
        uint256 v;
        uint256 w;
        uint256 vPow;
        uint256 wPow;
        uint256[2][] f; // could just allocate extra space in the proof?
        uint256[2][] r; // each poly is an array of length N. evaluations of prods
        Utils.ECPoint temp;
        Utils.ECPoint CLnR;
        Utils.ECPoint CRnR;
        Utils.ECPoint[2][] CR;
        Utils.ECPoint[2][] yR;
        Utils.ECPoint C_XR;
        Utils.ECPoint y_XR;
        Utils.ECPoint gR;
        Utils.ECPoint DR;
    }

    struct IPAuxiliaries {
        Utils.ECPoint P;
        Utils.ECPoint u_x;
        Utils.ECPoint[] hPrimes;
        Utils.ECPoint hPrimeSum;
        uint256 o;
    }

    function gSum() internal pure returns (Utils.ECPoint memory) {
        return Utils.ECPoint(0x00715f13ea08d6b51bedcde3599d8e12163e090921309d5aafc9b5bfaadbcda0, 0x27aceab598af7bf3d16ca9d40fe186c489382c21bb9d22b19cb3af8b751b959f);
    }

    function verify(TransferStatement memory statement, bytes calldata proof) external view returns (bool) {
        TransferProof memory zktProof = unserialize(proof);
        return verify(statement, zktProof);
    }

    function verify(TransferStatement memory statement, TransferProof memory proof) internal view returns (bool) {
        uint256 statementHash = uint256(keccak256(abi.encode(statement.CLn, statement.CRn, statement.C, statement.D, statement.y, statement.epoch))).gMod();

        AnonAuxiliaries memory anonAuxiliaries;
        anonAuxiliaries.v = uint256(keccak256(abi.encode(statementHash, proof.BA, proof.BS, proof.A, proof.B))).gMod();
        anonAuxiliaries.w = uint256(keccak256(abi.encode(anonAuxiliaries.v, proof.CLnG, proof.CRnG, proof.C_0G, proof.DG, proof.y_0G, proof.gG, proof.C_XG, proof.y_XG))).gMod();
        anonAuxiliaries.m = proof.f.length / 2;
        anonAuxiliaries.N = 2 ** anonAuxiliaries.m;
        anonAuxiliaries.f = new uint256[2][](2 * anonAuxiliaries.m);
        for (uint256 k = 0; k < 2 * anonAuxiliaries.m; k++) {
            anonAuxiliaries.f[k][1] = proof.f[k];
            anonAuxiliaries.f[k][0] = anonAuxiliaries.w.gSub(proof.f[k]);
        }

        for (uint256 k = 0; k < 2 * anonAuxiliaries.m; k++) {
            anonAuxiliaries.temp = anonAuxiliaries.temp.pAdd(ip.gs(k).pMul(anonAuxiliaries.f[k][1]));
            anonAuxiliaries.temp = anonAuxiliaries.temp.pAdd(ip.gs(k + 2 * anonAuxiliaries.m).pMul(anonAuxiliaries.f[k][1].gMul(anonAuxiliaries.w.gSub(anonAuxiliaries.f[k][1]))));
        }
        anonAuxiliaries.temp = anonAuxiliaries.temp.pAdd(ip.gs(4 * anonAuxiliaries.m).pMul(anonAuxiliaries.f[0][1].gMul(anonAuxiliaries.f[anonAuxiliaries.m][1])).pAdd(ip.gs(1 + 4 * anonAuxiliaries.m).pMul(anonAuxiliaries.f[0][0].gMul(anonAuxiliaries.f[anonAuxiliaries.m][0]))));
        require(proof.B.pMul(anonAuxiliaries.w).pAdd(proof.A).pEqual(anonAuxiliaries.temp.pAdd(Utils.h().pMul(proof.z_A))), "Recovery failure for B^w * A.");

        anonAuxiliaries.r = assemblePolynomials(anonAuxiliaries.f);

        anonAuxiliaries.CR = assembleConvolutions(anonAuxiliaries.r, statement.C);
        anonAuxiliaries.yR = assembleConvolutions(anonAuxiliaries.r, statement.y);
        for (uint256 i = 0; i < anonAuxiliaries.N; i++) {
            anonAuxiliaries.CLnR = anonAuxiliaries.CLnR.pAdd(statement.CLn[i].pMul(anonAuxiliaries.r[i][0]));
            anonAuxiliaries.CRnR = anonAuxiliaries.CRnR.pAdd(statement.CRn[i].pMul(anonAuxiliaries.r[i][0]));
        }
        anonAuxiliaries.vPow = 1;
        for (uint256 i = 0; i < anonAuxiliaries.N; i++) {
            anonAuxiliaries.C_XR = anonAuxiliaries.C_XR.pAdd(anonAuxiliaries.CR[i / 2][i % 2].pMul(anonAuxiliaries.vPow));
            anonAuxiliaries.y_XR = anonAuxiliaries.y_XR.pAdd(anonAuxiliaries.yR[i / 2][i % 2].pMul(anonAuxiliaries.vPow));
            if (i > 0) {
                anonAuxiliaries.vPow = anonAuxiliaries.vPow.gMul(anonAuxiliaries.v);
            }
        }
        anonAuxiliaries.wPow = 1;
        for (uint256 k = 0; k < anonAuxiliaries.m; k++) {
            anonAuxiliaries.CLnR = anonAuxiliaries.CLnR.pAdd(proof.CLnG[k].pMul(anonAuxiliaries.wPow.gNeg()));
            anonAuxiliaries.CRnR = anonAuxiliaries.CRnR.pAdd(proof.CRnG[k].pMul(anonAuxiliaries.wPow.gNeg()));
            anonAuxiliaries.CR[0][0] = anonAuxiliaries.CR[0][0].pAdd(proof.C_0G[k].pMul(anonAuxiliaries.wPow.gNeg()));
            anonAuxiliaries.DR = anonAuxiliaries.DR.pAdd(proof.DG[k].pMul(anonAuxiliaries.wPow.gNeg()));
            anonAuxiliaries.yR[0][0] = anonAuxiliaries.yR[0][0].pAdd(proof.y_0G[k].pMul(anonAuxiliaries.wPow.gNeg()));
            anonAuxiliaries.gR = anonAuxiliaries.gR.pAdd(proof.gG[k].pMul(anonAuxiliaries.wPow.gNeg()));
            anonAuxiliaries.C_XR = anonAuxiliaries.C_XR.pAdd(proof.C_XG[k].pMul(anonAuxiliaries.wPow.gNeg()));
            anonAuxiliaries.y_XR = anonAuxiliaries.y_XR.pAdd(proof.y_XG[k].pMul(anonAuxiliaries.wPow.gNeg()));

            anonAuxiliaries.wPow = anonAuxiliaries.wPow.gMul(anonAuxiliaries.w);
        }
        anonAuxiliaries.DR = anonAuxiliaries.DR.pAdd(statement.D.pMul(anonAuxiliaries.wPow));
        anonAuxiliaries.gR = anonAuxiliaries.gR.pAdd(Utils.g().pMul(anonAuxiliaries.wPow));

        TransferAuxiliaries memory zetherAuxiliaries;
        zetherAuxiliaries.y = uint256(keccak256(abi.encode(anonAuxiliaries.w))).gMod();
        zetherAuxiliaries.ys[0] = 1;
        zetherAuxiliaries.k = 1;
        for (uint256 i = 1; i < 64; i++) {
            zetherAuxiliaries.ys[i] = zetherAuxiliaries.ys[i - 1].gMul(zetherAuxiliaries.y);
            zetherAuxiliaries.k = zetherAuxiliaries.k.gAdd(zetherAuxiliaries.ys[i]);
        }
        zetherAuxiliaries.z = uint256(keccak256(abi.encode(zetherAuxiliaries.y))).gMod();
        zetherAuxiliaries.zs = [zetherAuxiliaries.z.gExp(2), zetherAuxiliaries.z.gExp(3)];        
        zetherAuxiliaries.zSum = zetherAuxiliaries.zs[0].gAdd(zetherAuxiliaries.zs[1]).gMul(zetherAuxiliaries.z);
        zetherAuxiliaries.k = zetherAuxiliaries.k.gMul(zetherAuxiliaries.z.gSub(zetherAuxiliaries.zs[0])).gSub(zetherAuxiliaries.zSum.gMul(2 ** 32).gSub(zetherAuxiliaries.zSum));
        zetherAuxiliaries.t = proof.tHat.gSub(zetherAuxiliaries.k); // t = tHat - delta(y, z)
        for (uint256 i = 0; i < 32; i++) {
            zetherAuxiliaries.twoTimesZSquared[i] = zetherAuxiliaries.zs[0].gMul(2 ** i);
            zetherAuxiliaries.twoTimesZSquared[i + 32] = zetherAuxiliaries.zs[1].gMul(2 ** i);
        }

        zetherAuxiliaries.x = uint256(keccak256(abi.encode(zetherAuxiliaries.z, proof.tCommits))).gMod();
        zetherAuxiliaries.tEval = proof.tCommits[0].pMul(zetherAuxiliaries.x).pAdd(proof.tCommits[1].pMul(zetherAuxiliaries.x.gMul(zetherAuxiliaries.x))); // replace with "commit"?

        SigmaAuxiliaries memory sigmaAuxiliaries;
        sigmaAuxiliaries.A_y = anonAuxiliaries.gR.pMul(proof.s_sk).pAdd(anonAuxiliaries.yR[0][0].pMul(proof.c.gNeg()));
        sigmaAuxiliaries.A_D = Utils.g().pMul(proof.s_r).pAdd(statement.D.pMul(proof.c.gNeg())); // add(mul(anonAuxiliaries.gR, proof.s_r), mul(anonAuxiliaries.DR, proof.c.neg()));
        sigmaAuxiliaries.A_b = Utils.g().pMul(proof.s_b).pAdd(anonAuxiliaries.DR.pMul(zetherAuxiliaries.zs[0].gNeg()).pAdd(anonAuxiliaries.CRnR.pMul(zetherAuxiliaries.zs[1])).pMul(proof.s_sk).pAdd(anonAuxiliaries.CR[0][0].pMul(zetherAuxiliaries.zs[0].gNeg()).pAdd(anonAuxiliaries.CLnR.pMul(zetherAuxiliaries.zs[1])).pMul(proof.c.gNeg())));
        sigmaAuxiliaries.A_X = anonAuxiliaries.y_XR.pMul(proof.s_r).pAdd(anonAuxiliaries.C_XR.pMul(proof.c.gNeg()));
        sigmaAuxiliaries.A_t = Utils.g().pMul(zetherAuxiliaries.t).pAdd(zetherAuxiliaries.tEval.pNeg()).pMul(proof.c.gMul(anonAuxiliaries.wPow)).pAdd(Utils.h().pMul(proof.s_tau)).pAdd(Utils.g().pMul(proof.s_b.gNeg()));
        sigmaAuxiliaries.gEpoch = Utils.mapInto("ZKT", statement.epoch);
        sigmaAuxiliaries.A_u = sigmaAuxiliaries.gEpoch.pMul(proof.s_sk).pAdd(statement.u.pMul(proof.c.gNeg()));

        sigmaAuxiliaries.c = uint256(keccak256(abi.encode(zetherAuxiliaries.x, sigmaAuxiliaries.A_y, sigmaAuxiliaries.A_D, sigmaAuxiliaries.A_b, sigmaAuxiliaries.A_X, sigmaAuxiliaries.A_t, sigmaAuxiliaries.A_u))).gMod();
        require(sigmaAuxiliaries.c == proof.c, string(abi.encodePacked("Sigma failed. Epoch: ", Utils.uint2str(statement.epoch))));

        IPAuxiliaries memory ipAuxiliaries;
        ipAuxiliaries.o = uint256(keccak256(abi.encode(sigmaAuxiliaries.c))).gMod();
        ipAuxiliaries.u_x = Utils.g().pMul(ipAuxiliaries.o);
        ipAuxiliaries.hPrimes = new Utils.ECPoint[](64);
        for (uint256 i = 0; i < 64; i++) {
            ipAuxiliaries.hPrimes[i] = ip.hs(i).pMul(zetherAuxiliaries.ys[i].gInv());
            ipAuxiliaries.hPrimeSum = ipAuxiliaries.hPrimeSum.pAdd(ipAuxiliaries.hPrimes[i].pMul(zetherAuxiliaries.ys[i].gMul(zetherAuxiliaries.z).gAdd(zetherAuxiliaries.twoTimesZSquared[i])));
        }
        ipAuxiliaries.P = proof.BA.pAdd(proof.BS.pMul(zetherAuxiliaries.x)).pAdd(gSum().pMul(zetherAuxiliaries.z.gNeg())).pAdd(ipAuxiliaries.hPrimeSum);
        ipAuxiliaries.P = ipAuxiliaries.P.pAdd(Utils.h().pMul(proof.mu.gNeg()));
        ipAuxiliaries.P = ipAuxiliaries.P.pAdd(ipAuxiliaries.u_x.pMul(proof.tHat));
        require(ip.verifyInnerProduct(ipAuxiliaries.hPrimes, ipAuxiliaries.u_x, ipAuxiliaries.P, proof.ipProof, ipAuxiliaries.o), "IP failed.");

        return true;
    }

    function assemblePolynomials(uint256[2][] memory f) internal view returns (uint256[2][] memory result) {
        uint256 m = f.length / 2;
        uint256 N = 2 ** m;
        result = new uint256[2][](N);
        for (uint256 i = 0; i < 2; i++) {
            uint256[] memory half = recursivePolynomials(i * m, (i + 1) * m, 1, f);
            for (uint256 j = 0; j < N; j++) {
                result[j][i] = half[j];
            }
        }
    }

    function recursivePolynomials(uint256 baseline, uint256 current, uint256 accum, uint256[2][] memory f) internal view returns (uint256[] memory result) {
        // have to do a bunch of re-allocating because solidity won't let me have something which is internal and also modifies (internal) state. (?)
        uint256 size = 2 ** (current - baseline); // size is at least 2...
        result = new uint256[](size);

        if (current == baseline) {
            result[0] = accum;
            return result;
        }
        current = current - 1;

        uint256[] memory left = recursivePolynomials(baseline, current, accum.gMul(f[current][0]), f);
        uint256[] memory right = recursivePolynomials(baseline, current, accum.gMul(f[current][1]), f);
        for (uint256 i = 0; i < size / 2; i++) {
            result[i] = left[i];
            result[i + size / 2] = right[i];
        }
    }

    function assembleConvolutions(uint256[2][] memory exponent, Utils.ECPoint[] memory base) internal view returns (Utils.ECPoint[2][] memory result) {
        uint256 size = exponent.length;
        uint256 half = size / 2;
        result = new Utils.ECPoint[2][](half);

        Utils.ECPoint[] memory base_fft = fft(base, false);

        uint256[] memory exponent_fft = new uint256[](size);
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < size; j++) {
                exponent_fft[j] = exponent[(size - j) % size][i]; 
            }

            exponent_fft = fft(exponent_fft);
            Utils.ECPoint[] memory inverse_fft = new Utils.ECPoint[](half);
            uint256 compensation = 2;
            compensation = compensation.gInv();
            for (uint256 j = 0; j < half; j++) { // Hadamard
                inverse_fft[j] = base_fft[j].pMul(exponent_fft[j]).pAdd(base_fft[j + half].pMul(exponent_fft[j + half])).pMul(compensation);
            }

            inverse_fft = fft(inverse_fft, true);
            for (uint256 j = 0; j < half; j++) {
                result[j][i] = inverse_fft[j];
            }
        }
    }

    function fft(Utils.ECPoint[] memory input, bool inverse) internal view returns (Utils.ECPoint[] memory result) {
        uint256 size = input.length;
        if (size == 1) {
            return input;
        }
        require(size % 2 == 0, "Input size is not a power of 2!");

        uint256 omega = UNITY.gExp(2**28 / size);
        uint256 compensation = 1;
        if (inverse) {
            omega = omega.gInv();
            compensation = 2;
        }
        compensation = compensation.gInv();
        Utils.ECPoint[] memory even = fft(extract(input, 0), inverse);
        Utils.ECPoint[] memory odd = fft(extract(input, 1), inverse);
        uint256 omega_run = 1;
        result = new Utils.ECPoint[](size);
        for (uint256 i = 0; i < size / 2; i++) {
            Utils.ECPoint memory temp = odd[i].pMul(omega_run);
            result[i] = even[i].pAdd(temp).pMul(compensation);
            result[i + size / 2] = even[i].pAdd(temp.pNeg()).pMul(compensation);
            omega_run = omega_run.gMul(omega);
        }
    }

    function extract(Utils.ECPoint[] memory input, uint256 parity) internal pure returns (Utils.ECPoint[] memory result) {
        result = new Utils.ECPoint[](input.length / 2);
        for (uint256 i = 0; i < input.length / 2; i++) {
            result[i] = input[2 * i + parity];
        }
    }

    function fft(uint256[] memory input) internal view returns (uint256[] memory result) {
        uint256 size = input.length;
        if (size == 1) {
            return input;
        }
        require(size % 2 == 0, "Input size is not a power of 2!");

        uint256 omega = UNITY.gExp(2**28 / size);
        uint256[] memory even = fft(extract(input, 0));
        uint256[] memory odd = fft(extract(input, 1));
        uint256 omega_run = 1;
        result = new uint256[](size);
        for (uint256 i = 0; i < size / 2; i++) {
            uint256 temp = odd[i].gMul(omega_run);
            result[i] = even[i].gAdd(temp);
            result[i + size / 2] = even[i].gSub(temp);
            omega_run = omega_run.gMul(omega);
        }
    }

    function extract(uint256[] memory input, uint256 parity) internal pure returns (uint256[] memory result) {
        result = new uint256[](input.length / 2);
        for (uint256 i = 0; i < input.length / 2; i++) {
            result[i] = input[2 * i + parity];
        }
    }

    function unserialize(bytes memory arr) internal pure returns (TransferProof memory proof) {
        proof.BA = Utils.ECPoint(Utils.slice(arr, 0), Utils.slice(arr, 32));
        proof.BS = Utils.ECPoint(Utils.slice(arr, 64), Utils.slice(arr, 96));
        proof.A = Utils.ECPoint(Utils.slice(arr, 128), Utils.slice(arr, 160));
        proof.B = Utils.ECPoint(Utils.slice(arr, 192), Utils.slice(arr, 224));

        uint256 m = (arr.length - 1472) / 576;
        proof.CLnG = new Utils.ECPoint[](m);
        proof.CRnG = new Utils.ECPoint[](m);
        proof.C_0G = new Utils.ECPoint[](m);
        proof.DG = new Utils.ECPoint[](m);
        proof.y_0G = new Utils.ECPoint[](m);
        proof.gG = new Utils.ECPoint[](m);
        proof.C_XG = new Utils.ECPoint[](m);
        proof.y_XG = new Utils.ECPoint[](m);
        proof.f = new uint256[](2 * m);
        for (uint256 k = 0; k < m; k++) {
            proof.CLnG[k] = Utils.ECPoint(Utils.slice(arr, 256 + k * 64), Utils.slice(arr, 288 + k * 64));
            proof.CRnG[k] = Utils.ECPoint(Utils.slice(arr, 256 + (m + k) * 64), Utils.slice(arr, 288 + (m + k) * 64));
            proof.C_0G[k] = Utils.ECPoint(Utils.slice(arr, 256 + m * 128 + k * 64), Utils.slice(arr, 288 + m * 128 + k * 64));
            proof.DG[k] = Utils.ECPoint(Utils.slice(arr, 256 + m * 192 + k * 64), Utils.slice(arr, 288 + m * 192 + k * 64));
            proof.y_0G[k] = Utils.ECPoint(Utils.slice(arr, 256 + m * 256 + k * 64), Utils.slice(arr, 288 + m * 256 + k * 64));
            proof.gG[k] = Utils.ECPoint(Utils.slice(arr, 256 + m * 320 + k * 64), Utils.slice(arr, 288 + m * 320 + k * 64));
            proof.C_XG[k] = Utils.ECPoint(Utils.slice(arr, 256 + m * 384 + k * 64), Utils.slice(arr, 288 + m * 384 + k * 64));
            proof.y_XG[k] = Utils.ECPoint(Utils.slice(arr, 256 + m * 448 + k * 64), Utils.slice(arr, 288 + m * 448 + k * 64));
            proof.f[k] = uint256(Utils.slice(arr, 256 + m * 512 + k * 32));
            proof.f[k + m] = uint256(Utils.slice(arr, 256 + m * 544 + k * 32));
        }
        uint256 starting = m * 576;
        proof.z_A = uint256(Utils.slice(arr, 256 + starting));

        proof.tCommits = [Utils.ECPoint(Utils.slice(arr, 288 + starting), Utils.slice(arr, 320 + starting)), Utils.ECPoint(Utils.slice(arr, 352 + starting), Utils.slice(arr, 384 + starting))];
        proof.tHat = uint256(Utils.slice(arr, 416 + starting));
        proof.mu = uint256(Utils.slice(arr, 448 + starting));

        proof.c = uint256(Utils.slice(arr, 480 + starting));
        proof.s_sk = uint256(Utils.slice(arr, 512 + starting));
        proof.s_r = uint256(Utils.slice(arr, 544 + starting));
        proof.s_b = uint256(Utils.slice(arr, 576 + starting));
        proof.s_tau = uint256(Utils.slice(arr, 608 + starting));

        InnerProductVerifier.InnerProductProof memory ipProof;
        ipProof.ls = new Utils.ECPoint[](6);
        ipProof.rs = new Utils.ECPoint[](6);
        for (uint256 i = 0; i < 6; i++) { // 2^6 = 64.
            ipProof.ls[i] = Utils.ECPoint(Utils.slice(arr, 640 + starting + i * 64), Utils.slice(arr, 672 + starting + i * 64));
            ipProof.rs[i] = Utils.ECPoint(Utils.slice(arr, 640 + starting + (6 + i) * 64), Utils.slice(arr, 672 + starting + (6 + i) * 64));
        }
        ipProof.a = uint256(Utils.slice(arr, 640 + starting + 6 * 128));
        ipProof.b = uint256(Utils.slice(arr, 672 + starting + 6 * 128));
        proof.ipProof = ipProof;

        return proof;
    }
}
