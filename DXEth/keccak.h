#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

typedef struct keccak_ctx keccak_ctx_t;

keccak_ctx_t* keccak_init(int mdlen);
int keccak_update(keccak_ctx_t* c, const void* data, size_t len);
int keccak_final(void* md, keccak_ctx_t* c);
void keccak_free(keccak_ctx_t* c);

void* keccak(const void* in, size_t inlen, void* md, int mdlen);

#ifdef __cplusplus
}
#endif
