# NSURLSessionWebSocketTask Test Suite

This repository contains a small conformance test suite and a stress test for
the WebSocket implementation in NSURLSession.

Because the official API documentation is rather sparse, I build the test suite
and checks with initial assumption, that I then validated on MacOS 15.7.2.

## Dependencies

You need a recent version of python and create a venv by running `sh
create-venv.sh`.

### Linux
- A working GNUstep installation with Objective-C 2.0 support (libobjc2, gnustep-make, gnustep-base).
  Please note that as of writing this, the GNUstep debian packages do not support Objective-C 2.0, and use the GCC runtime.

We use the GNUstep configuration tool `gnustep-config` to get the GNUstep and Objective-C specific compiler
and linker flags.

Make sure to source the `GNUstep.sh` script in your shell before compiling and running the program, otherwise
meson might not be able to locate `gnustep-config`.

If you used the standard FHS installation layout, or did not explicitly set a layout when building GNUstep,
you can source the script like this:

```bash
source /usr/share/GNUstep/Makefiles/GNUstep.sh
```

## Building
First, setup the meson project and `build/` directory: 
```bash
# Source the GNUstep environment script if not already done by your shell configuration (e.g. source /usr/share/GNUstep/Makefiles/GNUstep.sh)
OBJC=clang meson setup build
```

You can now compile and execute the example program:
```bash
ninja -C build
./build/objc-boilerplate venv/bin/python3 server/main.py ws://localhost:8080
```
