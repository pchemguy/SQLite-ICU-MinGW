---
url: https://chatgpt.com/c/6a6add0f-1f70-83eb-b67e-b8e80aaf9903
---

## 📗 Introspection via `lib`

> [!NOTE] Prompt
> 
> Ok, so I have ctd ext built.  Now, how can use lib to verify that specific global constants name are defined and verify their values?

Use normal Python attribute inspection on `lib`.

For a single constant:

```python
name = "CTD_OK"
expected = 0

assert hasattr(lib, name), f"{name} is not defined"
actual = getattr(lib, name)

assert isinstance(actual, int)
assert actual == expected, f"{name}: expected {expected}, got {actual}"
```

For several constants:

```python
EXPECTED_CONSTANTS = {
    "CTD_OK": 0,
    "CTD_ERROR_NULL": 1,
    "CTD_ERROR_RANGE": 2,
    "CTD_ERROR_CAPACITY": 3,
    "CTD_ERROR_ALLOCATION": 4,
    "CTD_ERROR_DIVIDE_BY_ZERO": 5,
}


for name, expected in EXPECTED_CONSTANTS.items():
    assert hasattr(lib, name), f"{name} is not defined"

    actual = getattr(lib, name)

    assert isinstance(actual, int), (
        f"{name} should be a Python int, got {type(actual).__name__}"
    )
    assert actual == expected, (
        f"{name}: expected {expected}, got {actual}"
    )
```

A reusable helper:

```python
def assert_lib_constant(name: str, expected: int) -> None:
    try:
        actual = getattr(lib, name)
    except AttributeError as exc:
        raise AssertionError(f"{name} is not defined by the CFFI lib object") from exc

    assert isinstance(actual, int), (
        f"{name} should be a Python int, got {type(actual).__name__}"
    )
    assert actual == expected, (
        f"{name}: expected {expected}, got {actual}"
    )
```

Usage:

```python
assert_lib_constant("CTD_OK", 0)
assert_lib_constant("CTD_ERROR_NULL", 1)
```

For discovering names:

```python
names = [name for name in dir(lib) if name.startswith("CTD_")]
print(names)
```

But `dir(lib)` is useful for inspection, not the strongest test. For verification, `getattr()` plus `AttributeError` handling is better because it directly tests the exact required name.

---
---

## 📗 Pytest Patterns

> [!NOTE] Prompt
> 
> I do not need an exception this code will be used by pytest in bulk. It will be pytest's responsibility to provide feedback.

Then keep it direct:

```python
EXPECTED_CONSTANTS = {
    "CTD_OK": 0,
    "CTD_ERROR_NULL": 1,
    "CTD_ERROR_RANGE": 2,
    "CTD_ERROR_CAPACITY": 3,
    "CTD_ERROR_ALLOCATION": 4,
    "CTD_ERROR_DIVIDE_BY_ZERO": 5,
}


def test_constants() -> None:
    for name, expected in EXPECTED_CONSTANTS.items():
        assert getattr(lib, name) == expected
```

For better pytest parameterization:

```python
import pytest


@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("CTD_OK", 0),
        ("CTD_ERROR_NULL", 1),
        ("CTD_ERROR_RANGE", 2),
        ("CTD_ERROR_CAPACITY", 3),
        ("CTD_ERROR_ALLOCATION", 4),
        ("CTD_ERROR_DIVIDE_BY_ZERO", 5),
    ],
)
def test_constant(name: str, expected: int) -> None:
    assert getattr(lib, name) == expected
```

A missing attribute already causes pytest to report `AttributeError`, and a wrong value produces an assertion failure.

---
---

## 📗 Global Variables

> [!NOTE] Prompt
> 
> Now, global vars: names and initial values, not necessarily strict equality. This includes numeric scalars, strings, and structs.

Use a table of global names plus validator functions. `getattr(lib, name)` verifies that the symbol exists; the validator checks the initial value without requiring universal equality semantics.

```python
from collections.abc import Callable
from typing import Any

import pytest

from _ctd_wrapper import ffi, lib


GlobalValidator = Callable[[Any], bool]


GLOBAL_CASES: list[tuple[str, GlobalValidator]] = [
    # Numeric scalars
    ("ctd_global_counter", lambda value: value == 0),
    ("ctd_global_constant", lambda value: value > 0),

    # NUL-terminated string pointer or character array
    ("ctd_global_name", lambda value: ffi.string(value) == b"ctd"),

    # Structure
    (
        "ctd_global_point",
        lambda value: value.x == 2.0 and value.y == 3.0,
    ),
]


@pytest.mark.parametrize(("name", "validator"), GLOBAL_CASES)
def test_global_initial_value(
    name: str,
    validator: GlobalValidator,
) -> None:
    value = getattr(lib, name)
    assert validator(value)
```

A missing global naturally produces `AttributeError`; a bad initial value produces an ordinary assertion failure.

### Prefer dedicated validators

For readable bulk tests:

```python
from typing import Any


def is_zero(value: Any) -> bool:
    return value == 0


def is_positive_integer(value: Any) -> bool:
    return isinstance(value, int) and value > 0


def is_ctd_string(value: Any) -> bool:
    return value != ffi.NULL and ffi.string(value) == b"ctd"


def is_initial_point(value: Any) -> bool:
    return value.x == 2.0 and value.y == 3.0
```

```python
GLOBAL_CASES = [
    ("ctd_global_counter", is_zero),
    ("ctd_global_constant", is_positive_integer),
    ("ctd_global_name", is_ctd_string),
    ("ctd_global_point", is_initial_point),
]
```

### Better pytest IDs

```python
@pytest.mark.parametrize(
    ("name", "validator"),
    GLOBAL_CASES,
    ids=[name for name, _ in GLOBAL_CASES],
)
def test_global_initial_value(name: str, validator: GlobalValidator) -> None:
    assert validator(getattr(lib, name))
```

Pytest will report cases individually:

```text
test_global_initial_value[ctd_global_counter]
test_global_initial_value[ctd_global_constant]
test_global_initial_value[ctd_global_name]
test_global_initial_value[ctd_global_point]
```

### Different string global forms

These C declarations require slightly different checks.

#### Character pointer

```c
extern const char *ctd_global_name;
```

```python
def is_ctd_string(value: Any) -> bool:
    return value != ffi.NULL and ffi.string(value) == b"ctd"
```

#### Fixed character array

```c
extern const char ctd_global_name[16];
```

The same conversion works:

```python
ffi.string(value)
```

#### Nullable string

```python
def is_null_string(value: Any) -> bool:
    return value == ffi.NULL
```

or:

```python
def is_optional_ctd_string(value: Any) -> bool:
    return value == ffi.NULL or ffi.string(value) == b"ctd"
```

### Structures

For:

```c
extern ctd_point ctd_global_point;
```

CFFI exposes a struct cdata value, so inspect its fields directly:

```python
def is_initial_point(value: Any) -> bool:
    return (
        value.x == pytest.approx(2.0)
        and value.y == pytest.approx(3.0)
    )
```

For floating-point fields, `pytest.approx()` is preferable to exact equality:

```python
def is_initial_stats(value: Any) -> bool:
    return (
        value.count == 3
        and value.minimum == 1
        and value.maximum == 5
        and value.sum == 9
        and value.mean == pytest.approx(3.0)
    )
```

### Declarative expected values

Another useful design is to separate extraction from comparison:

```python
GLOBAL_CASES = [
    ("ctd_global_counter", lambda value: value, 0),
    ("ctd_global_constant", lambda value: value, 1729),
    ("ctd_global_name", ffi.string, b"ctd"),
    (
        "ctd_global_point",
        lambda value: (value.x, value.y),
        pytest.approx((2.0, 3.0)),
    ),
]


@pytest.mark.parametrize(
    ("name", "extract", "expected"),
    GLOBAL_CASES,
    ids=[case[0] for case in GLOBAL_CASES],
)
def test_global_initial_value(
    name: str,
    extract: Callable[[Any], Any],
    expected: Any,
) -> None:
    assert extract(getattr(lib, name)) == expected
```

This is preferable when each global has a definite expected representation. Use predicate validators when the accepted initial state is a range, set, structural condition, nullable alternative, or other non-equality contract.

One important requirement: these tests must run before any test mutates the globals, or each mutating test must restore the original state. Initial-value tests are otherwise order-dependent.

---
---

## 📗 Enum Values - C vs. Python

> [!NOTE] Prompt
> 
> With enumes, how do I amend parametrization such that instead of hard coding individual values, a python enum class mirroring the target c enum is used instead for both names and values?

Use the Python `IntEnum` itself as the parameter source. Each member gives you both the C symbol name and expected integer value.

```python
from enum import IntEnum

import pytest

from _ctd_wrapper import lib


class CtdStatus(IntEnum):
    CTD_OK = 0
    CTD_ERROR_NULL = 1
    CTD_ERROR_RANGE = 2
    CTD_ERROR_CAPACITY = 3
    CTD_ERROR_ALLOCATION = 4
    CTD_ERROR_DIVIDE_BY_ZERO = 5
```

Then parametrize directly over the enum members:

```python
@pytest.mark.parametrize("member", CtdStatus)
def test_ctd_status_constant(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

Pytest will generate one case per member.

For clearer test IDs:

```python
@pytest.mark.parametrize(
    "member",
    list(CtdStatus),
    ids=lambda member: member.name,
)
def test_ctd_status_constant(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

You can also unpack name and value during parametrization:

```python
@pytest.mark.parametrize(
    ("name", "expected"),
    [(member.name, member.value) for member in CtdStatus],
)
def test_ctd_status_constant(name: str, expected: int) -> None:
    assert getattr(lib, name) == expected
```

The first form is cleaner because the enum remains the single authoritative Python mirror:

```python
@pytest.mark.parametrize(
    "member",
    CtdStatus,
    ids=lambda member: member.name,
)
def test_ctd_status_constant(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member
```

That last assertion works because `IntEnum` members compare equal to their underlying integer values. I would still prefer `.value` for explicitness:

```python
assert getattr(lib, member.name) == member.value
```

---
---

## 📗 Enum Type

> [!NOTE] Prompt
> 
> Is enum type exposed on lib to also  verify its name? I mean, if I access enum members in c, I also need to use enum name?

No. CFFI does **not** expose the enum type name as `lib.ctd_status`.

`lib` exposes runtime C symbols and constants, such as:

```python
lib.CTD_OK
lib.CTD_ERROR_NULL
```

The type is accessed through `ffi`:

```python
enum_type = ffi.typeof("ctd_status")

assert enum_type.kind == "enum"
assert enum_type.cname == "ctd_status"
```

For your declaration:

```c
typedef enum ctd_status {
    CTD_OK = 0,
    CTD_ERROR_NULL = 1
} ctd_status;
```

there are two C names:

* `enum ctd_status` — the enum tag;
* `ctd_status` — the typedef name.

You can verify either through CFFI:

```python
assert ffi.typeof("ctd_status").kind == "enum"
assert ffi.typeof("ctd_status").cname == "ctd_status"

assert ffi.typeof("enum ctd_status").kind == "enum"
assert ffi.typeof("enum ctd_status").cname == "enum ctd_status"
```

Depending on CFFI’s canonicalization, comparing the type objects is more useful than requiring identical `cname` strings:

```python
assert ffi.typeof("ctd_status") == ffi.typeof("enum ctd_status")
```

A pytest test could be:

```python
def test_ctd_status_type() -> None:
    enum_type = ffi.typeof("ctd_status")

    assert enum_type.kind == "enum"
    assert enum_type == ffi.typeof("enum ctd_status")
```

### In C, enum members do not use the enum name

C enum enumerators are placed in the ordinary identifier namespace. You write:

```c
ctd_status status = CTD_OK;
```

not:

```c
ctd_status status = ctd_status.CTD_OK;  /* invalid C */
```

The enum name is required when declaring the type:

```c
ctd_status status;
enum ctd_status other_status;
```

But the members themselves are unscoped:

```c
CTD_OK
CTD_ERROR_NULL
```

That maps naturally to CFFI:

```python
ffi.typeof("ctd_status")  # type information
lib.CTD_OK                # enumerator value
```

Therefore, verifying the enum fully requires two separate tests:

```python
def test_ctd_status_type() -> None:
    assert ffi.typeof("ctd_status").kind == "enum"
    assert ffi.typeof("ctd_status") == ffi.typeof("enum ctd_status")


@pytest.mark.parametrize(
    "member",
    CtdStatus,
    ids=lambda member: member.name,
)
def test_ctd_status_member(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

---
---

## 📗 C Enum Use

> [!NOTE] Prompt
> 
> So, I do not really care about enum type/tag names? If members are verified, the same unscoped members will work in c? 

Correct. For ordinary C enum usage, **the enumerator names and values are what matter operationally**.

Given:

```c
typedef enum ctd_status {
    CTD_OK = 0,
    CTD_ERROR_NULL = 1
} ctd_status;
```

C code uses:

```c
ctd_status status = CTD_OK;

if(status == CTD_ERROR_NULL){
    /* ... */
}
```

The members are unscoped identifiers. They are not accessed through the tag or typedef:

```c
ctd_status.CTD_OK       /* invalid C */
enum ctd_status.CTD_OK  /* invalid C */
```

Therefore, this verifies the constants callers actually use:

```python
@pytest.mark.parametrize(
    "member",
    CtdStatus,
    ids=lambda member: member.name,
)
def test_ctd_status_member(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

The enum type name matters only where the type itself appears in the API, for example:

```c
ctd_status ctd_divide(...);
void ctd_set_status(ctd_status status);
ctd_status global_status;
```

But CFFI already compiled and exposed those declarations. If the typedef or tag name were incorrect in `cdef()`, the generated extension would generally fail to compile against the real header or would expose a different declared interface.

So for runtime tests:

- verify enumerator names and values;
- test functions accepting or returning the enum;
- usually do not separately test the enum tag or typedef name.

A separate `ffi.typeof("ctd_status")` test is worthwhile only when validating the generated binding’s declared type surface itself, rather than testing the C module’s behavior.

---
---

## 📗 C Contract Testing

> [!NOTE] Prompt
> 
> I need tests to verify the structures are there!

Correct. You need explicit contract tests for declared types, including structs, unions, enums, typedefs, and opaque types.

CFFI exposes those through `ffi.typeof()`, not `lib`.

For a struct typedef:

```c
typedef struct ctd_point {
    double x;
    double y;
} ctd_point;
```

verify both existence and structure:

```python
def test_ctd_point_type() -> None:
    ctype = ffi.typeof("ctd_point")

    assert ctype.kind == "struct"
    assert [field_name for field_name, _ in ctype.fields] == ["x", "y"]
```

For field types:

```python
def test_ctd_point_fields() -> None:
    ctype = ffi.typeof("ctd_point")
    fields = dict(ctype.fields)

    assert fields["x"].type.cname == "double"
    assert fields["y"].type.cname == "double"
```

For `ctd_stats`:

```python
def test_ctd_stats_type() -> None:
    ctype = ffi.typeof("ctd_stats")
    fields = dict(ctype.fields)

    assert ctype.kind == "struct"
    assert list(fields) == [
        "count",
        "minimum",
        "maximum",
        "sum",
        "mean",
    ]

    assert fields["count"].type.cname == "size_t"
    assert fields["minimum"].type.cname == "int32_t"
    assert fields["maximum"].type.cname == "int32_t"
    assert fields["sum"].type.cname == "int64_t"
    assert fields["mean"].type.cname == "double"
```

For fixed arrays inside structs:

```python
def test_ctd_record_type() -> None:
    ctype = ffi.typeof("ctd_record")
    fields = dict(ctype.fields)

    assert fields["id"].type.cname == "int32_t"

    assert fields["name"].type.kind == "array"
    assert fields["name"].type.item.cname == "char"
    assert fields["name"].type.length == 16

    assert fields["values"].type.kind == "array"
    assert fields["values"].type.item.cname == "double"
    assert fields["values"].type.length == 3
```

For a union:

```python
def test_ctd_number_type() -> None:
    ctype = ffi.typeof("ctd_number")
    fields = dict(ctype.fields)

    assert ctype.kind == "union"
    assert list(fields) == ["i64", "f64"]
    assert fields["i64"].type.cname == "int64_t"
    assert fields["f64"].type.cname == "double"
```

For an enum type:

```python
def test_ctd_status_type() -> None:
    ctype = ffi.typeof("ctd_status")

    assert ctype.kind == "enum"
```

And separately verify its members through `lib`:

```python
@pytest.mark.parametrize(
    "member",
    CtdStatus,
    ids=lambda member: member.name,
)
def test_ctd_status_member(member: CtdStatus) -> None:
    assert getattr(lib, member.name) == member.value
```

For an opaque type:

```c
typedef struct ctd_counter ctd_counter;
```

verify that it exists and remains incomplete:

```python
def test_ctd_counter_type() -> None:
    ctype = ffi.typeof("ctd_counter")

    assert ctype.kind == "struct"
    assert ctype.fields is None
```

For callback typedefs:

```python
def test_ctd_binary_callback_type() -> None:
    ctype = ffi.typeof("ctd_binary_callback")

    assert ctype.kind == "function"
    assert ctype.result.cname == "int"
    assert [arg.cname for arg in ctype.args] == [
        "int",
        "int",
        "void *",
    ]
```

Depending on CFFI representation, function-pointer typedefs may appear as a pointer whose item is the function type. A robust version is:

```python
def unwrap_function_pointer(ctype):
    if ctype.kind == "pointer":
        ctype = ctype.item

    assert ctype.kind == "function"
    return ctype
```

Then:

```python
def test_ctd_binary_callback_type() -> None:
    ctype = unwrap_function_pointer(ffi.typeof("ctd_binary_callback"))

    assert ctype.result.cname == "int"
    assert [arg.cname for arg in ctype.args] == [
        "int",
        "int",
        "void *",
    ]
```

The correct boundary is therefore:

* `ffi.typeof("name")` verifies declared C types exist and have the expected shape.
* `lib.NAME` verifies exposed constants, enum members, globals, and functions.
* Function calls verify behavior.

That is the complete contract surface you are trying to test.
