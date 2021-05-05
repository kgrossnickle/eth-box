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
    [unroll(ACCESSES)]
    for (i = 0; i < ACCESSES; i++) {
        j = i % 32;
        parentIndex = fnv(seed[0] ^ i, j < 16 ? mix0[j % 16] : mix1[j % 16]) % (numDatasetElements / 2);
        // parentIndex = fnv(seed[0] ^ i, j < 16 ? mix0[j % 16] : mix1[j % 16]) % (128 / 2);
        // note, this access is 1024 bits / 128 bytes / 32 words wide
        datasetLoad2(temp0, temp1, parentIndex * 2);
        // datasetLoad(temp0, parentIndex * 2);
        // datasetLoad(temp1, parentIndex * 2 + 1);
        
        fnvHash(mix0, temp0);
        fnvHash(mix1, temp1);
    }

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

    keccak_256_768(result, concat);
}

//uniform uint debug : register(b0);
//RWStructuredBuffer<uint> debug_buffer : register(u6);

[numthreads(NUM_THREADS, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i, index, foundIndex;
    uint hashResult[8];
    uint headerNonce[10]; // [header .. nonce]
    bool found;
    
    //uint rem_idx = tid.x % MAX_FOUND;
    //InterlockedAdd(mineResult[0].count, 1, foundIndex);
    index = tid.x;
    if (index == 0 && init != 0) {
        mineResult[0].count = 0;
    }
    
    for (i = 0; i < 8; i++)
        headerNonce[i] = header[i/4][i%4];
    
    // 5 MH drop here. 43 MH on local after this loop
    for (i = 0; i < 2; i++)
        headerNonce[i + 8] = startNonce[i];
    
    //3 MH drop here!!
    headerNonce[8] = tid.x;
    
    //3 MH drop here 37MH at last check
    if (headerNonce[8] < startNonce[0])
        headerNonce[9]++;
    
    //41 MH here last?? ok...
    for (i = 0; i < 8; i++)
        hashResult[i] = 0;

    
    //2-3 MH drop here
    hashimoto(hashResult, headerNonce);
    
    found = false;
    for (i = 0; i < 8; i++)
        found = found || hashResult[i] < target[i/4][i%4];
    
    //if (index == 0 && debug) {
    //    for (i = 0; i < 8; i++)
    //        debug_buffer[index * 8 + i] = result[i];
    //}

    if (!found)
        return;
    

    //25 MH drop here !!! 41-> 10
    //InterlockedAdd(mineResult[0].count, 1, foundIndex);
     
    //NOTE THIS IS BROKEN, need some sort of interprocess break or count add etc.
    //
    // Maybe TID / 16 
    // 
    // 
    //Both below are -2 MH.. not bad
    if (foundIndex >= MAX_FOUND)
        return;
    // can overwrite nonce to make invalid, we just take that risk...
    for (i = 0; i < 2; i++)
        mineResult[0].nonces[0].nonce[i] = headerNonce[i + 8];
}

