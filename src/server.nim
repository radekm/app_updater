import std/os
import std/strutils

import jester

import shared

router myrouter:
  get "/hash":
    resp hashFile(publishArchive)
  get "/download":
    sendFile(getCurrentDir() / publishArchive)

proc main() =
  let
    (host, port) = readCommandLineArgs()
    settings = newSettings(bindAddr = host, port = port.Port)
  var jester = initJester(myrouter, settings = settings)
  jester.serve()

main()
