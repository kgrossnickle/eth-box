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
    //return result[0];
    //mineResult[0].nonces[0].nonce[0] = result[0];
    //mineResult[0].nonces[0].nonce[1] = result[1];
    //if ( le_to_be(result[0]) < be_target[0]  ) {
    //    mineResult[0].nonces[0].nonce[0] = headerNonce[8];
    //    mineResult[0].nonces[0].nonce[1] = headerNonce[9];
    // }
    //mineResult[0].pad = result[0];
    
    //replace for loop with uint64 hash < uint64 target

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


uint rand_lcg(uint rng_state)
{
    // LCG values from Numerical Recipes
    rng_state = 1664525 * rng_state + 1013904223;
    return rng_state;
}

uint rand_xorshift(uint rng_state)
{
    // Xorshift algorithm from George Marsaglia's paper
    rng_state ^= (rng_state << 13);
    rng_state ^= (rng_state >> 17);
    rng_state ^= (rng_state << 5);
    return rng_state;
}

uint when_eq(uint x, uint y) {
    return 1.0 - abs(sign(x - y));
}

groupshared uint hash0_w_nonces = 9;

[numthreads(16,1,1)]
void main(uint3 groupID : SV_GroupID, uint3 tid : SV_DispatchThreadID, uint groupIndex : SV_GroupIndex) {

    uint i, index, foundIndex;
    uint hashResult[8];
    uint be_target[8];
    uint headerNonce[10]; // [header .. nonce]
    //bool found = false;
    //uint ifound = 0;
    //uint n1, n2;
    //uint bound = be_target[0];
    //uint bound2 = be_target[1];
    //uint minv = be_target[0];
    //uint c = 0;

    uint j, parentIndex;
    uint seed[16];

    uint mix0[16];
    uint mix1[16];

    uint temp0[16];
    uint temp1[16];

    uint digest[8];
    uint concat[24];
   // uint finalNonce[2];
    //uint tot_run = 0;
    //uint batch_size = 64 * 1024;

    //for (i = 0; i < 8; i++) {
    //    be_target[i] = le_to_be(target[i / 4][i % 4]);
    //}
    //index = tid.x;
    //if (index == 0 && init != 0) {
    //    mineResult[0].count = 0;
    //}

    for (i = 0; i < 8; i++)
        headerNonce[i] = header[i / 4][i % 4];

    for (i = 0; i < 2; i++)
        headerNonce[i + 8] = startNonce[i];

    //looking at tid.y and z is slow af, just look at x and incrment by 64 to avoid collisions
    //InterlockedAdd(mineResult[0].count, 65, foundIndex);

    //mineResult[0].nonces[0].nonce[0] = rand;
    //mineResult[0].nonces[0].nonce[1] = rand;
    headerNonce[8] += tid.x;// +tid.y;//foundIndex;//(tid.x + (tid.y * NUM_Y_THREADS) +(tid.z * NUM_X_THREADS * NUM_Y_THREADS * NUM_Z_THREADS)) * 64;

    //return;
    //if (headerNonce[8] < startNonce[0])
    //    headerNonce[9]++;

    //does this make diff?
    //for (i = 0; i < 8; i++)
    //    hashResult[i] = 0;
    //uint tr = 0;
    //while (tr < 64) {
        //tr++;
        //headerNonce[8] ++;
        // calculate seed
        keccak_512_320(seed, headerNonce);

        // initialize mix
        mix0 = seed;
        mix1 = seed;

        //[unroll(ACCESSES)]
        for (i = 0; i < 64; i++) {
            j = i % 32;
            parentIndex = fnv(i ^ seed[0], j < 16 ? mix0[j % 16] : mix1[j % 16]) % (numDatasetElements / 2);
            datasetLoad(temp0, parentIndex * 2);
            datasetLoad(temp1, (parentIndex * 2) + 1);
            fnvHash(mix0, temp0);
            fnvHash(mix1, temp1);
        }

        //ORIG
        // compress mix into 256 bits
        for (i = 0; i < 4; i++) {
            j = i * 4; // j <= 12
            digest[i] = fnv(fnv(fnv(mix0[j + 0], mix0[j + 1]), mix0[j + 2]), mix0[j + 3]);
        }
        //ORIG
        for (i = 4; i < 8; i++) {
            j = i * 4 - 16; // j <= 12
            digest[i] = fnv(fnv(fnv(mix1[j + 0], mix1[j + 1]), mix1[j + 2]), mix1[j + 3]);
        }

        // concatinate seed and string
        for (i = 0; i < 16; i++)
            concat[i] = seed[i];
        for (i = 16; i < 24; i++)
            concat[i] = digest[i - 16];

        keccak_256_768(hashResult, concat);
        //hash0_w_nonces = min(hash0_w_nonces, hashResult[0]);

        if ((hashResult[0] == 0) ){
            mineResult[0].nonces[0].nonce[0] = headerNonce[8];
            mineResult[0].nonces[0].nonce[1] = headerNonce[9];
        }
        //if (hashResult[0] == 0)
        //    mineResult[tid.x].pad = hashResult[0];
        //TotalSum[groupIndex] = l + r;
        //GroupMemoryBarrierWithGroupSync();

        //InterlockedOr(mineResult[0].pad, hashResult[0]);
        //GroupMemoryBarrier();
        //InterlockedMin(mineResult[0].pad, hashResult[0]);
        //mineResult[0].pad = 3;// hashResult[0];//;min(mineResult[0].pad, hashResult[0]);
        //mineResult[0].nonces[0].nonce[0] = tid.x;
        //mineResult[0].nonces[0].nonce[0] = headerNonce[8] * when_eq(headerNonce[8], 0);
        //mineResult[0].nonces[0].nonce[1] = headerNonce[9] * when_eq(headerNonce[8], 0);
        //if (hashResult[0] == 0) {
        //    mineResult[tid.x].pad = hashResult[0];
            //mineResult[0].pad = 0;
            //found = true;
            //uint n1 = headerNonce[8];
            //uint n2 = headerNonce[9];
            //ifound = 1;
            //mineResult[0].pad = mineResult[0].pad | hashResult[0];
            //mineResult[0].nonces[0].nonce[0] = headerNonce[8];
            //mineResult[0].nonces[0].nonce[1] = headerNonce[9];
        //}

    //}
    //if (found) {
    //    mineResult[0].nonces[0].nonce[0] = n1;
    //    mineResult[0].nonces[0].nonce[1] = n2;
    //}
}

    /*







    //my new


    uint i, index, foundIndex;
    uint hashResult[8];
    uint be_target[8];
    uint headerNonce[10]; // [header .. nonce]
    bool found;
    uint bound = be_target[0];
    uint bound2 = be_target[1];
    uint minv = be_target[0];
    uint c = 0;

    uint j, parentIndex;
    uint seed[16];

    uint mix0[16];
    uint mix1[16];

    uint temp0[16];
    uint temp1[16];

    uint digest[8];
    uint concat[24];
    uint finalNonce[2];
    uint tot_run = 0;
    uint batch_size = 64 * 1024;
    found = false;
    uint r1;
    uint r2;

    uint b0, b1, b2, b3;
    uint tmp;
    uint tmp2;
    uint res;
    uint count;
    //for (i = 0; i < 8; i++) {
    //    be_target[i] = le_to_be(target[i / 4][i % 4]);
    //}
    //index = tid.x;
    //if (index == 0 && init != 0) {
    //    mineResult[0].count = 0;
    //}

    for (i = 0; i < 8; i++)
        headerNonce[i] = header[i / 4][i % 4];

    for (i = 0; i < 2; i++)
        headerNonce[i + 8] = startNonce[i];

    //looking at tid.y and z is slow af, just look at x and incrment by 64 to avoid collisions
    //InterlockedAdd(mineResult[0].count, 65, foundIndex);
    headerNonce[8] += tid.x;//foundIndex;//(tid.x + (tid.y * NUM_Y_THREADS) +(tid.z * NUM_X_THREADS * NUM_Y_THREADS * NUM_Z_THREADS)) * 64;
    if (headerNonce[8] < startNonce[0])
        headerNonce[9]++;

    for (i = 0; i < 8; i++)
        hashResult[i] = 0;


    // calculate seed
    keccak_512_320(seed, headerNonce);

    // initialize mix
    mix0 = seed;
    mix1 = seed;

    [unroll(ACCESSES)]
    for (i = 0; i < ACCESSES; i++) {
        j = i % 32;
        parentIndex = fnv(i ^ seed[0], j < 16 ? mix0[j % 16] : mix1[j % 16]) % (numDatasetElements / 2);
        datasetLoad(temp0, parentIndex * 2);
        datasetLoad(temp1, (parentIndex * 2) + 1);
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


    keccak_256_768(hashResult, concat);

    //if (r1 < bound || (r1 == bound && r2 < bound2 ) ) {
    // hardcoded boundary!!!!
    if (hashResult[0] == 0) {
        
            found = true;
        //count = mineResult[0].count;
        
        //InterlockedAdd(mineResult[0].count, 1);
        //finalNonce[0] = headerNonce[8];
        //finalNonce[1] = headerNonce[9];
        //found = true;
    }
    if (!found)
        return;
    mineResult[0].nonces[0].nonce[0] = headerNonce[8];
    mineResult[0].nonces[0].nonce[1] = headerNonce[9];
    


}
*/

