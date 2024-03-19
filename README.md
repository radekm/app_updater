# Updater for .NET desktop applications

This app is a very simple replacement for ClickOnce and Squirell.
Suppose you have created .NET desktop application which will be updated regularly
and you need to distribute updates to your users.

Suppose your users are using Windows. The first step is to publish your .NET app for Windows:

```
rm -r bin/Release/net8.0/win-x64/
dotnet publish -c Release -r win-x64 --self-contained true
cd bin/Release/net8.0/win-x64
zip -r ../../../../publish.zip publish
cd ../../../..
```

The second step is to start HTTP server which will distribute `publish.zip` file.
On a server create a directory where you copy `publish.zip` and `server` executable.
Start server

```
./server 127.0.0.1 2222
```

In your browser you can check that `http://localhost:2222/hash?archive=publish.zip`
shows hash of `publish.zip`. The server distributes all files in its working directory
with `.zip` extension.

The third step is to distribute `app-updater.exe` executable to your user
and create a shortcut icon which will run

```
app-updater.exe hostname 2222 publish.zip YourAppName.exe
```

where

- `hostname` is hostname of your server,
- `2222` is port where our server runs,
- `publish.zip` is the name of the archive
  which contains `publish` directory and has `.zip` extension,
- and `YourAppName.exe` is an executable of your application
  which exists in `publish` directory from the archive.

`app-updater.exe` will download and extract `publish.zip` to current working directory
and run the executable.

# Cross-compile server from Mac for Linux

Run

```bash
zig build server -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-gnu
```

# Cross-compile client from Mac for Windows

Run

```bash
zig build client -Doptimize=ReleaseSafe -Dtarget=x86_64-windows
```
