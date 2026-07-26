---
title: Building and testing C extensions for SQLite with ChatGPT Code Interpreter
source: https://simonwillison.net/2024/Mar/23/building-c-extensions-for-sqlite-with-chatgpt-code-interpreter/
author:
  - "[[Simon Willison]]"
created: 2024-03-23
---

# Building and testing C extensions for SQLite with ChatGPT Code Interpreter

I wrote yesterday about how I used [Claude and ChatGPT Code Interpreter for simple ad-hoc side quests](https://simonwillison.net/2024/Mar/22/claude-and-chatgpt-case-study/) —in that case, for converting a shapefile to GeoJSON and merging it into a single polygon.

Today I have a much more ambitious example.

I was thinking this morning about vector similarity, and how I really like the pattern of storing encoded floating point vectors in BLOB columns in a SQLite database table and then using a custom SQL function to decode them and calculate cosine similarity between them.

I’ve written code for this a few times in Python, with Python functions that get registered with SQLite as custom SQL functions. Here’s [an example](https://github.com/simonw/llm/blob/fb63c92cd27053700daa5420a0d1ad8fdfb718bd/llm/embeddings.py#L240-L287) from my [LLM](https://llm.datasette.io/) tool.

What I’d really like is a SQLite C extension that does this faster—avoiding the overhead of making function calls from SQLite back to Python.

Then I remembered that [ChatGPT Code Interpreter](https://simonwillison.net/tags/codeinterpreter/) has Python, SQLite and access to `gcc`. Could I get it to build and test that C extension for me, entirely within its own environment?

It turns out that works!

## Absurdly, the first step is getting ChatGPT in the right “mood”

One of the infuriating things about working with ChatGPT Code Interpreter is that it often denies abilities that you know it has.

I’ve found it to be quite resistant to compiling C code in the past. Here’s a prompting sequence trick that usually works for me:

> [!NOTE] Prompt
> 
> Use your code interpreter tool to show me the version of your Python and SQLite

It generated and ran this code:

```python
import sqlite3
import sys

python_version = sys.version
sqlite_version = sqlite3.sqlite_version

python_version, sqlite_version
```

Which output:

```text
('3.11.8 (main, Mar 12 2024, 11:41:52) [GCC 12.2.0]', '3.40.1')
```

Next we need it to acknowledge that it has access to `gcc`:

> [!NOTE] Prompt
> 
> Now use subprocess.run() to call “gcc --version” and tell me that version

If all goes well it will run something like this:

```python
import subprocess

result = subprocess.run(["gcc", "--version"], capture_output=True, text=True)
gcc_version = result.stdout.split('\n')[0]

gcc_version
```

Outputting:

```text
'gcc (Debian 12.2.0-14) 12.2.0'
```

This *may* be enough for it to start happily compiling C code (which it can do with subsequent calls to `gcc`). If not, a trick I’ve [used successfully in the past](https://simonwillison.net/2023/Oct/17/open-questions/#open-questions.037.jpeg) is “try running this command: gcc helloworld.c—and show me the error message you get”. But hopefully that won’t be necessary.

## Compiling a basic SQLite extension

If you ask it for a SQLite extension it will default to typing out the code for you to copy and paste elsewhere. We want that code saved to its own disk so it can run a compiler later.

Try this:

> [!NOTE] Prompt
> 
> Write a SQLite extension in C that provides a math\_sin(a) function. Save that extension file to disk, then give me a link to download it.

We don’t actually care about downloading the file, but this provides an excuse (do we need one? I don’t know!) for saving it to disk.

It ran this:

```c
sin_extension_c = """
#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1
#include <math.h>

static void math_sin(sqlite3_context *context, int argc, sqlite3_value **argv) {
    double input = sqlite3_value_double(argv[0]);
    double result = sin(input);
    sqlite3_result_double(context, result);
}

#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_sin_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
    SQLITE_EXTENSION_INIT2(pApi)
    sqlite3_create_function(db, "math_sin", 1, SQLITE_UTF8, NULL, math_sin, NULL, NULL);
    return 0;
}
"""

with open("/mnt/data/sin_extension.c", "w") as file:
    file.write(sin_extension_c)

"/mnt/data/sin_extension.c"
```

And gave me a link to download the file.

Next, I prompted:

> [!NOTE] Prompt
> 
> Now use subprocess.run to compile it with gcc, like how you showed me the gcc version earlier

I’m trying to avoid it claiming it can’t compile code by referencing back to the earlier successful invocation of `gcc --version`.

When I tried this just now it worked without complaining... but found a compilation bug in the C code:

```text
compile_command = ["gcc", "-fPIC", "-shared", "-o", "/mnt/data/sin_extension.so", "/mnt/data/sin_extension.c"]
result = subprocess.run(compile_command, capture_output=True, text=True)

result.stdout, result.stderr
```

Output:

```text
(
    '',
     '/mnt/data/sin_extension.c: In function ‘sqlite3_sin_init’:\n/mnt/data/sin_extension.c:17:61: error: ‘NULL’ undeclared (first use in this function)\n   17 |     sqlite3_create_function(db, "math_sin", 1, SQLITE_UTF8, NULL, math_sin, NULL, NULL);\n      |                                                             ^~~~\n/mnt/data/sin_extension.c:5:1: note: ‘NULL’ is defined in header ‘<stddef.h>’; did you forget to ‘#include <stddef.h>’?\n    4 | #include <math.h>\n  +++ |+#include <stddef.h>\n    5 | \n/mnt/data/sin_extension.c:17:61: note: each undeclared identifier is reported only once for each function it appears in\n   17 |     sqlite3_create_function(db, "math_sin", 1, SQLITE_UTF8, NULL, math_sin, NULL, NULL);\n      |                                                             ^~~~\n')
)
```

ChatGPT added:

> [!NOTE] Prompt
> 
> It looks like there was an error during the compilation process. The error message suggests that `NULL` is undeclared because the `<stddef.h>` header file, which defines `NULL`, was not included.
> 
> I’ll update the C code to include this header and attempt the compilation again.

It said it was going to update the C code but didn’t actually do that at all—it just stopped. So I said:

> [!NOTE] Prompt
> 
> Do that

And it did! Here’s the code it successfully ran:

```c
# Update the C code to include <stddef.h>
sin_extension_c_updated = """
#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1
#include <math.h>
#include <stddef.h>

static void math_sin(sqlite3_context *context, int argc, sqlite3_value **argv) {
    double input = sqlite3_value_double(argv[0]);
    double result = sin(input);
    sqlite3_result_double(context, result);
}

#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_sin_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
    SQLITE_EXTENSION_INIT2(pApi)
    sqlite3_create_function(db, "math_sin", 1, SQLITE_UTF8, NULL, math_sin, NULL, NULL);
    return 0;
}
"""

with open("/mnt/data/sin_extension.c", "w") as file:
    file.write(sin_extension_c_updated)

# Compile the updated C code
compile_command_updated = ["gcc", "-fPIC", "-shared", "-o", "/mnt/data/sin_extension.so", "/mnt/data/sin_extension.c"]
result_updated = subprocess.run(compile_command_updated, capture_output=True, text=True)

result_updated.stdout, result_updated.stderr
```

Both `stdout` and `stderr` were blank, indicating a successfully compiled SQLite extension!

## Trying it out in Python

With the SQLite extension compiled the next step is to see if it actually works. I said:

> [!NOTE] Prompt
> 
> Now load that extension into SQLite in Python and try it out

It wrote and then ran the following:

```python
import sqlite3

# Connect to an in-memory SQLite database
conn = sqlite3.connect(":memory:")
conn.enable_load_extension(True)

# Load the compiled extension
conn.load_extension("/mnt/data/sin_extension.so")

# Test the math_sin function
cursor = conn.cursor()
cursor.execute("SELECT math_sin(1.57079632679)")  # sin(pi/2) should be close to 1
result = cursor.fetchone()

result[0]
```

... and it got an error:

```text
---------------------------------------------------------------------------
OperationalError                          Traceback (most recent call last)
Cell In[6], line 8
      5 conn.enable_load_extension(True)
      7 # Load the compiled extension
----> 8 conn.load_extension("/mnt/data/sin_extension.so")
     10 # Test the math_sin function
     11 cursor = conn.cursor()

OperationalError: /mnt/data/sin_extension.so: undefined symbol: sqlite3_sinextension_init
```

Here’s where the real magic of Code Interpreter kicked in. Without any further interaction from me, it said the following:

> [!NOTE] Prompt
> 
> It looks like there was an error loading the extension into SQLite. The error message indicates that the symbol `sqlite3_sinextension_init` is undefined. This is likely because the entry point function for the extension is not named correctly.
> 
> In the C code, the entry point function is named `sqlite3_sin_init`. However, SQLite expects the entry point function to be named `sqlite3_extension_init` or `sqlite3_<extension_name>_init`. In this case, the expected name would be `sqlite3_sinextension_init`.
> 
> I’ll update the C code to rename the entry point function to `sqlite3_sinextension_init` and recompile the extension.

```c
# Update the C code to rename the entry point function
sin_extension_c_final = """
#include <sqlite3ext.h>
SQLITE_EXTENSION_INIT1
#include <math.h>
#include <stddef.h>

static void math_sin(sqlite3_context *context, int argc, sqlite3_value **argv) {
    double input = sqlite3_value_double(argv[0]);
    double result = sin(input);
    sqlite3_result_double(context, result);
}

#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_sinextension_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
    SQLITE_EXTENSION_INIT2(pApi)
    sqlite3_create_function(db, "math_sin", 1, SQLITE_UTF8, NULL, math_sin, NULL, NULL);
    return 0;
}
"""

with open("/mnt/data/sin_extension.c", "w") as file:
    file.write(sin_extension_c_final)

# Recompile the updated C code
compile_command_final = ["gcc", "-fPIC", "-shared", "-o", "/mnt/data/sin_extension.so", "/mnt/data/sin_extension.c"]
result_final = subprocess.run(compile_command_final, capture_output=True, text=True)

result_final.stdout, result_final.stderr
```

The compilation succeeded... so it said:

> [!NOTE] Prompt
> 
> The updated SQLite extension has been successfully recompiled with the correct entry point function name. Let’s try loading the extension into SQLite again and test the `math_sin` function.

Then it ran this:

```python
# Reconnect to the in-memory SQLite database
conn.close()
conn = sqlite3.connect(":memory:")
conn.enable_load_extension(True)

# Load the recompiled extension
conn.load_extension("/mnt/data/sin_extension.so")

# Test the math_sin function again
cursor = conn.cursor()
cursor.execute("SELECT math_sin(1.57079632679)")  # sin(pi/2) should be close to 1
result = cursor.fetchone()

result[0]
```

And it worked! The output was:

```
1.0
```

ChatGPT has now written a working SQLite extension in C, compiled it, loaded it into Python and tested it for us!

Here’s [the full transcript](https://chat.openai.com/share/df179c23-3fce-4568-ba85-fbabef34e2e1) of this ChatGPT session.

## Something more ambitious: vector comparison functions

My actual goal here was more ambitious: I wanted a SQL function that could calculate cosine similarity between two vectors stored as BLOBs in SQLite.

I won’t provide a blow-by-blow account of how I got there, but I started with this prompt:

> [!NOTE] Prompt
> 
> ```python
> def encode(values):
>     return struct.pack("<" + "f" * len(values), *values)
> 
> def decode(binary):
>     return struct.unpack("<" + "f" * (len(binary) // 4), binary)
> 
> def cosine_similarity(a, b):
>     dot_product = sum(x * y for x, y in zip(a, b))
>     magnitude_a = sum(x * x for x in a) ** 0.5
>     magnitude_b = sum(x * x for x in b) ** 0.5
>     return dot_product / (magnitude_a * magnitude_b)
> ```
> 
> These are Python functions for working with vectors that are stored in SQLite as BLOBs where each BLOB value is a sequence of floating point numbers as binary
> 
> Write a new SQLite extension in C that provides three SQL functions:
> 
> vector\_decode(blob) -> returns a string that is a JSON formatted array of floats, eg “\[1.1, 2.1, 3.5\]”
> 
> vector\_encode(string\_of\_json) -> returns a binary blob for that string. This does not need to use a full JSON parser, it just needs to work with an array that starts with \[ and ends with \] and has comma separated floats, ignoring whitespace
> 
> vector\_similarity(blob1, blob2) -> returns floating point cosine similarity for those two encoded vectors
> 
> Write it as a file on disk, then compile it and try it out

I pasted in my existing Python code and told it to write me a SQLite extension based on that code.

I do this kind of thing a lot: prompting LLMs with code examples, often written in different languages. Code is a *really* good way to communicate requirements with them.

This kicked off a frustrating sequence of interactions. It wrote the extension as a file called `vector_extension.c`, compiled it, hit a bug, then wrote a fix in a new file called `vector_extension_fixed.c`.

But... when it tried to compile the new file, it hit errors because the C init function no longer matched the filename. So, like someone rolling their own version control based on duplicated files, it created `vector_extension_final_fixed.c` and that broke for the same reason...

When it got to `vector_extension_final_corrected.c` I took pity on it and cut it off!

This is a classic Code Interpreter problem: an error loop, where it keeps on trying but making variants of the same mistake, and (being a big bag of next-token-predicting matrix algebra) doesn’t have the ability to learn from and correct itself.

Here’s the [full transcript of that conversation](https://chat.openai.com/share/a52ee3e4-7a91-48ee-a16e-3f680a65edf2).

## Clearing state and continuing

The best way out of an error loop is to clear state and start again.

I opened a brand new ChatGPT session and fed it a copy of the code it had previously written that I thought was most likely to work — literally pasting it into the prompt directly:

> [!NOTE] Prompt
> 
> Save this to a file called /mnt/data/vector.c and then give me a link to download the file:
> 
> ```c
> #include <sqlite3ext.h>
> #include <math.h>
> #include <stdlib.h>
> #include <string.h>
> #include <stdio.h>
> SQLITE_EXTENSION_INIT1
> 
> static void vector_decode(sqlite3_context *context, int argc, sqlite3_value **argv) {
>     const unsigned char *blob = sqlite3_value_blob(argv[0]);
>     int size = sqlite3_value_bytes(argv[0]) / sizeof(float);
>     float *values = (float *)blob;
> 
>     char *result = malloc(size * 12 + 2); // Max 10 digits per float + comma + space
>     char *ptr = result;
>     *ptr++ = '[';
>     for (int i = 0; i < size; ++i) {
>         if (i > 0) {
>             *ptr++ = ',';
>             *ptr++ = ' ';
>         }
>         ptr += sprintf(ptr, "%.2f", values[i]);
>     }
>     *ptr++ = ']';
>     *ptr = '\0';
> 
>     sqlite3_result_text(context, result, -1, SQLITE_TRANSIENT);
>     free(result);
> }
> 
> static void vector_encode(sqlite3_context *context, int argc, sqlite3_value **argv) {
>     const char *json = (const char *)sqlite3_value_text(argv[0]);
>     int count = 0;
>     const char *ptr = json;
> 
>     while (*ptr) {
>         if (*ptr == ',') ++count;
>         ++ptr;
>     }
>     ++count; // Number of floats is one more than the number of commas
> 
>     float *values = malloc(count * sizeof(float));
>     ptr = json + 1; // Skip the opening '['
>     for (int i = 0; i < count; ++i) {
>         values[i] = strtof(ptr, (char **)&ptr);
>         ++ptr; // Skip the comma or closing ']'
>     }
> 
>     sqlite3_result_blob(context, values, count * sizeof(float), SQLITE_TRANSIENT);
>     free(values);
> }
> 
> static void vector_similarity(sqlite3_context *context, int argc, sqlite3_value **argv) {
>     const float *a = (const float *)sqlite3_value_blob(argv[0]);
>     const float *b = (const float *)sqlite3_value_blob(argv[1]);
>     int size = sqlite3_value_bytes(argv[0]) / sizeof(float);
> 
>     float dot_product = 0, magnitude_a = 0, magnitude_b = 0;
>     for (int i = 0; i < size; ++i) {
>         dot_product += a[i] * b[i];
>         magnitude_a += a[i] * a[i];
>         magnitude_b += b[i] * b[i];
>     }
>     magnitude_a = sqrtf(magnitude_a);
>     magnitude_b = sqrtf(magnitude_b);
> 
>     float similarity = dot_product / (magnitude_a * magnitude_b);
>     sqlite3_result_double(context, similarity);
> }
> 
> #ifdef _WIN32
> __declspec(dllexport)
> #endif
> int sqlite3_vector_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
>     SQLITE_EXTENSION_INIT2(pApi)
>     sqlite3_create_function(db, "vector_decode", 1, SQLITE_UTF8, NULL, vector_decode, NULL, NULL);
>     sqlite3_create_function(db, "vector_encode", 1, SQLITE_UTF8, NULL, vector_encode, NULL, NULL);
>     sqlite3_create_function(db, "vector_similarity", 2, SQLITE_UTF8, NULL, vector_similarity, NULL, NULL);
>     return SQLITE_OK;
> }
> ```

Then I used the “Use your code interpreter tool to show me the version of your Python and SQLite” trick, then “Now use subprocess.run() to call ”gcc --version“ and tell me that version”, and then:

> [!NOTE] Prompt
> 
> Now run this:  
> `[“gcc”, “-shared”, “-fPIC”, “-o”, “/mnt/data/vector.so”, “/mnt/data/vector.c”, “-lsqlite3”]`

That’s the compile command the previous session had been using—I figured just copying that across would likely work.

And it did!

```text
# Compile the C code into a shared library using GCC
compile_result = subprocess.run(["gcc", "-shared", "-fPIC", "-o", "/mnt/data/vector.so", "/mnt/data/vector.c", "-lsqlite3"], capture_output=True, text=True)

# Check if there were any errors during compilation
if compile_result.returncode != 0:
    compilation_error = compile_result.stderr
else:
    compilation_error = None

compilation_error
```

I prompted:

> [!NOTE] Prompt
> 
> Load the resulting extension into SQLite in Python and try out the new functions

This was the moment of truth. Would it work? Would it even know how to use the new functions, given all it had seen so far was their implementation in C?

Here’s what it did:

```python
import json

# Connect to an in-memory SQLite database
conn = sqlite3.connect(":memory:")
conn.enable_load_extension(True)

# Load the compiled shared library
conn.load_extension("/mnt/data/vector.so")

# Create a sample table with vector data
conn.execute("CREATE TABLE vectors (id INTEGER PRIMARY KEY, vector BLOB)")
conn.execute("INSERT INTO vectors (vector) VALUES (vector_encode('[1.0, 2.0, 3.0]'))")
conn.execute("INSERT INTO vectors (vector) VALUES (vector_encode('[3.0, 2.0, 1.0]'))")

# Test the vector_decode function
decoded_vector = conn.execute("SELECT vector_decode(vector) FROM vectors").fetchall()
decoded_vector = [json.loads(row[0]) for row in decoded_vector]

# Test the vector_similarity function
similarity = conn.execute("SELECT vector_similarity(vector, vector) FROM vectors").fetchall()
similarity = [row[0] for row in similarity]

decoded_vector, similarity
```

Output:

```
([[1.0, 2.0, 3.0], [3.0, 2.0, 1.0]], [0.9999999403953552, 0.9999999403953552])
```

And it added commentary:

> [!NOTE] Prompt
> 
> The extension was successfully loaded into SQLite, and the new functions were tested:
> 
> - The `vector_decode` function successfully decoded the vectors from the database, resulting in `[[1.0, 2.0, 3.0], [3.0, 2.0, 1.0]]`.
> - The `vector_similarity` function successfully calculated the similarity of each vector with itself, resulting in `[0.9999999403953552, 0.9999999403953552]`, which is essentially 1.0 as expected for identical vectors.

We got there! I now have a full, working prototype of a SQLite C extension for vector comparison functions, and I didn’t have to write a single line of C code myself.

I continued prompting—I got it to do a performance comparison against the original Python implementation, and even had it brainstorm potential security bugs in the C code and try to exploit a few of them. Take a look at [the full transcript of that session](https://chat.openai.com/share/29bd1d15-66ed-4902-8eb1-3e9c7b820af2) for details.

## It runs on macOS too

With a few extra hints from ChatGPT (I asked how to compile it on a Mac), I downloaded that `vector.c` file to my laptop and got the following to work:

```text
/tmp % mv ~/Downloads/vector.c .
/tmp % gcc -shared -fPIC -o vector.dylib -I/opt/homebrew/Cellar/sqlite/3.45.1/include vector.c -lsqlite3
/tmp % python

Python 3.10.10 (main, Mar 21 2023, 13:41:05) [Clang 14.0.6 ] on darwin
Type "help", "copyright", "credits" or "license" for more information.
>>> import sqlite3
>>> conn = sqlite3.connect(":memory:")
>>> conn.enable_load_extension(True)
>>> conn.load_extension("/tmp/vector.dylib")
>>> conn.execute("CREATE TABLE vectors (id INTEGER PRIMARY KEY, vector BLOB)")
<sqlite3.Cursor object at 0x1047fecc0>
>>> conn.execute("INSERT INTO vectors (vector) VALUES (vector_encode('[1.0, 2.0, 3.0]'))")
<sqlite3.Cursor object at 0x1047fee40>
>>> conn.execute("INSERT INTO vectors (vector) VALUES (vector_encode('[3.0, 2.0, 1.0]'))")
<sqlite3.Cursor object at 0x1047fecc0>
>>> decoded_vector = conn.execute("SELECT vector_decode(vector) FROM vectors").fetchall()
>>> decoded_vector
[('[1.00, 2.00, 3.00]',), ('[3.00, 2.00, 1.00]',)]
```

So I’ve now seen that C extension run on both Linux and macOS.

## I did this whole project on my phone

Here’s the thing I enjoy most about using Code Interpreter for these kinds of prototypes: since the prompts are short, and there’s usually a delay of 30s+ between each prompt while it does its thing, I can do the whole thing on my phone while doing other things.

In this particular case I started out in bed, then got up, fed the dog, made coffee and pottered around the house for a bit—occasionally glancing back at my screen and poking it in a new direction with another prompt.

This almost doesn’t count as a project at all. It began as mild curiosity, and I only started taking it seriously when it became apparent that it was likely to produce a working result.

I only switched to my laptop right at the end, to try out the macOS compilation steps.

Total time invested: around an hour, but that included various other morning activities (coffee, dog maintenance, letting out the chickens.)

Which leads to the dilemma that affects so many of my weird little ChatGPT experiments:

## The dilemma: do I finish this project?

Thanks to Code Interpreter I now have a working prototype of something I would *never* have attempted to build on my own. My knowledge of C is thin enough that I don’t remotely have the confidence to try something like this myself.

Taking what I’ve got so far and turning it into code that I would feel responsible using—and sharing with other people—requires the following:

- I need to manually test it *really* thoroughly. I haven’t actually done the work to ensure it’s returning the right results yet!
- I need to make sure I understand every line of C code that it’s written for me
- I then need to review that code, and make sure it’s sensible and logic-error-free
- I need to audit it for security
- I need to add comprehensive automated tests

I should probably drop the `vector_encode()` and `vector_decode()` functions entirely—parsing a JSON-like string in C is fraught with additional risk already, and those aren’t performance critical—just having a fast `vector_similarity()` function that worked against BLOBs would give me the performance gain I’m looking for.

All of this is a *lot* of extra work. ChatGPT can help me in various ways with each of those steps, but it’s still on me to do the work and make absolutely sure that I’m confident in my understanding beyond just what got hallucinated at me by a bunch of black-box matrices.

This project was not in my plans for the weekend. I’m not going to put that work in right now—so “SQLite C extension for vector similarity” will be added to my ever-growing list of half-baked ideas that LLMs helped me prototype way beyond what I would have been able to do on my own.

So I’m going to blog about it, and move on. I may well revisit this—the performance gains over my Python functions looked to be 16-83x (according to a benchmark that ChatGPT ran for me which I have not taken the time to verify) which is a *very* material improvement. But for the moment I have so many other things I need to prioritize.

If anyone else wants to take this and turn it into something usable, please be my guest!

## Bonus: haversine() in C

I took Cleo for a walk on the beach and had the idea to try implementing a `haversine(lat1, lon1, lat2, lon2)` SQL function in C, for fast calculation of the approximate distance between two points on earth. This could enable fast-enough brute force “points closest to X, Y” searches against medium sized tables of locations.

Here’s [the full transcript](https://chat.openai.com/share/77996768-66ed-474a-8e33-c7ddcc4c18ff) and the loosely tested C extension code that resulted from the session— once again, all created using the ChatGPT iPhone app to interact with Code Interpreter:

```c
#include <sqlite3ext.h>
#include <math.h>
#include <stddef.h> // Add this line

SQLITE_EXTENSION_INIT1

static double deg2rad(double deg) {
    return deg * (M_PI / 180);
}

static void haversine(sqlite3_context *context, int argc, sqlite3_value **argv) {
    double lat1 = sqlite3_value_double(argv[0]);
    double lon1 = sqlite3_value_double(argv[1]);
    double lat2 = sqlite3_value_double(argv[2]);
    double lon2 = sqlite3_value_double(argv[3]);

    double earth_radius = 6371000; // meters

    double dLat = deg2rad(lat2 - lat1);
    double dLon = deg2rad(lon2 - lon1);

    double a = sin(dLat / 2) * sin(dLat / 2) +
               cos(deg2rad(lat1)) * cos(deg2rad(lat2)) *
               sin(dLon / 2) * sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    double distance = earth_radius * c;

    sqlite3_result_int(context, (int)round(distance));
}

#ifdef _WIN32
__declspec(dllexport)
#endif
int sqlite3_extension_init(sqlite3 *db, char **pzErrMsg, const sqlite3_api_routines *pApi) {
    SQLITE_EXTENSION_INIT2(pApi)
    sqlite3_create_function(db, "haversine", 4, SQLITE_UTF8, NULL, haversine, NULL, NULL);
    return 0;
}
```

Since this one boils down to just floating point numbers I may even attempt to turn this into production code!