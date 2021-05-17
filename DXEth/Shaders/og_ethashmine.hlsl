void main(uint3 tid : SV_DispatchThreadID) {
    uint i, index, foundIndex;
    uint hashResult[8];
    uint be_target[8];
    uint headerNonce[10]; // [header .. nonce]
    bool found;

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

    //InterlockedAdd(mineResult[0].count, 1, foundIndex);
    //while (tot_run < 1) {
    //    headerNonce[8]++;

        // dont check lets just inc each time
        //if (headerNonce[8] < startNonce[0])

    //    headerNonce[9]++;
    //    tot_run++;
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

        //MIX DIGEST CORRECT UP TO HERE, OLD CHECK CODE
        //for (i = 0; i < 8; i++)
        //    mineResult[0].nonces[i].nonce[0] = digest[i];

        keccak_256_768(hashResult, concat);
        //
        /*
        r1 = hashResult[0];
        r2 = hashResult[1];

        b0 = (r1 >> 24);
        b1 = ((r1 << 8) & 0x00ff0000);
        b2 = ((r1 >> 8) & 0x0000ff00);
        b3 = (r1 << 24);

        b0 = b0 | b1;
        b1 = b2 | b3;
        tmp = b1 - 1;
        tmp = tmp + 1;
        tmp2 = b0 + 1;
        tmp2 = b0 - 1;
        res = tmp2 | tmp;
        r1 = res + 1;

        b0 = (r2 >> 24);
        b1 = ((r2 << 8) & 0x00ff0000);
        b2 = ((r2 >> 8) & 0x0000ff00);
        b3 = (r2 << 24);

        b0 = b0 | b1;
        b1 = b2 | b3;
        tmp = b1 - 1;
        tmp = tmp + 1;
        tmp2 = b0 + 1;
        tmp2 = b0 - 1;
        res = tmp2 | tmp;
        r2 = res + 1;
        */
        
        //if (r1 < bound || (r1 == bound && r2 < bound2 ) ) {
        // hardcoded boundary!!!!
         if (hashResult[0] == 0) {
            //count = mineResult[0].count;
            mineResult[0].nonces[0].nonce[0] = headerNonce[8];
            mineResult[0].nonces[0].nonce[1] = headerNonce[9];
            //InterlockedAdd(mineResult[0].count, 1);
            //finalNonce[0] = headerNonce[8];
            //finalNonce[1] = headerNonce[9];
            //found = true;
        }
        //minv = min(minv, hashResult[0]);
    //}

    //if (found) {
    //    mineResult[0].nonces[0].nonce[0] = finalNonce[0];
    //    mineResult[0].nonces[0].nonce[1] = finalNonce[1];
        //InterlockedAdd(mineResult[0].count, 1, foundIndex);
    //}
    
    
    
    //mineResult[0].nonces[0].nonce[0] = hashResult[0];
    //mineResult[0].nonces[0].nonce[0] = (hashResult[0] < be_target[0]) ? hashResult[0] : mineResult[0].nonces[0].nonce[0]  ;


    //mineResult[0].nonces[0].nonce[0] = headerNonce[8];
        //mineResult[0].nonces[0].nonce[0] = headerNonce[8];
        //InterlockedAdd(mineResult[0].count, 1, foundIndex);
        //for (i = 0; i < 2; i++)
        //    mineResult[0].nonces[0].nonce[i] = headerNonce[i + 8];
        //mineResult[0].nonces[0].nonce[0] = headerNonce[ 8];
        //mineResult[0].nonces[0].nonce[1] = headerNonce[9];
    



    
    //THis doesnt error, might be faster to leave out
    //if (foundIndex >= MAX_FOUND)
    //    return;

    //change index below, debugging

}