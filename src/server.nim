import std/os
import std/strutils

import jester

import shared

router myrouter:
  get "/hash":
    resp hashFile(publishArchive)
  get "/download":
    # When sending a file we should use `sendFile(getCurrentDir() / publishArchive)`.
    # But unfortunately `sendFile` doesn't work with files bigger than 10 MB.
    # It sends `Content-Length` header twice -- the first time with zero
    # and the second time with the actual file length.
    # The issue exists since 2020: https://github.com/dom96/jester/issues/241
    let blob = readFile(getCurrentDir() / publishArchive)
    resp Http200, blob, "application/octet-stream"

proc main() =
  let
    (host, port) = readCommandLineArgs()
    settings = newSettings(bindAddr = host, port = port.Port)
  var jester = initJester(myrouter, settings = settings)
  jester.serve()

main()
