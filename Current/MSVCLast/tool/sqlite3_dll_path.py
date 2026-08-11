from __future__ import annotations

import ctypes
from ctypes import wintypes
from pathlib import Path


kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
kernel32.GetModuleHandleW.restype = wintypes.HMODULE

kernel32.GetModuleFileNameW.argtypes = [
    wintypes.HMODULE,
    wintypes.LPWSTR,
    wintypes.DWORD,
]
kernel32.GetModuleFileNameW.restype = wintypes.DWORD


def get_loaded_dll_path(name: str) -> Path | None:
    handle = kernel32.GetModuleHandleW(name)
    if not handle:
        return None

    size = 260

    while True:
        buffer = ctypes.create_unicode_buffer(size)
        length = kernel32.GetModuleFileNameW(
            handle,
            buffer,
            size,
        )

        if length == 0:
            raise ctypes.WinError(ctypes.get_last_error())

        if length < size - 1:
            return Path(buffer.value).resolve()

        size *= 2


# Ensure Python's SQLite extension has been imported and initialized.
import sqlite3

path = get_loaded_dll_path("sqlite3.dll")

if path is None:
    print("No separately loaded sqlite3.dll was found.")
else:
    print(path)
