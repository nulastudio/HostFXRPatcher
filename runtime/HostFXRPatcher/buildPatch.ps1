param
(
    $RID,
    $Configuration,
    [switch]$Portable,
    [switch]$Cross,
    [switch]$Stripsymbols
)

function Write-Message($message, $err)
{
    $msg = "
====================
$message
====================
"
    if ($err) {
        Write-Host $msg -ForegroundColor red
    } else {
        Write-Host $msg
    }
}

function Get-Separator
{
    return (Join-Path . .).Trim('.')
}

function Format-Path($path)
{
    $separator = Get-Separator
    return "${path}".Replace('/', $separator).Replace('\', $separator)
}

function Print-Usage
{
    Write-Host "Usage:"
    Write-Host "-rid <RID> -configuration <Configuration=Debug|Release> [-portable] [-cross] [-stripsymbols]"
}

function Check-Arguments
{
    if (!$RID) {
        Print-Usage
        exit
    }
}

function Write-VersionInfo {
    $COMPANYNAME = "Microsoft Corporation"
    $FILEDESCRIPTION = ".NET Core Host Resolver - ${version_nv}"
    $PRODUCTNAME = "Microsoft(R) .NET Framework"
    $PRODUCTVERSION = "0,0,0,0"
    $PRODUCTVERSION_STR = "${PRODUCTVERSION} @Commit: ${longcommit}"
    $FILEVERSION = "0,0,0,0"
    $FILEVERSION_STR = "${FILEVERSION} @Commit: ${longcommit}"
    $LEGALCOPYRIGHT = "(C) Microsoft Corporation. All rights reserved."

    $content = Get-Content -Raw -Path ${scriptdir}/version_info.h
    $content = $content.Replace("{COMPANYNAME}", $COMPANYNAME)
    $content = $content.Replace("{FILEDESCRIPTION}", $FILEDESCRIPTION)
    $content = $content.Replace("{PRODUCTNAME}", $PRODUCTNAME)
    $content = $content.Replace("{PRODUCTVERSION}", $PRODUCTVERSION)
    $content = $content.Replace("{PRODUCTVERSION_STR}", $PRODUCTVERSION_STR)
    $content = $content.Replace("{FILEVERSION}", $FILEVERSION)
    $content = $content.Replace("{FILEVERSION_STR}", $FILEVERSION_STR)
    $content = $content.Replace("{LEGALCOPYRIGHT}", $LEGALCOPYRIGHT)
    $content | Out-File ${clidir}/version_info.h
}

function Fix-CMake-Version-Detect {
    $content = Get-Content -Raw -Path ${rootdir}/eng/native/build-commons.sh
    $content = $content.Replace("[0-9]+\.[0-9]+\.[0-9]+$", "[0-9]+\.[0-9]+\.[0-9]+")
    $content | Out-File ${rootdir}/eng/native/build-commons.sh
}

function Fix-Patch {
    Write-Message "Patching"

    $content = Get-Content -Raw -Path ${clidir}/runtime_config.cpp

    $magicString = "/* HostFXRPatcher */"

    # v5.*
    $content = $content.Replace("m_probe_paths.insert(m_probe_paths.begin(), probe_paths->value.GetString());", "m_probe_paths.insert(m_probe_paths.begin(), get_directory(m_path) + probe_paths->value.GetString());" + $magicString)
    $content = $content.Replace("m_probe_paths.push_front(begin->GetString());", "m_probe_paths.push_front(get_directory(m_path) + begin->GetString());" + $magicString)

    if (!$content.Contains($magicString)) {
        Write-Message "Patch Failed" $true
        exit
    } else {
        Write-Message "Patch Success"
    }

    $content | Out-File ${clidir}/runtime_config.cpp
}

function Remove-Unneed-Build {
    Write-Message "Remove Unneed Builds"

    $content = Get-Content -Path ${clidir}/CMakeLists.txt
    $content = $content.Replace("add_subdirectory(apphost)", "")
    $content = $content.Replace("add_subdirectory(dotnet)", "")
    $content = $content.Replace("add_subdirectory(nethost)", "")
    $content = $content.Replace("add_subdirectory(test_fx_ver)", "")
    $content = $content.Replace("add_subdirectory(hostpolicy)", "")
    $content = $content.Replace("add_subdirectory(test)", "")
    $content | Out-File ${clidir}/CMakeLists.txt
}

$Windows = $([System.Runtime.InteropServices.OSPlatform]::Windows)
$Linux   = $([System.Runtime.InteropServices.OSPlatform]::Linux)
$Darwin  = $([System.Runtime.InteropServices.OSPlatform]::OSX)

function Is-OS($OS)
{
    return $([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform($OS))
}

if (!$Configuration) {
    $Configuration = "Release"
}

Check-Arguments

$scriptdir    = Format-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$rootdir      = Format-Path "${scriptdir}/.."
$artifactsdir = Format-Path "${rootdir}/artifacts-patched"

$workdir      = ""
$clidir       = ""

$workdir1     = Format-Path "${rootdir}/src/installer/corehost"
$clidir1      = Format-Path "${workdir1}/cli"

$workdir2     = Format-Path "${rootdir}/src/native/corehost"
$clidir2      = $workdir2

$arch          = $RID.Split('-')[1]
$configuration = $Configuration


if (Is-OS($Windows)) {
    $platform = "windows"
    $hostfxr  = "hostfxr.dll"
} elseif (Is-OS($Linux)) {
    $platform = "linux"
    $hostfxr  = "libhostfxr.so"
} elseif (Is-OS($Darwin)) {
    $platform = "darwin"
    $hostfxr  = "libhostfxr.dylib"
}

$version       = "0.0"
$buildhash     = "00000000"
$pportable     = ""
$pcrossbuild   = ""
$pstripsymbols = ""

if ($Portable) {
    $pportable = "-portablebuild"
}
if ($Cross) {
    $pcrossbuild = "-cross"
}
if ($Stripsymbols) {
    $pstripsymbols = "-stripsymbols"
}

if (!(Test-Path $artifactsdir)) {
    mkdir -p $artifactsdir >$null 2>$null
}

$versionMap = (Get-Content -Raw "${scriptdir}/VersionMapping.json") | ConvertFrom-Json
[System.Collections.ArrayList]$versionBuilt = @()
[System.Collections.ArrayList]$versionRelease = @()

if (Test-Path("${scriptdir}/VersionBuilt.json")) {
    $json = (Get-Content -Raw "${scriptdir}/VersionBuilt.json") | ConvertFrom-Json -NoEnumerate
    if ($json) {
        $versionBuilt = $json
    }
}

if (Test-Path("${scriptdir}/VersionReleased.json")) {
    $json = (Get-Content -Raw "${scriptdir}/VersionReleased.json") | ConvertFrom-Json -NoEnumerate
    if ($json) {
        $versionRelease = $json
    }
}

[System.Collections.ArrayList]$tags = @()

# 全新编译
# $versionBuilt = @()

# 版本过滤
foreach ($tag in (git tag))
{
    # 只编译5.x以及6.x
    if (($tag -like "v5*") -or ($tag -like "v6*")) {
        $version = $tag
        if ($versionMap.$tag) {
            $version = $versionMap.$tag
        }
        if ($versionBuilt.Contains($version)) {
            continue
        }
        [void]$tags.Add($tag)
    }
}

# 增量编译
# 每次发布新版本之后在这里写
# DO NOT DELETE THIS LINE

# 自定义版本编译
# $tags = @()
# [void]$tags.Add("v5.0.0")

# 去重
[System.Collections.ArrayList]$tmp = @()
foreach ($tag in $tags) {
    if (!$tmp.Contains($tag)) {
        [void]$tmp.Add($tag)
    }
}
$tags = $tmp

cd $rootdir

Write-Message "Cleaning Up"
git reset --hard HEAD >$null 2>$null

cd ${workdir}

foreach ($tag in $tags)
{
    $version = $tag
    if ($versionMap.$tag) {
        $version = $versionMap.$tag
    }

    if (!$versionRelease.Contains($version)) {
        Write-Message "跳过${version}：非已发布的版本"
        continue
    }

    cd $rootdir

    $bindir = "${artifactsdir}/${version}/${rid}.${configuration}"
    if (!(Test-Path $bindir)) {
        mkdir -p $bindir >$null 2>$null
    }

    Write-Message "${version}编译中..."

    Write-Message "Cleaning Up"

    git reset --hard $tag >$null 2>$null

    if (Test-Path "${workdir1}/CMakeLists.txt") {
        $workdir = $workdir1
        $clidir  = $clidir1
    } elseif (Test-Path "${workdir2}/CMakeLists.txt") {
        $workdir = $workdir2
        $clidir  = $clidir2
    }

    Fix-Patch

    # 获取short commit id
    $commithash = (git rev-parse --short HEAD)
    $version_nv = $version.TrimStart("v")
    $longcommit = (git rev-parse HEAD)
    $buildhash  = $commithash

    [System.Collections.ArrayList]$libPaths = @()
    $libPath = ""
    [void]$libPaths.Add("${workdir}/cli/fxr/${hostfxr}")
    [void]$libPaths.Add("${rootdir}/bin/${rid}.${configuration}/corehost/${hostfxr}")
    [void]$libPaths.Add("${rootdir}/artifacts/bin/${rid}.${configuration}/corehost/${hostfxr}")
    [void]$libPaths.Add("${rootdir}/Bin/obj/${rid}.${configuration}/corehost/cli/fxr/${configuration}/${hostfxr}")
    [void]$libPaths.Add("${rootdir}/Bin/obj/${rid}.${configuration}/corehost/cli/fxr/Release/${hostfxr}")

    foreach ($path in $libPaths)
    {
        if ((Test-Path $path)) {
            rm $path
        }
    }

    cd ${workdir}

    $config = "

Configuration: ${configuration}
Target: ${RID}
Arch: ${arch}
Version: ${version}
Commit: ${buildhash}
Args: ${pportable} ${pcrossbuild} ${pstripsymbols}"

    Write-Message "Building Config${config}"

    Remove-Unneed-Build

    if (Is-OS($Windows)) {
        Write-VersionInfo
        powershell $workdir/build.cmd ${configuration} ${arch} hostver ${version} apphostver ${version} fxrver ${version} policyver ${version} commit ${buildhash} rid ${RID} rootDir ${rootdir}
    } else {
        Fix-CMake-Version-Detect

        # Fix Missing CMake Args
        $needCMakeArgsVersions = "v5.0.0-preview.1.20120.5", "v5.0.0-preview.2.20160.6"
        $cmakeargs = ""
        if ($needCMakeArgsVersions.Contains($version)) {
            if ($arch -eq "arm") {
                $cmakeargs = "-DCLR_CMAKE_TARGET_ARCH_ARM=1"
            } elseif ($arch -eq "arm64") {
                $cmakeargs = "-DCLR_CMAKE_TARGET_ARCH_ARM64=1"
            }
        }

        if ($cmakeargs) {
            bash $workdir/build.sh -${configuration} -${arch} -hostver ${version} -apphostver ${version} -fxrver ${version} -policyver ${version} -commithash ${buildhash} /p:CheckEolTargetFramework=False -cmakeargs $cmakeargs
        } else {
            bash $workdir/build.sh -${configuration} -${arch} -hostver ${version} -apphostver ${version} -fxrver ${version} -policyver ${version} -commithash ${buildhash} /p:CheckEolTargetFramework=False
        }
    }

    foreach ($path in $libPaths)
    {
        if ((Test-Path $path)) {
            $libPath = $path
            break
        }
    }

    if ($libPath) {
        cp $libPath "${bindir}/${hostfxr}"

        if (!$versionBuilt.Contains($version)) {
            [void]$versionBuilt.Add($version)
        }

        $versionBuilt | Sort-Object | ConvertTo-Json -AsArray | Out-File -FilePath "${scriptdir}/VersionBuilt.json"

        Write-Message "${version}编译完成"
    } else {
        Write-Message "${version}编译失败" $true
    }

    Write-Message "Cleaning Up"

    git reset --hard ${tag} >$null 2>$null

    cd ${rootdir}

    dir -r "CMakeCache.txt" | ForEach-Object {
        rm $_
    }
    dir -r "CMakeLists.txt" | ForEach-Object {
        rm $_
    }

    cd ${workdir}
}

cd ${rootdir}

Write-Message "所有版本编译完成"
