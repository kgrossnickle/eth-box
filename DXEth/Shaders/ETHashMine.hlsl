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

uint le_to_be(uint num) {

    uint b0, b1, b2, b3;
    uint tmp;
    uint tmp2;
    uint res;
    b0 = (num >> 24);
    b1 = ((num << 8) & 0x00ff0000);
    b2 = ((num >> 8) & 0x0000ff00);
    b3 = (num << 24);

    b0 = b0 | b1;
    b1 = b2 | b3;
    tmp = b1 - 1;
    tmp = tmp + 1;
    tmp2 = b0 + 1;
    tmp2 = b0 - 1;
    res = tmp2 | tmp;
    return  res + 1;
}
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
        parentIndex = fnv(i ^ seed[0], j < 16 ? mix0[j % 16] : mix1[j % 16]) % (numDatasetElements / 2);
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
    for (i = 0; i < 8; i++) {
        result[i] = le_to_be(result[i]);
    }
}
void uint32_to_8(uint32_t x[8], out uint lit_int[32]) {
    uint i;
    for( i = 0; i < 32; i+=4){
        lit_int[i] = (uint)(x[i] >> 0);
        lit_int[i+1] = (uint)(x[i] >> 8);
        lit_int[i+2] = (uint)(x[i] >> 16);
        lit_int[i+3] = (uint)(x[i] >> 24);
    }
}
void targ_to_uint8s(uint4 target[2], out uint lit_int[32]) {
    uint t[8];
    uint i;
    for (i = 0; i < 8; i++) {
        t[i] = target[i / 4][i % 4];
    }
    uint32_to_8(t, lit_int);
}
//x = ( x >> 24 ) | (( x << 8) & 0x00ff0000 )| ((x >> 8) & 0x0000ff00) | ( x << 24)  ; 



//need to put back to NUM_THREADS
[numthreads(NUM_THREADS, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i, index, foundIndex;
    uint hashResult[8];
    uint be_target[8];
    uint headerNonce[10]; // [header .. nonce]
    bool found;

    for (i = 0; i < 8; i++) {
        be_target[i] = le_to_be(target[i / 4][i % 4]);
    }
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
    
    found = false;
    //replace for loop with uint256 hash < uint256 target
    for (i = 0; i < 8; i++) {
        if ((hashResult[i]) < be_target[i]) {
            found = true;
            break;
        }
        if ((hashResult[i]) > be_target[i]) {
            found = false;
            break;
        }
    }
    if (!found)
        return;

    InterlockedAdd(mineResult[0].count, 1, foundIndex);
    for (i = 0; i < 2; i++)
        mineResult[0].nonces[0].nonce[i] = headerNonce[i + 8];
    
    //THis doesnt error, might be faster to leave out
    //if (foundIndex >= MAX_FOUND)
    //    return;

    //change index below, debugging

}