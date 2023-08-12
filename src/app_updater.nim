import std/httpclient
import std/os
import std/osproc
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

checkParamCount(3)

let
  (host, port) = readHostAndPortFromParams()
  executable = paramStr(3)
  hashUrl = fmt"http://{host}:{port}/hash"
  downloadUrl = fmt"http://{host}:{port}/download"
  newPublishArchive = fmt"new-{publishArchive}"
  tempDir = "temp"
  exists = fileExists(publishArchive) and dirExists(publishDir)

proc update() =
  # Latest version is already installed.
  if exists and downloadString(hashUrl) == hashFile(publishArchive):
    return

  echo "Deleting temporaries"
  removeFile(newPublishArchive)
  removeDir(tempDir)

  echo fmt"Updating archive"
  downloadFile(downloadUrl, newPublishArchive)

  echo "Extracting archive"
  extractAll(newPublishArchive, tempDir)

  echo fmt"Making file executable"
  inclFilePermissions(tempDir / publishDir / executable, {fpUserExec})

  echo "Replacing current version with new version"
  removeDir(publishDir)
  moveDir(tempDir / publishDir, publishDir)
  removeFile(publishArchive)
  moveFile(newPublishArchive, publishArchive)

  echo "Deleting temporaries"
  removeDir(tempDir)

try:
  update()
except CatchableError as e:
  echo "Update failed with: " & e.msg

echo fmt"Executing {executable}"
let p = startProcess(publishDir / executable, "", options = {})
try:
  discard p.waitForExit()
finally:
  p.close()
