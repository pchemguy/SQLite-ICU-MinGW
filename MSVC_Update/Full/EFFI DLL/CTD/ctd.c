/*
** ctd.c
**
** Standalone C99 DLL fixture for exploring Python CFFI.
*/

#include "ctd.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

struct ctd_counter {
    int value;
};

CTD_API extern int ctd_global_counter = 0;
CTD_API extern const int ctd_global_constant = 1729;

CTD_API const char *ctd_version(void) {
    return "ctd 1.0";
}

CTD_API const char *ctd_status_name(ctd_status status) {
    switch (status) {
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

CTD_API int ctd_add(int a, int b) {
    return a + b;
}

CTD_API int ctd_subtract(int a, int b) {
    return a - b;
}

CTD_API int32_t ctd_negate_i32(int32_t value) {
    return -value;
}

CTD_API uint64_t ctd_add_u64(uint64_t a, uint64_t b) {
    return a + b;
}

CTD_API double ctd_hypot_squared(double x, double y) {
    return x * x + y * y;
}

CTD_API ctd_status ctd_divide(double numerator, double denominator, double *result) {
    if (result == NULL) {
        return CTD_ERROR_NULL;
    }

    if (denominator == 0.0) {
        return CTD_ERROR_DIVIDE_BY_ZERO;
    }

    *result = numerator / denominator;
    return CTD_OK;
}

CTD_API ctd_status ctd_get_magic(int32_t *result) {
    if (result == NULL) {
        return CTD_ERROR_NULL;
    }

    *result = INT32_C(123456);
    return CTD_OK;
}

CTD_API ctd_status ctd_increment(int32_t *value) {
    if (value == NULL) {
        return CTD_ERROR_NULL;
    }

    if (*value == INT32_MAX) {
        return CTD_ERROR_RANGE;
    }

    *value += 1;
    return CTD_OK;
}

CTD_API ctd_status ctd_swap_i32(int32_t *a, int32_t *b) {
    int32_t temporary;

    if (a == NULL || b == NULL) {
        return CTD_ERROR_NULL;
    }

    temporary = *a;
    *a = *b;
    *b = temporary;

    return CTD_OK;
}

CTD_API ctd_status ctd_sum_i32(const int32_t *values, size_t count, int64_t *result) {
    size_t index;
    int64_t sum = 0;

    if (result == NULL) {
        return CTD_ERROR_NULL;
    }

    if (values == NULL && count != 0) {
        return CTD_ERROR_NULL;
    }

    for (index = 0; index < count; ++index) {
        sum += values[index];
    }

    *result = sum;
    return CTD_OK;
}

CTD_API ctd_status ctd_scale_i32(int32_t *values, size_t count, int32_t factor) {
    size_t index;

    if (values == NULL && count != 0) {
        return CTD_ERROR_NULL;
    }

    for (index = 0; index < count; ++index) {
        values[index] *= factor;
    }

    return CTD_OK;
}

CTD_API ctd_status ctd_reverse_i32(int32_t *values, size_t count) {
    size_t left;
    size_t right;
    int32_t temporary;

    if (values == NULL && count != 0) {
        return CTD_ERROR_NULL;
    }

    if (count < 2) {
        return CTD_OK;
    }

    left = 0;
    right = count - 1;

    while (left < right) {
        temporary = values[left];
        values[left] = values[right];
        values[right] = temporary;

        ++left;
        --right;
    }

    return CTD_OK;
}

CTD_API ctd_status ctd_compute_stats_i32(
    const int32_t *values,
    size_t count,
    ctd_stats *result
) {
    size_t index;
    int64_t sum;
    int32_t minimum;
    int32_t maximum;

    if (result == NULL) {
        return CTD_ERROR_NULL;
    }

    if (values == NULL) {
        return CTD_ERROR_NULL;
    }

    if (count == 0) {
        return CTD_ERROR_RANGE;
    }

    minimum = values[0];
    maximum = values[0];
    sum = values[0];

    for (index = 1; index < count; ++index) {
        if (values[index] < minimum) {
            minimum = values[index];
        }

        if (values[index] > maximum) {
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

CTD_API ctd_status ctd_make_sequence_i32(
    int32_t start,
    size_t count,
    int32_t *buffer,
    size_t capacity,
    size_t *required_count
) {
    size_t index;

    if (required_count == NULL) {
        return CTD_ERROR_NULL;
    }

    *required_count = count;

    if (count == 0) {
        return CTD_OK;
    }

    if (buffer == NULL) {
        return CTD_ERROR_CAPACITY;
    }

    if (capacity < count) {
        return CTD_ERROR_CAPACITY;
    }

    for (index = 0; index < count; ++index) {
        buffer[index] = start + (int32_t)index;
    }

    return CTD_OK;
}

CTD_API int32_t *ctd_alloc_sequence_i32(int32_t start, size_t count) {
    int32_t *result;
    size_t index;

    if (count == 0) {
        return NULL;
    }

    if (count > SIZE_MAX / sizeof(*result)) {
        return NULL;
    }

    result = (int32_t *)malloc(count * sizeof(*result));

    if (result == NULL) {
        return NULL;
    }

    for (index = 0; index < count; ++index) {
        result[index] = start + (int32_t)index;
    }

    return result;
}

CTD_API ctd_status ctd_copy_bytes(
    const uint8_t *source,
    size_t source_count,
    uint8_t *destination,
    size_t destination_capacity,
    size_t *required_count
) {
    if (required_count == NULL) {
        return CTD_ERROR_NULL;
    }

    *required_count = source_count;

    if (source == NULL && source_count != 0) {
        return CTD_ERROR_NULL;
    }

    if (source_count == 0) {
        return CTD_OK;
    }

    if (destination == NULL || destination_capacity < source_count) {
        return CTD_ERROR_CAPACITY;
    }

    memcpy(destination, source, source_count);
    return CTD_OK;
}

CTD_API ctd_status ctd_xor_bytes(uint8_t *buffer, size_t count, uint8_t mask) {
    size_t index;

    if (buffer == NULL && count != 0) {
        return CTD_ERROR_NULL;
    }

    for (index = 0; index < count; ++index) {
        buffer[index] ^= mask;
    }

    return CTD_OK;
}

CTD_API size_t ctd_string_length(const char *text) {
    if (text == NULL) {
        return 0;
    }

    return strlen(text);
}

CTD_API const char *ctd_select_static_string(int selector) {
    switch (selector) {
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

CTD_API char *ctd_alloc_greeting(const char *name) {
    static const char prefix[] = "Hello, ";
    static const char suffix[] = "!";
    size_t prefix_size = sizeof(prefix) - 1;
    size_t suffix_size = sizeof(suffix) - 1;
    size_t name_size;
    size_t total_size;
    char *result;

    if (name == NULL) {
        return NULL;
    }

    name_size = strlen(name);

    if (name_size > SIZE_MAX - prefix_size - suffix_size - 1) {
        return NULL;
    }

    total_size = prefix_size + name_size + suffix_size + 1;
    result = (char *)malloc(total_size);

    if (result == NULL) {
        return NULL;
    }

    memcpy(result, prefix, prefix_size);
    memcpy(result + prefix_size, name, name_size);
    memcpy(result + prefix_size + name_size, suffix, suffix_size);
    result[total_size - 1] = '\0';

    return result;
}

CTD_API ctd_status ctd_ascii_upper(char *buffer, size_t capacity) {
    size_t index;

    if (buffer == NULL) {
        return CTD_ERROR_NULL;
    }

    for (index = 0; index < capacity; ++index) {
        unsigned char character = (unsigned char)buffer[index];

        if (character == '\0') {
            return CTD_OK;
        }

        if (character >= 'a' && character <= 'z') {
            buffer[index] = (char)(character - 'a' + 'A');
        }
    }

    return CTD_ERROR_CAPACITY;
}

CTD_API ctd_status ctd_copy_string(
    const char *source,
    char *destination,
    size_t destination_capacity,
    size_t *required_size
) {
    size_t size;

    if (source == NULL || required_size == NULL) {
        return CTD_ERROR_NULL;
    }

    size = strlen(source) + 1;
    *required_size = size;

    if (destination == NULL || destination_capacity < size) {
        return CTD_ERROR_CAPACITY;
    }

    memcpy(destination, source, size);
    return CTD_OK;
}

CTD_API ctd_point ctd_point_make(double x, double y) {
    ctd_point result;

    result.x = x;
    result.y = y;

    return result;
}

CTD_API ctd_point ctd_point_add(ctd_point a, ctd_point b) {
    ctd_point result;

    result.x = a.x + b.x;
    result.y = a.y + b.y;

    return result;
}

CTD_API double ctd_point_dot(const ctd_point *a, const ctd_point *b) {
    if (a == NULL || b == NULL) {
        return 0.0;
    }

    return a->x * b->x + a->y * b->y;
}

CTD_API ctd_status ctd_point_translate(ctd_point *point, double dx, double dy) {
    if (point == NULL) {
        return CTD_ERROR_NULL;
    }

    point->x += dx;
    point->y += dy;

    return CTD_OK;
}

CTD_API ctd_status ctd_record_initialize(
    ctd_record *record,
    int32_t id,
    const char *name
) {
    size_t name_size;

    if (record == NULL || name == NULL) {
        return CTD_ERROR_NULL;
    }

    name_size = strlen(name);

    if (name_size >= sizeof(record->name)) {
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

CTD_API ctd_value ctd_value_from_i64(int64_t value) {
    ctd_value result;

    result.kind = CTD_NUMBER_I64;
    result.number.i64 = value;

    return result;
}

CTD_API ctd_value ctd_value_from_f64(double value) {
    ctd_value result;

    result.kind = CTD_NUMBER_F64;
    result.number.f64 = value;

    return result;
}

CTD_API ctd_status ctd_value_as_f64(const ctd_value *value, double *result) {
    if (value == NULL || result == NULL) {
        return CTD_ERROR_NULL;
    }

    switch (value->kind) {
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

CTD_API ctd_status ctd_apply_callback(
    int left,
    int right,
    ctd_binary_callback callback,
    void *user_data,
    int *result
) {
    if (callback == NULL || result == NULL) {
        return CTD_ERROR_NULL;
    }

    *result = callback(left, right, user_data);
    return CTD_OK;
}

CTD_API int ctd_operation_add(int left, int right) {
    return left + right;
}

CTD_API int ctd_operation_multiply(int left, int right) {
    return left * right;
}

CTD_API ctd_binary_operation ctd_get_binary_operation(int selector) {
    switch (selector) {
        case 0:
            return ctd_operation_add;
        case 1:
            return ctd_operation_multiply;
        default:
            return NULL;
    }
}

CTD_API int ctd_global_counter_increment(void) {
    ctd_global_counter += 1;
    return ctd_global_counter;
}

CTD_API void ctd_global_counter_reset(void) {
    ctd_global_counter = 0;
}

CTD_API ctd_counter *ctd_counter_create(int initial_value) {
    ctd_counter *counter;

    counter = (ctd_counter *)malloc(sizeof(*counter));

    if (counter == NULL) {
        return NULL;
    }

    counter->value = initial_value;
    return counter;
}

CTD_API void ctd_counter_destroy(ctd_counter *counter) {
    free(counter);
}

CTD_API ctd_status ctd_counter_get(const ctd_counter *counter, int *result) {
    if (counter == NULL || result == NULL) {
        return CTD_ERROR_NULL;
    }

    *result = counter->value;
    return CTD_OK;
}

CTD_API ctd_status ctd_counter_add(ctd_counter *counter, int amount, int *result) {
    if (counter == NULL || result == NULL) {
        return CTD_ERROR_NULL;
    }

    counter->value += amount;
    *result = counter->value;

    return CTD_OK;
}

CTD_API void ctd_free(void *pointer) {
    free(pointer);
}
