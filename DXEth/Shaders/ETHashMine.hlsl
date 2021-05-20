//#include "ETHash.hlsli"

cbuffer param : register(b0) {
    uint4 target[2];
    uint4 header[2];
    uint2 startNonce;
    uint numDatasetElements;
    uint init;
}; // 20 words, 80 bytes total

struct result {
    //uint count;    // 4 bytes
    //uint pad;
    struct {
        uint nonce[2]; // 8 bytes
    } nonces[1];
};
typedef struct {
    uint4 data[4];
} uint512;

StructuredBuffer<uint512> dataset0 : register(t0);
StructuredBuffer<uint512> dataset1 : register(t1);
StructuredBuffer<uint512> dataset2 : register(t2);
StructuredBuffer<uint512> dataset3 : register(t3);
/*
tbuffer<uint512> dataset0 : register(t0);
tbuffer<uint512> dataset1 : register(t1);
tbuffer<uint512> dataset2 : register(t2);
tbuffer<uint512> dataset3 : register(t3);*/

RWStructuredBuffer<struct result> mineResult : register(u4);

\

#define DATASET_SHARDS 4

#ifndef NUM_THREADS
#define NUM_THREADS 16
#endif

#ifndef KECCAK_ROUNDS
#define KECCAK_ROUNDS 24
#endif

#define DATASET_PARENTS 256
#define CACHE_ROUNDS 3
#define HASH_WORDS 16
#define ACCESSES 64
#define MAX_FOUND 1

// NOTE: we're using uint2 as a 64bit integer in most cases
// this is little endian, i.e.
// uint2.x: lower bits
// uint2.y: higher bits

// FNV implementation
#define FNV_PRIME 0x01000193
#define fnv(v1, v2) (((v1) * FNV_PRIME) ^ (v2))

void fnvHash(inout uint mix[16], in uint data[16]) {
    uint i;
    uint4 mixCasted[4] = (uint4[4])mix;
    uint4 dataCasted[4] = (uint4[4])data;
    for (i = 0; i < 4; i++) {
        mixCasted[i] = fnv(mixCasted[i], dataCasted[i]);
    }
    mix = (uint[16])mixCasted;
}

// keccak (SHA-3) implementation
// OR more precisely Keccak-f[1600]
static const uint2 keccak_rndc[24] = {
    uint2(0x00000001, 0x00000000),
    uint2(0x00008082, 0x00000000),
    uint2(0x0000808a, 0x80000000),
    uint2(0x80008000, 0x80000000),
    uint2(0x0000808b, 0x00000000),
    uint2(0x80000001, 0x00000000),
    uint2(0x80008081, 0x80000000),
    uint2(0x00008009, 0x80000000),
    uint2(0x0000008a, 0x00000000),
    uint2(0x00000088, 0x00000000),
    uint2(0x80008009, 0x00000000),
    uint2(0x8000000a, 0x00000000),
    uint2(0x8000808b, 0x00000000),
    uint2(0x0000008b, 0x80000000),
    uint2(0x00008089, 0x80000000),
    uint2(0x00008003, 0x80000000),
    uint2(0x00008002, 0x80000000),
    uint2(0x00000080, 0x80000000),
    uint2(0x0000800a, 0x00000000),
    uint2(0x8000000a, 0x80000000),
    uint2(0x80008081, 0x80000000),
    uint2(0x00008080, 0x80000000),
    uint2(0x80000001, 0x00000000),
    uint2(0x80008008, 0x80000000),
};

static const uint keccak_rotc[24] = {
    1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14,
    27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44
};

static const uint keccak_piln[24] = {
    10, 7,  11, 17, 18, 3, 5,  16, 8,  21, 24, 4,
    15, 23, 19, 13, 12, 2, 20, 14, 22, 9,  6,  1
};

uint2 rotl64(uint2 a, uint b) {
    uint2 t = uint2(0, 0);
    if (b >= 32) {
        a = a.yx;
        b -= 32;
    }
    if (b == 0) {
        return a;
    }
    t.x = (a.x << b) | (a.y >> (32 - b));
    t.y = (a.y << b) | (a.x >> (32 - b));
    return t;
}

void keccak(inout uint2 st[25])
{
    // variables
    uint i, j, r;
    uint2 t, bc[5];

    // actual iteration
    for (r = 0; r < KECCAK_ROUNDS; r++) {
        // theta
        for (i = 0; i < 5; i++)
            bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];

        for (i = 0; i < 5; i++) {
            t = bc[(i + 4) % 5] ^ rotl64(bc[(i + 1) % 5], 1);
            for (j = 0; j < 25; j += 5)
                st[j + i] ^= t;
        }

        // rho pi
        t = st[1];
        for (i = 0; i < 24; i++) {
            j = keccak_piln[i];
            bc[0] = st[j];
            st[j] = rotl64(t, keccak_rotc[i]);
            t = bc[0];
        }

        // chi
        for (j = 0; j < 25; j += 5) {
            for (i = 0; i < 5; i++)
                bc[i] = st[j + i];
            for (i = 0; i < 5; i++)
                st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
        }

        //  iota
        st[0] ^= keccak_rndc[r];
    }
}

// a special case for keccak 512, where input is also 512 bits
// note that this implements the original keccak, not the NIST version
void keccak_512_512(out uint dst[16], in uint src[16]) {
    uint i;
    uint2 st[25];

    for (i = 0; i < 8; i++)
        st[i] = uint2(src[i * 2], src[i * 2 + 1]);

    for (i = 8; i < 25; i++)
        st[i] = 0;

    // 64, 71
    st[8] = uint2(0x00000001, 0x80000000);

    keccak(st);

    for (i = 0; i < 8; i++) {
        dst[i * 2] = st[i].x;
        dst[i * 2 + 1] = st[i].y;
    }
}

// a special case for keccak 512, where input is 320 bits
// note that this implements the original keccak, not the NIST version
void keccak_512_320(out uint dst[16], in uint src[10]) {
    uint i;
    uint2 st[25];

    for (i = 0; i < 5; i++)
        st[i] = uint2(src[i * 2], src[i * 2 + 1]);

    for (i = 5; i < 25; i++)
        st[i] = 0;

    // 40, 71
    st[5] = uint2(0x00000001, 0x00000000);
    st[8] = uint2(0x00000000, 0x80000000);

    keccak(st);

    for (i = 0; i < 8; i++) {
        dst[i * 2] = st[i].x;
        dst[i * 2 + 1] = st[i].y;
    }
}

void keccak_256_768(out uint dst[8], in uint src[24]) {
    uint i;
    uint2 st[25];

    for (i = 0; i < 12; i++)
        st[i] = uint2(src[i * 2], src[i * 2 + 1]);

    for (i = 12; i < 25; i++)
        st[i] = 0;

    // 96 135
    st[12] = uint2(0x00000001, 0x00000000);
    st[16] = uint2(0x00000000, 0x80000000);

    keccak(st);
    for (i = 0; i < 4; i++) {
        dst[i * 2] = st[i].x;
        dst[i * 2 + 1] = st[i].y;
    }
}

void datasetLoad(out uint data[16], uint index) {
    uint shard;
    shard = index % 4;
    index = index / 4;
    if (shard == 0)
        data = (uint[16])dataset0.Load(index).data;
        //data = (uint[16])dataset0[index].data;
    else if (shard == 1)
        data = (uint[16])dataset1.Load(index).data;
        //data = (uint[16])dataset1[index].data;
    else if (shard == 2)
        data = (uint[16])dataset2.Load(index).data;
        //data = (uint[16])dataset2[index].data;
    else if (shard == 3)
        data = (uint[16])dataset3.Load(index).data;
        //data = (uint[16])dataset3[index].data;
}


/*
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

*/
[numthreads(64,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i, index, foundIndex;
    StructuredBuffer<uint512> dbs[4];
    dbs[0] = dataset0;
    dbs[1] = dataset1;
    dbs[2] = dataset2;
    dbs[3] = dataset3;
    /*index = -1;
    for (i = 0; i < 9999999; i++) {
        index += index % 9999999;
    }
    return;*/

    uint hashResult[8];
    //uint be_target[8];
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
    headerNonce[8] += tid.x * 64;// +tid.y;//foundIndex;//(tid.x + (tid.y * NUM_Y_THREADS) +(tid.z * NUM_X_THREADS * NUM_Y_THREADS * NUM_Z_THREADS)) * 64;

    //return;
    //if (headerNonce[8] < startNonce[0])
    //    headerNonce[9]++;

    //does this make diff?
    //for (i = 0; i < 8; i++)
    //    hashResult[i] = 0;
    headerNonce[8] ++;
    // calculate seed
    keccak_512_320(seed, headerNonce);

    // initialize mix
    mix0 = seed;
    mix1 = seed;

    //[unroll(ACCESSES)]
    [unroll(64)]
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
    [unroll]
    for (i = 0; i < 4; i++) {
        j = i * 4; // j <= 12
        digest[i] = fnv(fnv(fnv(mix0[j + 0], mix0[j + 1]), mix0[j + 2]), mix0[j + 3]);
    }
    //ORIG
    [unroll]
    for (i = 4; i < 8; i++) {
        j = i * 4 - 16; // j <= 12
        digest[i] = fnv(fnv(fnv(mix1[j + 0], mix1[j + 1]), mix1[j + 2]), mix1[j + 3]);
    }

    // concatinate seed and string
    [unroll]
    for (i = 0; i < 16; i++)
        concat[i] = seed[i];
    [unroll]
    for (i = 16; i < 24; i++)
        concat[i] = digest[i - 16];

    keccak_256_768(hashResult, concat);
    //hash0_w_nonces = min(hash0_w_nonces, hashResult[0]);

    if ((hashResult[0] == 0)) {
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

