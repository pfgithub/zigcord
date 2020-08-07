# ZigCord Features
- Consume MESSAGE_CREATE events
- Send channel messages

Recursively clone, place your token inside `example-src/main.zig`, and run `zig build` for the ping-pong example.

## errors

if there is an error about getentropy symbol not found:

edit `lib/zig-bearssl/BearSSL/src/config.h` and set
```c
#define BR_USE_GETENTROPY   0
```