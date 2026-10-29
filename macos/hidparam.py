#!/usr/bin/env python3
"""Set a live IOHIDSystem parameter, the way System Settings' sliders do.

`defaults write -g com.apple.trackpad.scaling` only persists a value: the HID
system reads the global prefs at login, so a plain `defaults write` does
nothing until you log out.  System Settings avoids that by *also* poking the
running IOHIDSystem, which is what this does -- IOServiceOpen on IOHIDSystem
with kIOHIDParamConnectType (1), then IOHIDSetParameter.

ctypes rather than a compiled helper on purpose: no build step, no binary in
the repo, and stock /usr/bin/python3 is enough.  IOHIDSetParameter has been
deprecated since 10.12 and still has no replacement for these keys; it works
unprivileged because the param connect type is what the prefs UI uses.

Values are 16.16 fixed point, hence the * 65536.

    hidparam.py HIDTrackpadAcceleration 1.5
"""

import ctypes
import ctypes.util
import sys

KERN_SUCCESS = 0
kIOHIDParamConnectType = 1
kCFStringEncodingUTF8 = 0x08000100


def set_parameter(key: str, value: float) -> None:
    iokit = ctypes.CDLL(ctypes.util.find_library("IOKit"))
    cf = ctypes.CDLL(ctypes.util.find_library("CoreFoundation"))
    libc = ctypes.CDLL(None)

    cf.CFStringCreateWithCString.restype = ctypes.c_void_p
    cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
    iokit.IOServiceMatching.restype = ctypes.c_void_p
    iokit.IOServiceGetMatchingService.restype = ctypes.c_uint
    iokit.IOServiceGetMatchingService.argtypes = [ctypes.c_uint, ctypes.c_void_p]
    iokit.IOServiceOpen.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_uint,
                                    ctypes.POINTER(ctypes.c_uint)]
    iokit.IOHIDSetParameter.argtypes = [ctypes.c_uint, ctypes.c_void_p, ctypes.c_void_p,
                                        ctypes.c_ulong]
    libc.mach_task_self.restype = ctypes.c_uint
    # Both releases need argtypes too: without them ctypes passes the handle as
    # a C int, truncating a 64-bit CFStringRef to 32 bits, and CFRelease
    # segfaults on the result.
    iokit.IOObjectRelease.argtypes = [ctypes.c_uint]
    iokit.IOServiceClose.argtypes = [ctypes.c_uint]
    cf.CFRelease.argtypes = [ctypes.c_void_p]

    service = iokit.IOServiceGetMatchingService(0, iokit.IOServiceMatching(b"IOHIDSystem"))
    if not service:
        sys.exit("hidparam: no IOHIDSystem service")

    conn = ctypes.c_uint(0)
    rc = iokit.IOServiceOpen(service, libc.mach_task_self(), kIOHIDParamConnectType,
                             ctypes.byref(conn))
    iokit.IOObjectRelease(service)
    if rc != KERN_SUCCESS:
        sys.exit(f"hidparam: IOServiceOpen failed (0x{rc & 0xffffffff:x})")

    fixed = ctypes.c_int(int(value * 65536))
    cfkey = cf.CFStringCreateWithCString(None, key.encode(), kCFStringEncodingUTF8)
    rc = iokit.IOHIDSetParameter(conn.value, cfkey, ctypes.byref(fixed), ctypes.sizeof(fixed))
    cf.CFRelease(cfkey)
    iokit.IOServiceClose(conn.value)
    if rc != KERN_SUCCESS:
        sys.exit(f"hidparam: IOHIDSetParameter({key}) failed (0x{rc & 0xffffffff:x})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <HIDParameterKey> <float>")
    set_parameter(sys.argv[1], float(sys.argv[2]))
