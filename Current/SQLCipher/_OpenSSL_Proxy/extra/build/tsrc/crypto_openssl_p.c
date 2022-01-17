/*
**
*/
#ifndef CRYPTO_OPENSSL_PROXY_C
#define CRYPTO_OPENSSL_PROXY_C

#include <openssl/rand.h>
#include <openssl/evp.h>
#include <openssl/objects.h>
#include <openssl/hmac.h>
#include <openssl/err.h>
#include "crypto_openssl_p.h"


/* <openssl/objects.h> */
SQLITE_API const char *SQLITE_APICALL OBJ_nid2sn_p(int n) {
  return OBJ_nid2sn(n);
}

/******************************************************************************/

/* <openssl/evp.h> */
SQLITE_API const EVP_MD *SQLITE_APICALL EVP_sha1_p(void) {
  return EVP_sha1();
}

SQLITE_API const EVP_MD *SQLITE_APICALL EVP_sha256_p(void) {
  return EVP_sha256();
}

SQLITE_API const EVP_MD *SQLITE_APICALL EVP_sha512_p(void) {
  return EVP_sha512();
}

SQLITE_API const EVP_CIPHER *SQLITE_APICALL EVP_aes_256_cbc_p(void) {
  return EVP_aes_256_cbc();
}

SQLITE_API EVP_CIPHER_CTX *SQLITE_APICALL EVP_CIPHER_CTX_new_p(void) {
  return EVP_CIPHER_CTX_new();
}

SQLITE_API int SQLITE_APICALL PKCS5_PBKDF2_HMAC_p(const char *pass, int passlen,
                      const unsigned char *salt, int saltlen, int iter, const EVP_MD *digest, int keylen, unsigned char *out) {
  return PKCS5_PBKDF2_HMAC(pass, passlen, salt, saltlen, iter, digest, keylen, out);
}

/******************************************************************************/

/* <openssl/rand.h> */
SQLITE_API int SQLITE_APICALL RAND_bytes_p(unsigned char *buf, int num) {
  return RAND_bytes(buf, num);
}

SQLITE_API void SQLITE_APICALL RAND_add_p(const void *buf, int num, double randomness) {
  RAND_add(buf, num, randomness);
}

/******************************************************************************/

/* <openssl/hmac.h> */
SQLITE_API HMAC_CTX *SQLITE_APICALL HMAC_CTX_new_p(void) {
  return HMAC_CTX_new();
}

SQLITE_API void SQLITE_APICALL HMAC_CTX_free_p(HMAC_CTX *ctx) {
  HMAC_CTX_free(ctx);
}

SQLITE_API int SQLITE_APICALL HMAC_Init_ex_p(HMAC_CTX *ctx, const void *key, int len, const EVP_MD *md, ENGINE *impl) {
  return HMAC_Init_ex(ctx, key, len, md, impl);
}

SQLITE_API int SQLITE_APICALL HMAC_Update_p(HMAC_CTX *ctx, const unsigned char *data, size_t len) {
  return HMAC_Update(ctx, data, len);
}

SQLITE_API int SQLITE_APICALL HMAC_Final_p(HMAC_CTX *ctx, unsigned char *md, unsigned int *len) {
  return HMAC_Final(ctx, md, len);
}

#endif /* CRYPTO_OPENSSL_PROXY_C */
