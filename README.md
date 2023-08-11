# Cross-compile for Windows

First MinGW-w64 toolchain must be installed:

```
brew install mingw-w64
```

Then run

```
nimble build -d:mingw -d:release
```
