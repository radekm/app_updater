# Cross-compile from Mac for Linux

Installing

```
brew install x86_64-elf-gcc
```

and configuring Nim compiler to use `x86_64-elf-gcc` as compiler and linker doesn't
work because some header files are missing. Using `llvm` to cross-compile
has the same problem.

So we use Zig 0.11. We need to use command `zig cc` and since `clang.exe` value
must not contain spaces we wrap it in shell script `zigcc`. Now we can run

```
PATH=".:$PATH" nimble build \
  --cpu:amd64 --os:linux -d:release \
  --cc:clang \
  --clang.exe="zigcc" \
  --clang.linkerexe="zigcc" \
  --passC:--target=x86_64-linux-gnu --passL:--target=x86_64-linux-gnu
```

# Cross-compile from Mac for Windows

First MinGW-w64 toolchain must be installed:

```
brew install mingw-w64
```

Then run

```
nimble build -d:mingw -d:release
```
