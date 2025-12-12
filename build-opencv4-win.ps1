<#
.SYNOPSIS
Build OpenCV for Windows (with contrib, DNN, world module)

.DESCRIPTION
This script builds OpenCV from source on Windows using CMake and Visual Studio.
Place this script in the root of the OpenCV source directory.

.PARAMETER VsArch
Target architecture: x64 (default), x86, arm64, arm64ec

.PARAMETER VsVer
Visual Studio toolset: v143 (VS2022, default), v142 (VS2019), etc.

.PARAMETER VsCRT
CRT linkage: md (dynamic, default) or mt (static)

.PARAMETER BuildJava
Enable Java bindings (default: false)

.PARAMETER BuildType
CMake build type: Release (default), Debug, MinSizeRel, RelWithDebInfo

.EXAMPLE
.\build-opencv4-win.ps1 -VsArch x64 -VsVer v143 -VsCRT md
#>

param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('x64', 'x86', 'arm64', 'arm64ec')]
    [string] $VsArch = "x64",

    [Parameter(Mandatory = $false)]
    [ValidateSet('v140', 'v141', 'v142', 'v143')]
    [string] $VsVer = 'v143',

    [Parameter(Mandatory = $false)]
    [ValidateSet('mt', 'md')]
    [string] $VsCRT = 'md',

    [Parameter(Mandatory = $false)]
    [switch] $BuildJava = $false,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Release', 'Debug', 'MinSizeRel', 'RelWithDebInfo')]
    [string] $BuildType = 'Release'
)

# === Strict error handling ===
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Speed up file ops in CI

Clear-Host
Write-Host "🔧 Build Parameters:"
Write-Host "   Architecture : $VsArch"
Write-Host "   VS Toolset   : $VsVer"
Write-Host "   CRT Linkage  : $VsCRT"
Write-Host "   Build Type   : $BuildType"
Write-Host "   Build Java   : $BuildJava"
Write-Host ""

# === Map architecture to CMake -A values ===
$ArchFlag = switch ($VsArch) {
    'x64'      { 'x64' }
    'x86'      { 'Win32' }
    'arm64'    { 'ARM64' }
    'arm64ec'  { 'ARM64EC' }
    default { throw "Unsupported architecture: $VsArch" }
}

# === Generator name (no arch suffix!) ===
$generator = switch ($VsVer) {
    'v140' { 'Visual Studio 14 2015' }
    'v141' { 'Visual Studio 15 2017' }
    'v142' { 'Visual Studio 16 2019' }
    'v143' { 'Visual Studio 17 2022' }
    default { throw "Unsupported VS version: $VsVer" }
}

# === Build directory ===
$OutPutPath = "build-$VsArch-$VsVer-$VsCRT"
if (!(Test-Path -Path $OutPutPath)) {
    New-Item -Path $OutPutPath -ItemType Directory | Out-Null
}
$absOutPath = (Resolve-Path $OutPutPath).Path
Write-Host "📁 Build directory: $absOutPath"

# === CMake configure arguments (as array) ===
$cmakeArgs = @(
    '-S', '.',
    '-B', $absOutPath,
    '-G', $generator,
    '-A', $ArchFlag,
    "-T", "$VsVer,host=x64",
    "-DCMAKE_SYSTEM_NAME=Windows",
    "-DCMAKE_SYSTEM_PROCESSOR=$ArchFlag",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DCMAKE_CONFIGURATION_TYPES=$BuildType",
    "-DCMAKE_INSTALL_PREFIX=$absOutPath/install"
)

# === Load custom CMake options ===
$OptionsFile = "opencv4_cmake_options.txt"
if (!(Test-Path -Path $OptionsFile -PathType Leaf)) {
    Write-Error "❌ Error: Cannot find $OptionsFile"
    exit 1
}
Write-Host "📄 Loading CMake options from: $OptionsFile"
Get-Content "$OptionsFile" | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        $cmakeArgs += $line
    }
}

# === Optional features ===
if ($VsCRT -eq 'mt') {
    $cmakeArgs += '-DBUILD_WITH_STATIC_CRT=ON'
} else {
    $cmakeArgs += '-DBUILD_WITH_STATIC_CRT=OFF'
}

if ($BuildJava) {
    $cmakeArgs += '-DBUILD_JAVA=ON'
    $cmakeArgs += '-DBUILD_opencv_java=ON'
}

if ($VsArch -in @('arm64', 'arm64ec')) {
    $cmakeArgs += '-DCV_ENABLE_INTRINSICS=OFF'
}

# === Run CMake configure ===
Write-Host "`n⚙️ Running CMake configure..."
Write-Host "Command: cmake $($cmakeArgs -join ' ')"
& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ CMake configure failed!"
    exit $LASTEXITCODE
}

# === Run CMake build ===
$LogicalProcessorsNum = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$buildArgs = @(
    '--build', $absOutPath,
    '--config', $BuildType,
    '--parallel', $LogicalProcessorsNum,
    '--target', 'install'
)

Write-Host "`n🔨 Running CMake build (parallel=$LogicalProcessorsNum)..."
Write-Host "Command: cmake $($buildArgs -join ' ')"
& cmake @buildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ CMake build failed!"
    exit $LASTEXITCODE
}

Write-Host "`n✅ Build completed successfully!"
Write-Host "📦 Install prefix: $absOutPath/install"
