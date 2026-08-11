/*
**
*/

#ifndef CRYPTO_OPENSSL_PROXY_H
#define CRYPTO_OPENSSL_PROXY_H

#include <openssl/rand.h>
#include <openssl/evp.h>
#include <openssl/objects.h>
#include <openssl/hmac.h>
#include <openssl/err.h>

#ifndef SQLITE_EXTERN
#define SQLITE_EXTERN extern
#endif

#ifndef SQLITE_APICALL
#define SQLITE_APICALL __stdcall
#endif

#if (!defined(SQLITE_API) && (defined(_WIN32) || defined(WIN32)))
#  ifdef CRYPTO_OPENSSL_PROXY_C
#    define SQLITE_API __declspec(dllexport)
#  else
#    define SQLITE_API __declspec(dllimport)
#  endif
#endif

#ifdef  __cplusplus
SQLITE_EXTERN "C" {
#endif

/* <openssl/objects.h> */
SQLITE_API const char *SQLITE_APICALL OBJ_nid2sn_p(int n);

/* <openssl/evp.h> */
SQLITE_API const EVP_MD *SQLITE_APICALL EVP_sha1_p(void);
SQLITE_API const EVP_MD *SQLITE_APICALL EVP_sha256_p(void);
SQLITE_API const EVP_MD *SQLITE_APICALL EVP_sha512_p(void);
SQLITE_API const EVP_CIPHER *SQLITE_APICALL EVP_aes_256_cbc_p(void);
SQLITE_API EVP_CIPHER_CTX *SQLITE_APICALL EVP_CIPHER_CTX_new_p(void);
SQLITE_API int SQLITE_APICALL PKCS5_PBKDF2_HMAC_p(const char *pass, int passlen,
                      const unsigned char *salt, int saltlen, int iter, const EVP_MD *digest, int keylen, unsigned char *out);

/* <openssl/rand.h> */
SQLITE_API int SQLITE_APICALL RAND_bytes_p(unsigned char *buf, int num);
SQLITE_API void SQLITE_APICALL RAND_add_p(const void *buf, int num, double randomness);

/* <openssl/hmac.h> */
SQLITE_API HMAC_CTX *SQLITE_APICALL HMAC_CTX_new_p(void);
SQLITE_API void SQLITE_APICALL HMAC_CTX_free_p(HMAC_CTX *ctx);
SQLITE_API int SQLITE_APICALL HMAC_Init_ex_p(HMAC_CTX *ctx, const void *key, int len, const EVP_MD *md, ENGINE *impl);
SQLITE_API int SQLITE_APICALL HMAC_Update_p(HMAC_CTX *ctx, const unsigned char *data, size_t len);
SQLITE_API int SQLITE_APICALL HMAC_Final_p(HMAC_CTX *ctx, unsigned char *md, unsigned int *len);

#ifdef  __cplusplus
} /* extern "C" { */
#endif

#endif /* CRYPTO_OPENSSL_PROXY_H */
