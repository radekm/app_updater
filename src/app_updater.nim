import std/httpclient
import std/os
import std/osproc
import std/sequtils
import std/strformat

import zippy/ziparchives

import shared

proc downloadString(url: string): string =
  echo fmt"Downloading string from {url}"
  var client = newHttpClient()
  defer: client.close()
  client.getContent(url)

proc downloadFile(url: string, dest: string) =
  echo fmt"Downloading file from {url}"
  var client = newHttpClient()
  defer: client.close()
  client.downloadFile(url, dest)

let
  (host, port) = readCommandLineArgs()
  hashUrl = fmt"http://{host}:{port}/hash"
  downloadUrl = fmt"http://{host}:{port}/download"
  tempDir = "temp"
  exists = fileExists(publishArchive) and dirExists(publishDir)

var installed = false

if not exists or downloadString(hashUrl) != hashFile(publishArchive):
  echo "Deleting old version"
  removeFile(publishArchive)
  removeDir(publishDir)
  removeDir(tempDir)
  echo fmt"Updating archive"
  downloadFile(downloadUrl, publishArchive)
  echo "Extracting archive"
  extractAll(publishArchive, tempDir)
  moveDir(tempDir / publishDir, getCurrentDir() / publishDir)
  removeDir(tempDir)

  installed = true
else:
  echo "Archive is up to date"

let executables = toSeq(walkFiles(fmt"{publishDir}/*.exe"))

if executables.len == 0:
  raise newException(CatchableError, "No executable found")
elif executables.len > 1:
  raise newException(CatchableError, fmt"Several executables found: {executables}")
else:
  let executable = executables[0]
  if installed:
    echo fmt"Making file executable {executable}"
    inclFilePermissions(executable, {fpUserExec})
  echo fmt"Executing {executable}"
  let p = startProcess(executable, "", options = {})
  defer: p.close()
  discard p.waitForExit()
