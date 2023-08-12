import std/memfiles
import std/os
import std/strformat
import std/strutils

import crunchy

const
  # `publishArchive` must contain directory `publishDir`.
  publishArchive* = "publish.zip"
  publishDir* = "publish"

proc hashFile*(path: string): string =
  var memFile = memfiles.open(path)
  defer: memFile.close()
  sha256(memFile.mem, memFile.size).toHex()

proc checkParamCount*(expected: int) =
  if paramCount() != expected:
    raise newException(CatchableError, fmt"Expected {expected} params but given {paramCount()}")

proc readHostAndPortFromParams*(): (string, int) =
  if paramCount() < 2:
    raise newException(CatchableError, "Host and port should be given")
  (paramStr(1), paramStr(2).parseInt())
