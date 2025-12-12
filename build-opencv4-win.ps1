<#
.SYNOPSIS
Build OpenCV for Windows

.PARAMETER VsArch
Target architecture: x64 (default), x86, arm64, arm64ec

.PARAMETER VsVer
Visual Studio toolset: v143 (VS2022), v142 (VS2019), etc.

.PARAMETER VsCRT
CRT linkage: md (dynamic) or mt (static)

.PARAMETER BuildJava
Enable Java bindings (default: false)

.PARAMETER BuildType
CMake build type: Release (default), Debug, etc.
#>

param (
    [string]$VsArch = "x64",
    [string]$VsVer = "v143",
    [string]$VsCRT = "md",
    [switch]$BuildJava = $false,
    [string]$BuildType = "Release"
)

$ErrorActionPreference = "Stop"

Write-Host "Build Parameters:"
Write-Host "  Architecture : $VsArch"
Write-Host "  VS Toolset   : $VsVer"
Write-Host "  CRT Linkage  : $VsCRT"
Write-Host "  Build Type   : $BuildType"
Write-Host "  Build Java   : $BuildJava"
Write-Host ""

# Map architecture to CMake -A value
switch ($VsArch) {
    "x64"      { $ArchFlag = "x64" }
    "x86"      { $ArchFlag = "Win32" }
    "arm64"    { $ArchFlag = "ARM64" }
    "arm64ec"  { $ArchFlag = "ARM64EC" }
    default { throw "Unsupported architecture: $VsArch" }
}

# Generator name (no arch suffix)
switch ($VsVer) {
    "v140" { $generator = "Visual Studio 14 2015" }
    "v141" { $generator = "Visual Studio 15 2017" }
    "v142" { $generator = "Visual Studio 16 2019" }
    "v143" { $generator = "Visual Studio 17 2022" }
    default { throw "Unsupported VS version: $VsVer" }
}

# Build directory
$OutPutPath = "build-$VsArch-$VsVer-$VsCRT"
if (!(Test-Path -Path $OutPutPath)) {
    New-Item -Path $OutPutPath -ItemType Directory | Out-Null
}
$absOutPath = (Resolve-Path $OutPutPath).Path
Write-Host "Build directory: $absOutPath"

# CMake arguments as array
$cmakeArgs = @(
    "-S", ".",
    "-B", $absOutPath,
    "-G", $generator,
    "-A", $ArchFlag,
    "-T", "$VsVer,host=x64",
    "-DCMAKE_SYSTEM_NAME=Windows",
    "-DCMAKE_SYSTEM_PROCESSOR=$ArchFlag",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DCMAKE_CONFIGURATION_TYPES=$BuildType",
    "-DCMAKE_INSTALL_PREFIX=$absOutPath/install"
)

# Load custom options
$OptionsFile = "opencv4_cmake_options.txt"
if (!(Test-Path -Path $OptionsFile -PathType Leaf)) {
    Write-Error "Error: Cannot find $OptionsFile"
    exit 1
}
Get-Content $OptionsFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and !$line.StartsWith("#")) {
        $cmakeArgs += $line
    }
}

# CRT linkage
if ($VsCRT -eq "mt") {
    $cmakeArgs += "-DBUILD_WITH_STATIC_CRT=ON"
} else {
    $cmakeArgs += "-DBUILD_WITH_STATIC_CRT=OFF"
}

# Java support
if ($BuildJava) {
    $cmakeArgs += "-DBUILD_JAVA=ON"
    $cmakeArgs += "-DBUILD_opencv_java=ON"
}

# ARM64 workaround
if ($VsArch -eq "arm64" -or $VsArch -eq "arm64ec") {
    $cmakeArgs += "-DCV_ENABLE_INTRINSICS=OFF"
}

# Run CMake configure
Write-Host ""
Write-Host "Running CMake configure..."
& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "CMake configure failed!"
    exit $LASTEXITCODE
}

# Run CMake build
$cpuCount = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$buildArgs = @(
    "--build", $absOutPath,
    "--config", $BuildType,
    "--parallel", $cpuCount,
    "--target", "install"
)

Write-Host ""
Write-Host "Running CMake build..."
& cmake @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "CMake build failed!"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Build completed successfully."
Write-Host "Install path: $absOutPath/install"
