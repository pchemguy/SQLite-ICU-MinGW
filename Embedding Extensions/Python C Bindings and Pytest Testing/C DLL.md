---
url: https://chatgpt.com/c/6a6add0f-1f70-83eb-b67e-b8e80aaf9903
---

## 📗 DLL Source

> [!NOTE] Prompt
> 
> I need to make a standalone dll for CFFI exploration. Will this one work? Expand the code into a powerful exploration fixture.
> 
> ```c
> /*
> ** ctd.h
> */
> 
> int ctd_add(int a, int b);
> ```
> 
> ```c
> /*
> ** ctd.c
> */
> 
> #include "ctd.h"
> 
> int ctd_add(int a, int b) {
>     return a + b;
> }
> ```

> [!WARNING] Response
> 
> I’ll turn it into a C99 DLL fixture that exercises exports, scalars, pointers, arrays, buffers, strings, structs, callbacks, globals, allocation, and opaque handles.

Your original code can compile into a DLL, but **the function will not necessarily be exported on Windows**. A useful fixture should define an export macro and deliberately cover the main C constructs that CFFI must represent.

The following fixture remains compact and dependency-free while covering:

* scalar arguments and return values;
* fixed-width integer types;
* input, output, and in/out pointers;
* arrays and caller-provided buffers;
* borrowed and allocated strings;
* nullable pointers;
* library-allocated arrays;
* structs and unions;
* callbacks with user data;
* exported global variables;
* function pointers;
* opaque handles;
* explicit error reporting.

### `ctd.h`

```c
/*
** ctd.h
**
** Standalone C99 DLL fixture for exploring Python CFFI.
*/

#ifndef CTD_H
#define CTD_H

#include <stddef.h>
#include <stdint.h>

#if defined(CTD_STATIC)
# define CTD_API
#elif defined(_WIN32)
# if defined(CTD_BUILD_DLL)
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
CTD_API ctd_status ctd_sum_i32(
    const int32_t *values,
    size_t count,
    int64_t *result
);

CTD_API ctd_status ctd_scale_i32(
    int32_t *values,
    size_t count,
    int32_t factor
);

CTD_API ctd_status ctd_reverse_i32(
    int32_t *values,
    size_t count
);

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
CTD_API int32_t *ctd_alloc_sequence_i32(
    int32_t start,
    size_t count
);

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

CTD_API ctd_status ctd_xor_bytes(
    uint8_t *buffer,
    size_t count,
    uint8_t mask
);

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

CTD_API ctd_status ctd_ascii_upper(
    char *buffer,
    size_t capacity
);

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
CTD_API ctd_status ctd_point_translate(
    ctd_point *point,
    double dx,
    double dy
);

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
CTD_API ctd_status ctd_value_as_f64(
    const ctd_value *value,
    double *result
);

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

CTD_API ctd_binary_operation ctd_get_binary_operation(
    int selector
);

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
CTD_API ctd_status ctd_counter_get(
    const ctd_counter *counter,
    int *result
);
CTD_API ctd_status ctd_counter_add(
    ctd_counter *counter,
    int amount,
    int *result
);

/*
** Release memory returned by this library.
**
** Passing NULL is permitted.
*/
CTD_API void ctd_free(void *pointer);

#ifdef __cplusplus
}
#endif

#endif
```

### `ctd.c`

```c
/*
** ctd.c
**
** Standalone C99 DLL fixture for exploring Python CFFI.
*/

#define CTD_BUILD_DLL
#include "ctd.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

struct ctd_counter {
    int value;
};

CTD_API int ctd_global_counter = 0;
CTD_API const int ctd_global_constant = 1729;

const char *ctd_version(void){
    return "ctd 1.0";
}

const char *ctd_status_name(ctd_status status){
    switch(status){
        case CTD_OK:
            return "CTD_OK";
        case CTD_ERROR_NULL:
            return "CTD_ERROR_NULL";
        case CTD_ERROR_RANGE:
            return "CTD_ERROR_RANGE";
        case CTD_ERROR_CAPACITY:
            return "CTD_ERROR_CAPACITY";
        case CTD_ERROR_ALLOCATION:
            return "CTD_ERROR_ALLOCATION";
        case CTD_ERROR_DIVIDE_BY_ZERO:
            return "CTD_ERROR_DIVIDE_BY_ZERO";
        default:
            return "CTD_ERROR_UNKNOWN";
    }
}

int ctd_add(int a, int b){
    return a + b;
}

int ctd_subtract(int a, int b){
    return a - b;
}

int32_t ctd_negate_i32(int32_t value){
    return -value;
}

uint64_t ctd_add_u64(uint64_t a, uint64_t b){
    return a + b;
}

double ctd_hypot_squared(double x, double y){
    return x * x + y * y;
}

ctd_status ctd_divide(
    double numerator,
    double denominator,
    double *result
){
    if(result == NULL){
        return CTD_ERROR_NULL;
    }

    if(denominator == 0.0){
        return CTD_ERROR_DIVIDE_BY_ZERO;
    }

    *result = numerator / denominator;
    return CTD_OK;
}

ctd_status ctd_get_magic(int32_t *result){
    if(result == NULL){
        return CTD_ERROR_NULL;
    }

    *result = INT32_C(123456);
    return CTD_OK;
}

ctd_status ctd_increment(int32_t *value){
    if(value == NULL){
        return CTD_ERROR_NULL;
    }

    if(*value == INT32_MAX){
        return CTD_ERROR_RANGE;
    }

    *value += 1;
    return CTD_OK;
}

ctd_status ctd_swap_i32(int32_t *a, int32_t *b){
    int32_t temporary;

    if(a == NULL || b == NULL){
        return CTD_ERROR_NULL;
    }

    temporary = *a;
    *a = *b;
    *b = temporary;

    return CTD_OK;
}

ctd_status ctd_sum_i32(
    const int32_t *values,
    size_t count,
    int64_t *result
){
    size_t index;
    int64_t sum = 0;

    if(result == NULL){
        return CTD_ERROR_NULL;
    }

    if(values == NULL && count != 0){
        return CTD_ERROR_NULL;
    }

    for(index = 0; index < count; ++index){
        sum += values[index];
    }

    *result = sum;
    return CTD_OK;
}

ctd_status ctd_scale_i32(
    int32_t *values,
    size_t count,
    int32_t factor
){
    size_t index;

    if(values == NULL && count != 0){
        return CTD_ERROR_NULL;
    }

    for(index = 0; index < count; ++index){
        values[index] *= factor;
    }

    return CTD_OK;
}

ctd_status ctd_reverse_i32(
    int32_t *values,
    size_t count
){
    size_t left;
    size_t right;
    int32_t temporary;

    if(values == NULL && count != 0){
        return CTD_ERROR_NULL;
    }

    if(count < 2){
        return CTD_OK;
    }

    left = 0;
    right = count - 1;

    while(left < right){
        temporary = values[left];
        values[left] = values[right];
        values[right] = temporary;

        ++left;
        --right;
    }

    return CTD_OK;
}

ctd_status ctd_compute_stats_i32(
    const int32_t *values,
    size_t count,
    ctd_stats *result
){
    size_t index;
    int64_t sum;
    int32_t minimum;
    int32_t maximum;

    if(result == NULL){
        return CTD_ERROR_NULL;
    }

    if(values == NULL){
        return CTD_ERROR_NULL;
    }

    if(count == 0){
        return CTD_ERROR_RANGE;
    }

    minimum = values[0];
    maximum = values[0];
    sum = values[0];

    for(index = 1; index < count; ++index){
        if(values[index] < minimum){
            minimum = values[index];
        }

        if(values[index] > maximum){
            maximum = values[index];
        }

        sum += values[index];
    }

    result->count = count;
    result->minimum = minimum;
    result->maximum = maximum;
    result->sum = sum;
    result->mean = (double)sum / (double)count;

    return CTD_OK;
}

ctd_status ctd_make_sequence_i32(
    int32_t start,
    size_t count,
    int32_t *buffer,
    size_t capacity,
    size_t *required_count
){
    size_t index;

    if(required_count == NULL){
        return CTD_ERROR_NULL;
    }

    *required_count = count;

    if(count == 0){
        return CTD_OK;
    }

    if(buffer == NULL){
        return CTD_ERROR_CAPACITY;
    }

    if(capacity < count){
        return CTD_ERROR_CAPACITY;
    }

    for(index = 0; index < count; ++index){
        buffer[index] = start + (int32_t)index;
    }

    return CTD_OK;
}

int32_t *ctd_alloc_sequence_i32(
    int32_t start,
    size_t count
){
    int32_t *result;
    size_t index;

    if(count == 0){
        return NULL;
    }

    if(count > SIZE_MAX / sizeof(*result)){
        return NULL;
    }

    result = (int32_t *)malloc(count * sizeof(*result));

    if(result == NULL){
        return NULL;
    }

    for(index = 0; index < count; ++index){
        result[index] = start + (int32_t)index;
    }

    return result;
}

ctd_status ctd_copy_bytes(
    const uint8_t *source,
    size_t source_count,
    uint8_t *destination,
    size_t destination_capacity,
    size_t *required_count
){
    if(required_count == NULL){
        return CTD_ERROR_NULL;
    }

    *required_count = source_count;

    if(source == NULL && source_count != 0){
        return CTD_ERROR_NULL;
    }

    if(source_count == 0){
        return CTD_OK;
    }

    if(destination == NULL || destination_capacity < source_count){
        return CTD_ERROR_CAPACITY;
    }

    memcpy(destination, source, source_count);
    return CTD_OK;
}

ctd_status ctd_xor_bytes(
    uint8_t *buffer,
    size_t count,
    uint8_t mask
){
    size_t index;

    if(buffer == NULL && count != 0){
        return CTD_ERROR_NULL;
    }

    for(index = 0; index < count; ++index){
        buffer[index] ^= mask;
    }

    return CTD_OK;
}

size_t ctd_string_length(const char *text){
    if(text == NULL){
        return 0;
    }

    return strlen(text);
}

const char *ctd_select_static_string(int selector){
    switch(selector){
        case 0:
            return "zero";
        case 1:
            return "one";
        case 2:
            return "";
        default:
            return NULL;
    }
}

char *ctd_alloc_greeting(const char *name){
    static const char prefix[] = "Hello, ";
    static const char suffix[] = "!";
    size_t prefix_size = sizeof(prefix) - 1;
    size_t suffix_size = sizeof(suffix) - 1;
    size_t name_size;
    size_t total_size;
    char *result;

    if(name == NULL){
        return NULL;
    }

    name_size = strlen(name);

    if(name_size > SIZE_MAX - prefix_size - suffix_size - 1){
        return NULL;
    }

    total_size = prefix_size + name_size + suffix_size + 1;
    result = (char *)malloc(total_size);

    if(result == NULL){
        return NULL;
    }

    memcpy(result, prefix, prefix_size);
    memcpy(result + prefix_size, name, name_size);
    memcpy(result + prefix_size + name_size, suffix, suffix_size);
    result[total_size - 1] = '\0';

    return result;
}

ctd_status ctd_ascii_upper(
    char *buffer,
    size_t capacity
){
    size_t index;

    if(buffer == NULL){
        return CTD_ERROR_NULL;
    }

    for(index = 0; index < capacity; ++index){
        unsigned char character = (unsigned char)buffer[index];

        if(character == '\0'){
            return CTD_OK;
        }

        if(character >= 'a' && character <= 'z'){
            buffer[index] = (char)(character - 'a' + 'A');
        }
    }

    return CTD_ERROR_CAPACITY;
}

ctd_status ctd_copy_string(
    const char *source,
    char *destination,
    size_t destination_capacity,
    size_t *required_size
){
    size_t size;

    if(source == NULL || required_size == NULL){
        return CTD_ERROR_NULL;
    }

    size = strlen(source) + 1;
    *required_size = size;

    if(destination == NULL || destination_capacity < size){
        return CTD_ERROR_CAPACITY;
    }

    memcpy(destination, source, size);
    return CTD_OK;
}

ctd_point ctd_point_make(double x, double y){
    ctd_point result;

    result.x = x;
    result.y = y;

    return result;
}

ctd_point ctd_point_add(ctd_point a, ctd_point b){
    ctd_point result;

    result.x = a.x + b.x;
    result.y = a.y + b.y;

    return result;
}

double ctd_point_dot(const ctd_point *a, const ctd_point *b){
    if(a == NULL || b == NULL){
        return 0.0;
    }

    return a->x * b->x + a->y * b->y;
}

ctd_status ctd_point_translate(
    ctd_point *point,
    double dx,
    double dy
){
    if(point == NULL){
        return CTD_ERROR_NULL;
    }

    point->x += dx;
    point->y += dy;

    return CTD_OK;
}

ctd_status ctd_record_initialize(
    ctd_record *record,
    int32_t id,
    const char *name
){
    size_t name_size;

    if(record == NULL || name == NULL){
        return CTD_ERROR_NULL;
    }

    name_size = strlen(name);

    if(name_size >= sizeof(record->name)){
        return CTD_ERROR_CAPACITY;
    }

    record->id = id;

    memset(record->name, 0, sizeof(record->name));
    memcpy(record->name, name, name_size);

    record->values[0] = 1.0;
    record->values[1] = 2.0;
    record->values[2] = 3.0;

    return CTD_OK;
}

ctd_value ctd_value_from_i64(int64_t value){
    ctd_value result;

    result.kind = CTD_NUMBER_I64;
    result.number.i64 = value;

    return result;
}

ctd_value ctd_value_from_f64(double value){
    ctd_value result;

    result.kind = CTD_NUMBER_F64;
    result.number.f64 = value;

    return result;
}

ctd_status ctd_value_as_f64(
    const ctd_value *value,
    double *result
){
    if(value == NULL || result == NULL){
        return CTD_ERROR_NULL;
    }

    switch(value->kind){
        case CTD_NUMBER_I64:
            *result = (double)value->number.i64;
            return CTD_OK;

        case CTD_NUMBER_F64:
            *result = value->number.f64;
            return CTD_OK;

        default:
            return CTD_ERROR_RANGE;
    }
}

ctd_status ctd_apply_callback(
    int left,
    int right,
    ctd_binary_callback callback,
    void *user_data,
    int *result
){
    if(callback == NULL || result == NULL){
        return CTD_ERROR_NULL;
    }

    *result = callback(left, right, user_data);
    return CTD_OK;
}

static int ctd_operation_add(int left, int right){
    return left + right;
}

static int ctd_operation_multiply(int left, int right){
    return left * right;
}

ctd_binary_operation ctd_get_binary_operation(
    int selector
){
    switch(selector){
        case 0:
            return ctd_operation_add;
        case 1:
            return ctd_operation_multiply;
        default:
            return NULL;
    }
}

int ctd_global_counter_increment(void){
    ctd_global_counter += 1;
    return ctd_global_counter;
}

void ctd_global_counter_reset(void){
    ctd_global_counter = 0;
}

ctd_counter *ctd_counter_create(int initial_value){
    ctd_counter *counter;

    counter = (ctd_counter *)malloc(sizeof(*counter));

    if(counter == NULL){
        return NULL;
    }

    counter->value = initial_value;
    return counter;
}

void ctd_counter_destroy(ctd_counter *counter){
    free(counter);
}

ctd_status ctd_counter_get(
    const ctd_counter *counter,
    int *result
){
    if(counter == NULL || result == NULL){
        return CTD_ERROR_NULL;
    }

    *result = counter->value;
    return CTD_OK;
}

ctd_status ctd_counter_add(
    ctd_counter *counter,
    int amount,
    int *result
){
    if(counter == NULL || result == NULL){
        return CTD_ERROR_NULL;
    }

    counter->value += amount;
    *result = counter->value;

    return CTD_OK;
}

void ctd_free(void *pointer){
    free(pointer);
}
```

### Build with MSVC

Run from an MSVC developer command prompt:

```bat
cl /nologo /W4 /O2 /LD /TC ctd.c /Fe:ctd.dll
```

This produces approximately:

```text
ctd.dll
ctd.lib
ctd.exp
ctd.obj
```

`/TC` explicitly compiles the source as C rather than C++.

To inspect the exported symbols:

```bat
dumpbin /exports ctd.dll
```

### Build with GCC or MinGW

```bat
gcc -std=c99 -Wall -Wextra -pedantic -O2 -shared -o ctd.dll ctd.c
```

On platforms where symbol visibility defaults to hidden, the `CTD_API` definition ensures that the public symbols remain visible.

### Important CFFI distinctions exposed by the fixture

The fixture deliberately includes three different pointer-ownership cases:

| Function                     | Returned pointer | Ownership                        |
| ---------------------------- | ---------------- | -------------------------------- |
| `ctd_select_static_string()` | `const char *`   | Borrowed; never free             |
| `ctd_alloc_greeting()`       | `char *`         | Owned; release with `ctd_free()` |
| `ctd_alloc_sequence_i32()`   | `int32_t *`      | Owned; release with `ctd_free()` |

It also distinguishes:

* `const int32_t *values`: input array;
* `int32_t *values`: mutable in/out array;
* `double *result`: scalar output;
* `char *buffer, size_t capacity`: caller-owned buffer;
* `ctd_counter *`: opaque library object;
* `void *user_data`: uninterpreted callback context.

These semantics are **not inferable from C declarations alone**. CFFI can represent the declarations, but wrapper-generation policy still needs metadata or manually written Python logic for direction, capacity, ownership, nullability, string encoding, and error interpretation.

---
---
