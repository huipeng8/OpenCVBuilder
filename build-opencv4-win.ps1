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

$ErrorActionPreference = "Stop"
Clear-Host
Write-Host "Params: VsArch=$VsArch VsVer=$VsVer VsCRT=$VsCRT BuildJava=$BuildJava BuildType=$BuildType"

$genArgs = @()

# === Architecture mapping ===
switch ($VsArch) {
    'x64'      { $ArchFlag = 'x64'; $SystemProcessor = 'AMD64' }
    'x86'      { $ArchFlag = 'Win32'; $SystemProcessor = 'x86' }
    'arm64'    { $ArchFlag = 'ARM64'; $SystemProcessor = 'ARM64' }
    'arm64ec'  { $ArchFlag = 'ARM64EC'; $SystemProcessor = 'ARM64EC' }
    default { throw "Unsupported architecture: $VsArch" }
}

# === Generator and Architecture ===
$generator = switch ($VsVer) {
    'v140' { 'Visual Studio 14 2015' }
    'v141' { 'Visual Studio 15 2017' }
    'v142' { 'Visual Studio 16 2019' }
    'v143' { 'Visual Studio 17 2022' }
    default { throw "Unsupported VS version: $VsVer" }
}

# Base generator (without arch for modern VS)
$genArgs += "-G '$generator'"

# Handle architecture: use -A for VS2017+ (v141+), embed in name for v140
if ($VsVer -in @('v141', 'v142', 'v143')) {
    $cmakeArch = switch ($VsArch) {
        'x64'      { 'x64' }
        'x86'      { 'Win32' }
        'arm64'    { 'ARM64' }
        'arm64ec'  { 'ARM64EC' }
        default { throw "Unsupported architecture for -A: $VsArch" }
    }
    $genArgs += "-A $cmakeArch"
} elseif ($VsArch -ne 'x86') {
    # VS2015 (v140): append arch to generator name
    $suffix = if ($VsArch -eq 'x64') { ' Win64' } elseif ($VsArch -eq 'arm64') { ' ARM' } else { '' }
    $genArgs[-1] = "-G '$generator$suffix'"
}

# === Toolset & system info ===
$genArgs += "-T $VsVer,host=x64"
$genArgs += "-DCMAKE_SYSTEM_NAME=Windows"
$genArgs += "-DCMAKE_SYSTEM_PROCESSOR=$SystemProcessor"
$genArgs += "-DCMAKE_BUILD_TYPE=$BuildType"
$genArgs += "-DCMAKE_CONFIGURATION_TYPES=$BuildType"

# === Output path (clean build) ===
$OutPutPath = "build-$VsArch-$VsVer-$VsCRT"
if (Test-Path -Path $OutPutPath) {
    Remove-Item -Recurse -Force $OutPutPath
    Write-Host "Cleaned previous build directory: $OutPutPath"
}
New-Item -Path $OutPutPath -ItemType Directory | Out-Null
$absOutPath = (Resolve-Path $OutPutPath).Path

# CRITICAL FIX: Add -S and -B FIRST to avoid "Ignoring extra path"
$genArgs += "-S ."
$genArgs += "-B$absOutPath"

# === Load base CMake options from file ===
$OptionsFile = "opencv4_cmake_options.txt"
if (!(Test-Path -Path $OptionsFile -PathType Leaf)) {
    Write-Error "Error: Cannot find $OptionsFile"
    exit 1
}
Get-Content "$OptionsFile" | ForEach-Object {
    $line = $_.Trim()
    if ($line -and $line -notmatch '^\s*[#;]') {
        $genArgs += $line
    }
}

# === Architecture-specific fixes ===
if ($VsArch -in @('arm64', 'arm64ec')) {
    $genArgs += '-DCV_ENABLE_INTRINSICS=OFF'
}

# === CRT linkage and build strategy ===
if ($VsCRT -eq 'mt') {
    # /MT: Static, minimal, no IPP, no contrib
    $genArgs += '-DBUILD_SHARED_LIBS=OFF'
    $genArgs += '-DBUILD_WITH_STATIC_CRT=ON'
    $genArgs += '-DWITH_IPP=OFF'
    $genArgs += '-DBUILD_opencv_dnn=OFF'
    $genArgs += '-DBUILD_opencv_videoio=OFF'
    $genArgs += '-DBUILD_opencv_highgui=OFF'
    $genArgs += '-DWITH_WIN32UI=OFF'
    $genArgs += '-DWITH_FFMPEG=OFF'
    $genArgs += '-DWITH_MSMF=OFF'
    $genArgs += '-DWITH_VFW=OFF'
    $genArgs += '-DBUILD_opencv_gapi=OFF'
    $genArgs += '-DBUILD_opencv_stitching=OFF'
    $genArgs += '-DBUILD_opencv_rapid=OFF'
    $genArgs += '-DBUILD_opencv_plot=OFF'
    $genArgs += '-DBUILD_opencv_quality=OFF'
    $genArgs += '-DBUILD_opencv_saliency=OFF'
    $genArgs += '-DBUILD_opencv_wechat_qrcode=OFF'
    $genArgs += '-DBUILD_opencv_text=OFF'
    $genArgs += '-DBUILD_opencv_tracking=OFF'
    $genArgs += '-DBUILD_opencv_xphoto=OFF'
    $genArgs += '-DBUILD_opencv_ximgproc=OFF'
    $genArgs += '-DBUILD_opencv_xfeatures2d=OFF'
    $genArgs += '-DBUILD_opencv_face=OFF'
    $genArgs += '-DBUILD_opencv_fuzzy=OFF'
    $genArgs += '-DBUILD_opencv_line_descriptor=OFF'
    $genArgs += '-DBUILD_opencv_mcc=OFF'
    $genArgs += '-DBUILD_opencv_objdetect=OFF'
    $genArgs += '-DBUILD_opencv_optflow=OFF'
    $genArgs += '-DBUILD_opencv_phase_unwrapping=OFF'
    $genArgs += '-DBUILD_opencv_reg=OFF'
    $genArgs += '-DBUILD_opencv_rgbd=OFF'
    $genArgs += '-DBUILD_opencv_shape=OFF'
    $genArgs += '-DBUILD_opencv_structured_light=OFF'
    $genArgs += '-DBUILD_opencv_superres=OFF'
    $genArgs += '-DBUILD_opencv_surface_matching=OFF'
    $genArgs += '-DBUILD_opencv_videostab=OFF'
    $genArgs += '-DBUILD_opencv_xobjdetect=OFF'
    $genArgs += '-DBUILD_opencv_aruco=OFF'
    $genArgs += '-DBUILD_opencv_bgsegm=OFF'
    $genArgs += '-DBUILD_opencv_bioinspired=OFF'
    $genArgs += '-DBUILD_opencv_ccalib=OFF'
    $genArgs += '-DBUILD_opencv_datasets=OFF'
    $genArgs += '-DBUILD_opencv_dpm=OFF'
    $genArgs += '-DBUILD_opencv_hfs=OFF'
    $genArgs += '-DBUILD_opencv_img_hash=OFF'
    $genArgs += '-DBUILD_opencv_intensity_transform=OFF'
    $genArgs += '-DBUILD_opencv_ml=OFF'
    $genArgs += '-DBUILD_opencv_photo=OFF'
    $genArgs += '-DBUILD_opencv_signal=OFF'
    $genArgs += '-DBUILD_opencv_stereo=OFF'
} else {
    # /MD: Dynamic, full feature, with IPP and contrib
    $genArgs += '-DBUILD_SHARED_LIBS=ON'
    $genArgs += '-DBUILD_WITH_STATIC_CRT=OFF'
    # Only add contrib path here — and only once!
    $genArgs += '-DOPENCV_EXTRA_MODULES_PATH=../opencv_contrib/modules'
}

# === Java support ===
if ($BuildJava) {
    $genArgs += '-DBUILD_JAVA=ON'
    $genArgs += '-DBUILD_opencv_java=ON'
} else {
    $genArgs += '-DBUILD_JAVA=OFF'
    $genArgs += '-DBUILD_opencv_java=OFF'
}

# === Install prefix (safe to add last) ===
$genArgs += "-DCMAKE_INSTALL_PREFIX=$absOutPath/install"

# === Generate ===
$genCall = "cmake " + ($genArgs -join ' ')
Write-Host $genCall -ForegroundColor Cyan
Invoke-Expression $genCall

# === Build ===
$LogicalProcessorsNum = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$buildArgs = @('--build', $absOutPath, '--config', $BuildType, '--parallel', $LogicalProcessorsNum, '--target', 'install')
$buildCall = "cmake " + ($buildArgs -join ' ')
Write-Host $buildCall -ForegroundColor Green
Invoke-Expression $buildCall
