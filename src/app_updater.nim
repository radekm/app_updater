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
  tempDir = "temp"
  exists = fileExists(publishArchive) and dirExists(publishDir)

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
  echo fmt"Making file executable {executable}"
  inclFilePermissions(publishDir / executable, {fpUserExec})
else:
  echo "Archive is up to date"

echo fmt"Executing {executable}"
let p = startProcess(publishDir / executable, "", options = {})
try:
  discard p.waitForExit()
finally:
  p.close()
