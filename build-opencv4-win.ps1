<#
.SYNOPSIS build opencv for windows by benjaminwan
.DESCRIPTION
This is a powershell script for building OpenCV in Windows.
Put this script in the OpenCV root path, then run: .\build-opencv4-win.ps1

ATTENTION:
  Set ExecutionPolicy before running: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
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

# === 严格错误处理 ===
$ErrorActionPreference = "Stop"

Clear-Host
Write-Host "Params: VsArch=$VsArch VsVer=$VsVer VsCRT=$VsCRT BuildJava=$BuildJava BuildType=$BuildType"

$genArgs = @()

# Map architecture to CMake -A values
switch ($VsArch) {
    'x64'      { $ArchFlag = 'x64' }
    'x86'      { $ArchFlag = 'Win32' }
    'arm64'    { $ArchFlag = 'ARM64' }
    'arm64ec'  { $ArchFlag = 'ARM64EC' }
    default { throw "Unsupported architecture: $VsArch" }
}

# === Generator mapping (NO architecture suffix!) ===
$generator = switch ($VsVer) {
    'v140' { 'Visual Studio 14 2015' }
    'v141' { 'Visual Studio 15 2017' }
    'v142' { 'Visual Studio 16 2019' }
    'v143' { 'Visual Studio 17 2022' }
    default { throw "Unsupported VS version: $VsVer" }
}

# ✅ CORRECT: Use -G without arch, and -A separately
$genArgs += "-G '$generator'"
$genArgs += "-A $ArchFlag"

# Toolset (host=x64 is standard)
$genArgs += "-T $VsVer,host=x64"

# System info
$genArgs += "-DCMAKE_SYSTEM_NAME=Windows"
$genArgs += "-DCMAKE_SYSTEM_PROCESSOR=$ArchFlag"
$genArgs += "-DCMAKE_BUILD_TYPE=$BuildType"
$genArgs += "-DCMAKE_CONFIGURATION_TYPES=$BuildType"

# Source and build directories (CRITICAL!)
$genArgs += "-S ."  # ←←← Source is current directory

# Load custom CMake options
$OptionsFile = "opencv4_cmake_options.txt"
if (!(Test-Path -Path $OptionsFile -PathType Leaf)) {
    Write-Error "Error: Cannot find $OptionsFile"
    exit 1
}
Get-Content "$OptionsFile" | ForEach-Object {
    if ($_ -match '\S' -and -not $_.StartsWith('#')) {
        $genArgs += $_
    }
}

# ARM64 intrinsics workaround
if ($VsArch -in @('arm64', 'arm64ec')) {
    $genArgs += '-DCV_ENABLE_INTRINSICS=OFF'
}

# CRT linkage
if ($VsCRT -eq 'mt') {
    $genArgs += '-DBUILD_WITH_STATIC_CRT=ON'
} else {
    $genArgs += '-DBUILD_WITH_STATIC_CRT=OFF'
}

# Java support (optional)
if ($BuildJava) {
    $genArgs += '-DBUILD_JAVA=ON'
    $genArgs += '-DBUILD_opencv_java=ON'
}

# Output directory
$OutPutPath = "build-$VsArch-$VsVer-$VsCRT"
if (!(Test-Path -Path $OutPutPath)) {
    New-Item -Path $OutPutPath -ItemType Directory | Out-Null
}

# Use absolute path for robustness
$absOutPath = (Resolve-Path $OutPutPath).Path
$genArgs += "-DCMAKE_INSTALL_PREFIX=$absOutPath/install"
$genArgs += "-B $absOutPath"  # ←←← Build directory

# Generate command
$genCall = "cmake " + ($genArgs -join ' ')
Write-Host "CMake configure command:"
Write-Host $genCall
Invoke-Expression $genCall

# Build command
$LogicalProcessorsNum = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$buildArgs = @('--build', $absOutPath, '--config', $BuildType, '--parallel', $LogicalProcessorsNum, '--target', 'install')
$buildCall = "cmake " + ($buildArgs -join ' ')
Write-Host "CMake build command:"
Write-Host $buildCall
Invoke-Expression $buildCall
