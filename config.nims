import os
import strformat
import strutils


const exeName = "gridmonger".toExe
const rootDir = getCurrentDir()
const version = staticRead("CURRENT_VERSION").strip

const macPackageName = fmt"gridmonger-v{version}-mac.zip"

const dataDir = "Data"
const exampleMapsDir = "Example Maps"
const manualDir = "Manual"
const themesDir = "Themes"

const distDir    = "dist"
const distWinDir = distDir / "win"
const distMacDir = distDir / "mac"

const distManualName = "gridmonger-manual.zip"
const distMapsName = "gridmonger-example-maps.zip"

const siteDir = "docs"
const siteFilesDir = siteDir / "files"
const siteReleasesDir = siteFilesDir / "releases"
const siteReleasesMacDir = siteReleasesDir / "macos"
const siteReleasesWinDir = siteReleasesDir / "windows"
const siteExtrasDir = siteFilesDir / "extras"

const sphinxDocsDir = "sphinx-docs"


proc setCommonCompileParams() =
  --gc:orc
  --deepcopy:on
  --d:nimPreviewFloatRoundtrip
  --d:nvgGL3
  --d:glfwStaticLib
  --hint:"Name:off"
  switch "out", exeName
  setCommand "c", "src/main"

proc createZip(zipName, srcPath: string, extraArgs = "") =
  exec fmt"zip -q -9 -r ""{zipName}"" ""{srcPath}"" {extraArgs}"

type Arch = enum
  Arch32 = (0, "32")
  Arch64 = (1, "64")

let arch = if hostCPU == "i386": Arch32 else: Arch64

proc getWinInstallerPackageName(arch: Arch): string =
  fmt"gridmonger-v{version}-win{arch}-setup.zip"

proc getWinPortablePackageName(arch: Arch): string =
  fmt"gridmonger-v{version}-win{arch}-portable.zip"


# All tasks must be executed from the project root directory!

task debug, "debug build":
  --d:debug
  setCommonCompileParams()


task releaseNoStacktrace, "release build (no stacktrace)":
  --d:release
  --app:gui
  setCommonCompileParams()


task release, "release build":
  --stacktrace:on
  --linetrace:on
  releaseNoStacktraceTask()


task strip, "strip executable":
  exec fmt"strip -S {exeName}"


task packageWin, "create Windows installer":
  stripTask()
  mkdir distWinDir
  exec fmt"makensis /DARCH{arch} gridmonger.nsi"


task packageWinPortable, "create Windows portable package":
  stripTask()

  mkdir distWinDir
  let packageName = "Gridmonger"
  let packageDir = distWinDir / packageName
  rmDir packageDir
  mkDir packageDir

  # Create config dir
  mkDir packageDir / "Config"

  # Copy main executable
  cpFile exeName, packageDir / exeName

  # Copy resources
  cpDir dataDir, packageDir / dataDir
  cpDir exampleMapsDir, packageDir / exampleMapsDir
  cpDir manualDir, packageDir / manualDir
  cpDir themesDir, packageDir / themesDir

  let zipName = getWinPortablePackageName(arch)
  withDir distWinDir:
    createZip(zipName, srcPath=packageName)

  rmDir packageDir


task publishPackageWin, "publish Windows packages":
  let installerName = getWinInstallerPackageName(arch)
  cpFile distWinDir / installerName, siteReleasesWinDir / installerName

  let portableName = getWinPortablePackageName(arch)
  cpFile distWinDir / portableName, siteReleasesWinDir / portableName


task packageMac, "create macOS app bundle":
  stripTask()

  let appBundleName = "Gridmonger.app"
  let appBundleDir = distMacDir / appBundleName
  let contentsDir = appBundleDir / "Contents"
  let macOsDir = contentsDir / "MacOS"
  let resourcesDir = contentsDir / "Resources"

  let distExePath = macOsDir / exeName.capitalizeAscii

  rmDir appBundleDir
  mkDir contentsDir

  # Copy plist file & set version
#  sed "s/{VERSION}/$VERSION/g" Info.plist >$contentsDir/Info.plist
  cpFile "Info.plist", contentsDir / "Info.plist"

  # Copy main executable
  mkDir macOsDir
  cpFile exeName, distExePath

  # Copy resources
  mkDir resourcesDir
  cpDir dataDir, resourcesDir / dataDir
  cpDir exampleMapsDir, resourcesDir / exampleMapsDir
  cpDir manualDir, resourcesDir / manualDir
  cpDir themesDir, resourcesDir / themesDir
  cpFile "extras/appicons/mac/gridmonger.icns", resourcesDir / "gridmonger.icns"

  # Set executable flags
  exec "chmod +x " & distExePath
  exec "xattr -cr " & distExePath

  #codesign --verbose --sign fmt"Developer ID Application: John Novak (VRF26934X5)" --options runtime --entitlements Entitlements.plist --deep {appBundleDir}"
  #codesign --verify --deep --strict --verbose=2 appBundleDir

  # Make distribution ZIP file
  withDir distMacDir:
    createZip(zipName=macPackageName, srcPath=appBundleName)


task publishPackageMac, "publish macOS app bundle":
  cpFile distMacDir / macPackageName, siteReleasesMacDir / macPackageName


task manual, "build manual":
  withDir sphinxDocsDir:
    exec "make build_manual"


task packageManual, "create zipped manual package":
  let outputDir = "Gridmonger Manual"
  cpDir manualDir, outputDir
  mkdir distDir
  rmFile distDir / distManualName
  createZip(zipName=distDir / distManualName, srcPath=outputDir)
  rmDir outputDir


task packageExampleMaps, "create zipped example maps package":
  rmFile distDir / distMapsName
  createZip(zipName=distDir / distMapsName, srcPath=exampleMapsDir, extraArgs="-i *.gmm")


task publishExtras, "publish extra packages":
  cpFile distDir / distManualName, siteExtrasDir / distManualName
  cpFile distDir / distMapsName, siteExtrasDir / distMapsName


task site, "build website":
  withDir sphinxDocsDir:
    exec "make build_site"

  exec "extras/scripts/indexer.py -r docs/files"


task clean, "clean everything":
  rmFile exeName
  rmDir distDir
  rmDir manualDir
  withDir sphinxDocsDir:
    exec "make clean"

