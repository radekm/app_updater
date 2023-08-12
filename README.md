# Updater for .NET desktop applications

This app is a very simple replacement for ClickOnce and Squirell.
Suppose you have created .NET desktop application which will be updated regularly
and you need to distribute updates to your users.

Suppose your users are using Windows. The first step is to publish your .NET app for Windows:

```
rm -r bin/Release/net7.0/win-x64/
dotnet publish -c Release -r win-x64 --self-contained true
cd bin/Release/net7.0/win-x64
zip -r ../../../../publish.zip publish
cd ../../../..
```

The second step is to start HTTP server which will distribute `publish.zip` file.
On a server create a directory where you copy `publish.zip` and `server` executable.
Start server

```
./server localhost 2222
```

In your browser you can check that `http://localhost:2222/hash` shows hash of `publish.zip`.

The third step is to distribute `app_updater.exe` executable to your user
and create a shortcut icon which will run

```
app_updater.exe hostname 2222 YourAppName.exe
```

where `hostname` is hostname of your server, `2222` is port where our server runs
and `YourAppName.exe` is an executable of your application
(it should exist in your `publish` directory).
`appupdater.exe` will download and extract `publish.zip` to current working directory
and run the executable.

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
