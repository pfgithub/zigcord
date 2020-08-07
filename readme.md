# ZigCord Features
- Consume MESSAGE_CREATE events
- Send channel messages

## usage

- `git clone --recurse-submodules`
- make a file called `example-src/token` containing your token
- `while zig build run; do; done`

## errors

if there is an error about getentropy symbol not found:

edit `lib/zig-bearssl/BearSSL/src/config.h` and set
```c
#define BR_USE_GETENTROPY   0
```