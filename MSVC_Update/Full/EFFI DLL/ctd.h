/*
** ctd.h
**
** Standalone C99 DLL fixture for exploring Python CFFI.
*/

#ifndef CTD_H
#define CTD_H

#include <stddef.h>
#include <stdint.h>

#ifdef CTD_STATIC
# define CTD_API
#elif defined(_WIN32)
# ifdef CTD_BUILD_DLL
#  define CTD_API __declspec(dllexport)
# else
#  define CTD_API __declspec(dllimport)
# endif
#elif defined(__GNUC__) || defined(__clang__)
# define CTD_API __attribute__((visibility("default")))
#else
# define CTD_API
#endif

#ifdef __cplusplus
extern "C" {
#endif


/*
** Constants.
*/
#define LATIN \
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ" \
  "abcdefghijklmnopqrstuvwxyz"

/*
** Error codes.
*/
typedef enum ctd_status {
    CTD_OK = 0,
    CTD_ERROR_NULL = 1,
    CTD_ERROR_RANGE = 2,
    CTD_ERROR_CAPACITY = 3,
    CTD_ERROR_ALLOCATION = 4,
    CTD_ERROR_DIVIDE_BY_ZERO = 5
} ctd_status;

/*
** A simple structure suitable for passing by value.
*/
typedef struct ctd_point {
    double x;
    double y;
} ctd_point;

/*
** A structure populated through an output pointer.
*/
typedef struct ctd_stats {
    size_t count;
    int32_t minimum;
    int32_t maximum;
    int64_t sum;
    double mean;
} ctd_stats;

/*
** A structure containing fixed-size arrays.
*/
typedef struct ctd_record {
    int32_t id;
    char name[16];
    double values[3];
} ctd_record;

/*
** Tagged union.
*/
typedef union ctd_number {
    int64_t i64;
    double f64;
} ctd_number;

typedef enum ctd_number_kind {
    CTD_NUMBER_I64 = 1,
    CTD_NUMBER_F64 = 2
} ctd_number_kind;

typedef struct ctd_value {
    ctd_number_kind kind;
    ctd_number number;
} ctd_value;

/*
** Callback types.
*/
typedef int (*ctd_binary_callback)(
    int left,
    int right,
    void *user_data
);

typedef int (*ctd_binary_operation)(
    int left,
    int right
);

/*
** Opaque handle.
*/
typedef struct ctd_counter ctd_counter;

/*
** Exported global variables.
*/
CTD_API extern int ctd_global_counter;
CTD_API extern const int ctd_global_constant;

/*
** General information and error handling.
*/
CTD_API const char *ctd_version(void);
CTD_API const char *ctd_status_name(ctd_status status);

/*
** Scalar operations.
*/
CTD_API int ctd_add(int a, int b);
CTD_API int ctd_subtract(int a, int b);
CTD_API int32_t ctd_negate_i32(int32_t value);
CTD_API uint64_t ctd_add_u64(uint64_t a, uint64_t b);
CTD_API double ctd_hypot_squared(double x, double y);

CTD_API ctd_status ctd_divide(
    double numerator,
    double denominator,
    double *result
);

/*
** Scalar pointer operations.
*/
CTD_API ctd_status ctd_get_magic(int32_t *result);
CTD_API ctd_status ctd_increment(int32_t *value);
CTD_API ctd_status ctd_swap_i32(int32_t *a, int32_t *b);

/*
** Arrays.
**
** Array lengths are expressed in typed elements, not bytes.
*/
CTD_API ctd_status ctd_sum_i32(const int32_t *values, size_t count, int64_t *result);

CTD_API ctd_status ctd_scale_i32(int32_t *values, size_t count, int32_t factor);

CTD_API ctd_status ctd_reverse_i32(int32_t *values, size_t count);

CTD_API ctd_status ctd_compute_stats_i32(
    const int32_t *values,
    size_t count,
    ctd_stats *result
);

/*
** Caller-provided output buffer.
**
** The function returns the number of elements required in required_count.
** It writes data only when capacity is sufficient.
*/
CTD_API ctd_status ctd_make_sequence_i32(
    int32_t start,
    size_t count,
    int32_t *buffer,
    size_t capacity,
    size_t *required_count
);

/*
** Library-allocated array.
**
** The returned array must be released with ctd_free().
*/
CTD_API int32_t *ctd_alloc_sequence_i32(int32_t start, size_t count);

/*
** Byte buffers.
*/
CTD_API ctd_status ctd_copy_bytes(
    const uint8_t *source,
    size_t source_count,
    uint8_t *destination,
    size_t destination_capacity,
    size_t *required_count
);

CTD_API ctd_status ctd_xor_bytes(uint8_t *buffer, size_t count, uint8_t mask);

/*
** Strings.
**
** ctd_select_static_string() returns borrowed library memory.
** The returned pointer must not be freed.
**
** ctd_alloc_greeting() returns allocated memory.
** The returned pointer must be released with ctd_free().
*/
CTD_API size_t ctd_string_length(const char *text);
CTD_API const char *ctd_select_static_string(int selector);
CTD_API char *ctd_alloc_greeting(const char *name);

CTD_API ctd_status ctd_ascii_upper(char *buffer, size_t capacity);

CTD_API ctd_status ctd_copy_string(
    const char *source,
    char *destination,
    size_t destination_capacity,
    size_t *required_size
);

/*
** Structure operations.
*/
CTD_API ctd_point ctd_point_make(double x, double y);
CTD_API ctd_point ctd_point_add(ctd_point a, ctd_point b);
CTD_API double ctd_point_dot(const ctd_point *a, const ctd_point *b);
CTD_API ctd_status ctd_point_translate(ctd_point *point, double dx, double dy);

CTD_API ctd_status ctd_record_initialize(
    ctd_record *record,
    int32_t id,
    const char *name
);

/*
** Tagged-union operations.
*/
CTD_API ctd_value ctd_value_from_i64(int64_t value);
CTD_API ctd_value ctd_value_from_f64(double value);
CTD_API ctd_status ctd_value_as_f64(const ctd_value *value, double *result);

/*
** Callback and function-pointer operations.
*/
CTD_API ctd_status ctd_apply_callback(
    int left,
    int right,
    ctd_binary_callback callback,
    void *user_data,
    int *result
);

CTD_API ctd_binary_operation ctd_get_binary_operation(int selector);

/*
** Exported-global operations.
*/
CTD_API int ctd_global_counter_increment(void);
CTD_API void ctd_global_counter_reset(void);

/*
** Opaque counter operations.
*/
CTD_API ctd_counter *ctd_counter_create(int initial_value);
CTD_API void ctd_counter_destroy(ctd_counter *counter);
CTD_API ctd_status ctd_counter_get(const ctd_counter *counter, int *result);
CTD_API ctd_status ctd_counter_add(ctd_counter *counter, int amount, int *result);

/*
** Release memory returned by this library.
**
** Passing NULL is permitted.
*/
CTD_API void ctd_free(void *pointer);

#ifdef __cplusplus
}
#endif

#endif /* CTD_H */
