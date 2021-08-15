#include "ETHash.hlsli"

// The cache. Each entry is 512 bits / 64 bytes
// This should be filled in before kernel execution
// as the cache cannot be computed in parallel
// cache must be at least numCacheElements long
RWStructuredBuffer<uint512> cache : register(u4);

// numCacheElements is the _element_ count of the cache.
// aka rows in some documentation

cbuffer params : register(b0) {
    uint numDatasetElements;
    uint numCacheElements;
    uint datasetGenerationOffset;
};


void cacheLoad(out uint data[16], uint index) {
    data = (uint[16])cache[index].data;
}

[numthreads(NUM_THREADS, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint index;
    uint i, j, parentIndex;
    uint mix[16]; // 512 bits
    uint parent[16];

    index = tid[0] + datasetGenerationOffset;

    if (index >= numDatasetElements)
        return;

    // initialize the mix
    cacheLoad(mix, index % numCacheElements);
    mix[0] ^= index;

    keccak_512_512(mix, mix);

    [loop]
    for (i = 0; i < DATASET_PARENTS; i++) {
        parentIndex = fnv(index ^ i, mix[i % 16]) % numCacheElements;
        // retrieve parent from cache
        cacheLoad(parent, parentIndex);
        fnvHash(mix, parent);
    }

    keccak_512_512(mix, mix);

    // store mix into the desired dataset node
    datasetStore(index, mix);
}

