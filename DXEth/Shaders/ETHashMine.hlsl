#include "ETHash.hlsli"

cbuffer param : register(b0) {
    uint4 target[2];
    uint4 header[2];
    uint2 startNonce;
    uint numDatasetElements;
    uint init;
}; // 20 words, 80 bytes total

struct result {
    uint count;    // 4 bytes
    uint pad;
    struct {
        uint nonce[2]; // 8 bytes
    } nonces[MAX_FOUND];
};

RWStructuredBuffer<struct result> mineResult : register(u4);

// headerNonce is [header .. nonce]
void hashimoto(out uint result[8], uint headerNonce[10]) {
    uint i, j, parentIndex;
    uint seed[16];

    uint mix0[16];
    uint mix1[16];

    uint temp0[16];
    uint temp1[16];

    uint digest[8];
    uint concat[24];

    // calculate seed
    keccak_512_320(seed, headerNonce);

    // initialize mix
    mix0 = seed;
    mix1 = seed;

    // [unroll(ACCESSES)]
    //ORIGINAL
    /*
    [unroll(ACCESSES)]
    for (i = 0; i < ACCESSES; i++) {
        j = i % 32;
        parentIndex = fnv(seed[0] ^ i, j < 16 ? mix0[j % 16] : mix1[j % 16]) % (numDatasetElements / 2);
        // parentIndex = fnv(seed[0] ^ i, j < 16 ? mix0[j % 16] : mix1[j % 16]) % (128 / 2);
        // note, this access is 1024 bits / 128 bytes / 32 words wide
        datasetLoad2(temp0, temp1, parentIndex * 2);
        fnvHash(mix0, temp0);
        fnvHash(mix1, temp1);
    }
    */
    [unroll(ACCESSES)]
    for (i = 0; i < ACCESSES; i++) {
        j = i % 32;
        parentIndex = fnv(i ^ seed[0] , j < 16 ? mix0[j % 16] : mix1[j % 16]) % (numDatasetElements / 2);
        // parentIndex = fnv(seed[0] ^ i, j < 16 ? mix0[j % 16] : mix1[j % 16]) % (128 / 2);
        // note, this access is 1024 bits / 128 bytes / 32 words wide
        //datasetLoad(temp0, parentIndex);
        //datasetLoad2(temp0, temp1, parentIndex * 2);
        datasetLoad(temp0, parentIndex * 2);
        datasetLoad(temp1, (parentIndex * 2) + 1);
        fnvHash(mix0, temp0);
        fnvHash(mix1, temp1);
    }
    //UP TO HERE CORRECT! PREV CORRECT CHECKING BELOW 
    /*
    for (i = 0; i < 16; i++)
        mineResult[0].nonces[i].nonce[0] = temp1[i];
    

    mineResult[0].nonces[16].nonce[0] = ACCESSES;
    mineResult[0].nonces[17].nonce[0] = parentIndex;
    */

    // compress mix into 256 bits
    for (i = 0; i < 4; i++) {
        j = i * 4; // j <= 12
        digest[i] = fnv(fnv(fnv(mix0[j + 0], mix0[j + 1]), mix0[j + 2]), mix0[j + 3]);
    }

    for (i = 4; i < 8; i++) {
        j = i * 4 - 16; // j <= 12
        digest[i] = fnv(fnv(fnv(mix1[j + 0], mix1[j + 1]), mix1[j + 2]), mix1[j + 3]);
    }

    // concatinate seed and string
    for (i = 0; i < 16; i++)
        concat[i] = seed[i];
    for (i = 16; i < 24; i++)
        concat[i] = digest[i - 16];

    //MIX DIGEST CORRECT UP TO HERE, OLD CHECK CODE
    //for (i = 0; i < 8; i++)
    //    mineResult[0].nonces[i].nonce[0] = digest[i];

    keccak_256_768(result, concat);
}
//need to put back to NUM_THREADS
[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i, index, foundIndex;
    uint hashResult[8];
    uint headerNonce[10]; // [header .. nonce]
    bool found;

    //for (i = 0; i < 8; i++)
    //    mineResult[0].nonces[i].nonce[0] = header[i / 4][i % 4];
    //return;

    index = tid.x;
    if (index == 0 && init != 0) {
        mineResult[0].count = 0;
    }

    for (i = 0; i < 8; i++)
        headerNonce[i] = header[i / 4][i % 4];

    for (i = 0; i < 2; i++)
        headerNonce[i + 8] = startNonce[i];

    headerNonce[8] += index;
    if (headerNonce[8] < startNonce[0])
        headerNonce[9]++;

    for (i = 0; i < 8; i++)
        hashResult[i] = 0;

    hashimoto(hashResult, headerNonce);
    for (i = 0; i < 8; i++)
        mineResult[0].nonces[i].nonce[0] = hashResult[i];
    return;
    for (i = 0; i < 8; i++)
        mineResult[0].nonces[i].nonce[0] = hashResult[i];
    return;
    found = false;
    for (i = 0; i < 8; i++)
        found = found || hashResult[i] < target[i / 4][i % 4];
    /*
    for (i = 0; i < 8; i++) {
        if (hashResult[i] < target[i / 4][i % 4]) {
            found = true;
            break;
        }
        if (hashResult[i] > target[i / 4][i % 4]) {
            found = false;
            break;
        }
    }*/


    //for (i = 0; i < 8; i++)
    //    if  hashResult[i] < target[i / 4][i % 4]{}

    if (!found)
        return;

    InterlockedAdd(mineResult[0].count, 1, foundIndex);

    if (foundIndex >= MAX_FOUND)
        return;

    for (i = 0; i < 2; i++)
        mineResult[0].nonces[0].nonce[i] = headerNonce[i + 8];
}