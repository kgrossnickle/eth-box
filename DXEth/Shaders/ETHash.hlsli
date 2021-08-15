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

typedef struct {
    uint4 data[4];
} uint512;

// The DAG. Note that each DAG entry is 512 bits.
// so 16 uints makes up a DAG entry
// we need to split the dataset into 4 parts
// since we have a hard 2GB limit on the dataset size
#if DATASET_SHARDS == 4
RWStructuredBuffer<uint512> dataset0 : register(u0);
RWStructuredBuffer<uint512> dataset1 : register(u1);
RWStructuredBuffer<uint512> dataset2 : register(u2);
RWStructuredBuffer<uint512> dataset3 : register(u3);

void datasetStore(uint index, uint data[16]) {
    uint shard, i;

    shard = index % 4;
    index = index / 4;
    
    if (shard == 0)
        dataset0[index] = (uint4[4])data;
    else if (shard == 1)
        dataset1[index] = (uint4[4])data;
    else if (shard == 2)
        dataset2[index] = (uint4[4])data;
    else if (shard == 3)
        dataset3[index] = (uint4[4])data;
}

void datasetStoreNew(uint index, uint data[16]) {
    uint shard, i;
    //8519646 is num dataset elements @ epoich 2
    // max is 17039294 epoch 2
    //        8519647
    //        73007062
    //shard = index / (8519647 / 3);
                
    //index = index / 4;
    //index /= 2;
    if (index <= 24335687)
        dataset0[index] = (uint4[4])data;
    else if (index <= 24335687)
        dataset1[index - 24335687] = (uint4[4])data;
    else if (index <= 73007061)
        dataset2[index - 48671374] = (uint4[4])data;
    else if (index  > 73007061)
        dataset3[index - 73007061] = (uint4[4])data;
}


void datasetLoad(out uint data[16], uint index) {
    uint shard;
    shard = index % 4;
    index = index / 4;
    if (shard == 0)
        data = (uint[16])dataset0[index].data;
    else if (shard == 1)
        data = (uint[16])dataset1[index].data;
    else if (shard == 2)
        data = (uint[16])dataset2[index].data;
    else if (shard == 3)
        data = (uint[16])dataset3[index].data;
}

void datasetLoad2(out uint data0[16], out uint data1[16], uint index) {
    uint shard;
    shard = index % 4;
    index = index / 4;
    uint4 t0[4];
    uint4 t1[4];
    if (shard == 0) {
        t0 = dataset0[index].data;
        t1 = dataset0[index+1].data;
    } 
    else if (shard == 1) {
        t0 = dataset1[index].data;
        t1 = dataset1[index + 1].data;
    }
    else if (shard == 2) {
        t0 = dataset2[index].data;
        t1 = dataset2[index + 1].data;
    }
    else if (shard == 3) {
        t0 = dataset3[index].data;
        t1 = dataset3[index + 1].data;
    }
    data0 = (uint[16])t0;
    data1 = (uint[16])t1;
}
#elif !defined(DATASET_SHARDS) || DATASET_SHARDS == 1
RWStructuredBuffer<uint512> dataset_0 : register(u0);
void datasetStore(uint index, uint data[16]) {
    //orig
    dataset[index] = (uint4[4])data;
    //dataset[index] = (uint[16])data;
}

void datasetLoad(out uint data[16], uint index) {
    data = (uint[16])dataset[index];
}
#else
#error Unsupported number of shards
#endif
