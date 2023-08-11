# Package

version       = "0.1.0"
author        = "Radek Micek"
description   = "Downloads, updates and executes .NET applications"
license       = "MIT"
srcDir        = "src"
bin           = @["app_updater", "server"]

# Dependencies

requires "nim >= 2.0.0"
requires "zippy >= 0.10.10"
requires "crunchy >= 0.1.9"
requires "jester >= 0.6.0"
