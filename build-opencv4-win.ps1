<#
.SYNOPSIS build opencv for windows by benjaminwan
.DESCRIPTION
This is a powershell script for building OpenCV in Windows.
Put this script in the OpenCV root path, then run: .\build-opencv-win.ps1

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

# === 新增：严格错误处理 ===
$ErrorActionPreference = "Stop"

Clear-Host
Write-Host "Params: VsArch=$VsArch VsVer=$VsVer VsCRT=$VsCRT BuildJava=$BuildJava BuildType=$BuildType"

$genArgs = @()

# Map architecture to CMake flags
switch ($VsArch) {
    'x64'      { $ArchFlag = 'x64' }
    'x86'      { $ArchFlag = 'Win32' }
    'arm64'    { $ArchFlag = 'ARM64' }
    'arm64ec'  { $ArchFlag = 'ARM64EC' }
    default { throw "Unsupported architecture: $VsArch" }
}

# === 新增：显式指定 generator ===
$generator = switch ($VsVer) {
    'v140' { 'Visual Studio 14 2015' }
    'v141' { 'Visual Studio 15 2017' }
    'v142' { 'Visual Studio 16 2019' }
    'v143' { 'Visual Studio 17 2022' }
    default { throw "Unsupported VS version: $VsVer" }
}

if ($VsArch -eq 'x86') {
    $genArgs += "-G '$generator'"
} else {
    $genArgs += "-G '$generator $ArchFlag'"
}

# Toolset and system info
$genArgs += "-T $VsVer,host=x64"
$genArgs += "-DCMAKE_SYSTEM_NAME=Windows"
$genArgs += "-DCMAKE_SYSTEM_PROCESSOR=$ArchFlag"
$genArgs += "-DCMAKE_BUILD_TYPE=$BuildType"
$genArgs += "-DCMAKE_CONFIGURATION_TYPES=$BuildType"

# Load custom options
$OptionsFile = "opencv4_cmake_options.txt"
if (!(Test-Path -Path $OptionsFile -PathType Leaf)) {
    Write-Error "Error: Cannot find $OptionsFile"
    exit 1
}
Get-Content "$OptionsFile" | ForEach-Object { 
    if ($_ -match '\S') { $genArgs += $_ }  # Skip empty lines
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

# Java support
if ($BuildJava) {
    $genArgs += '-DBUILD_JAVA=ON'
    $genArgs += '-DBUILD_opencv_java=ON'
}

# === 移除强制 WITH_OPENCL=ON ===
# 让 opencv4_cmake_options.txt 控制所有选项

# Output path
$OutPutPath = "build-$VsArch-$VsVer-$VsCRT"
if (!(Test-Path -Path $OutPutPath)) {
    New-Item -Path $OutPutPath -ItemType Directory | Out-Null
}

# Use absolute path for robustness
$absOutPath = (Resolve-Path $OutPutPath).Path
$genArgs += "-S ."                          # ←←← 新增这一行
$genArgs += "-DCMAKE_INSTALL_PREFIX=$absOutPath/install"
$genArgs += "-B $absOutPath"                # 注意：加空格更安全（非必须，但推荐）

# Generate
$genCall = "cmake " + ($genArgs -join ' ')
Write-Host $genCall
Invoke-Expression $genCall

# Build
$LogicalProcessorsNum = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$buildArgs = @('--build', $absOutPath, '--config', $BuildType, '--parallel', $LogicalProcessorsNum, '--target', 'install')
$buildCall = "cmake " + ($buildArgs -join ' ')
Write-Host $buildCall
Invoke-Expression $buildCall
