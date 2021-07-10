param
(
    $RID,
    $Configuration,
    [switch]$Portable,
    [switch]$Cross,
    [switch]$Stripsymbols
)

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
    $PRODUCTNAME = "Microsoft\xae .NET Framework"
    $PRODUCTVERSION = "0,0,0,0"
    $PRODUCTVERSION_STR = "${PRODUCTVERSION} @Commit: ${longcommit}"
    $FILEVERSION = "0,0,0,0"
    $FILEVERSION_STR = "${FILEVERSION} @Commit: ${longcommit}"
    $LEGALCOPYRIGHT = "\xa9 Microsoft Corporation. All rights reserved."

    $content = Get-Content -Path ${rootdir}/version_info.h
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
    $content = Get-Content -Path ${rootdir}/eng/native/build-commons.sh
    $content = $content.Replace("[0-9]+\.[0-9]+\.[0-9]+$", "[0-9]+\.[0-9]+\.[0-9]+")
    $content | Out-File ${rootdir}/eng/native/build-commons.sh
}

function Delete-Unneed-Build {
    $content = Get-Content -Path ${workdir}/cli/CMakeLists.txt
    $content = $content.Replace("add_subdirectory(apphost)", "")
    $content = $content.Replace("add_subdirectory(dotnet)", "")
    $content = $content.Replace("add_subdirectory(nethost)", "")
    $content = $content.Replace("add_subdirectory(test_fx_ver)", "")
    $content = $content.Replace("add_subdirectory(hostpolicy)", "")
    $content = $content.Replace("add_subdirectory(test)", "")
    $content | Out-File ${workdir}/cli/CMakeLists.txt
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

$rootdir      = Format-Path "${pwd}"
$workdir      = Format-Path "${rootdir}/src/installer/corehost"
$clidir       = Format-Path "${workdir}/cli"
$artifactsdir = Format-Path "${rootdir}/artifacts-patched"
$patch        = Format-Path "${rootdir}/0001-fix-additionalProbingPaths-resolver.patch"

$arch=$RID.Split('-')[1]
$configuration=$Configuration

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
    mkdir -p $artifactsdir
}

$versionMap = (Get-Content "VersionMapping.json") | ConvertFrom-Json
[System.Collections.ArrayList]$versionBuilt = @()
[System.Collections.ArrayList]$versionRelease = @()

if (Test-Path("VersionBuilt.json")) {
    $json = (Get-Content "VersionBuilt.json") | ConvertFrom-Json -NoEnumerate
    if ($json) {
        $versionBuilt = $json
    }
}

if (Test-Path("VersionReleased.json")) {
    $json = (Get-Content "VersionReleased.json") | ConvertFrom-Json -NoEnumerate
    if ($json) {
        $versionRelease = $json
    }
}

[System.Collections.ArrayList]$tags = @()

# 版本过滤
foreach ($tag in (git tag))
{

    # 只编译5.x
    if ($tag -like "v5*") {
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

# $tags = @()

# 自定义版本编译
# $tags = "v5.0.0", "v5.0.1"
# 追加版本编译
# $tags = @()
# $tags.Add("v5.0.0")
# $tags.Add("v5.0.1")

# 去重
[System.Collections.ArrayList]$tmp = @()
foreach ($tag in $tags) {
    if (!$tmp.Contains($tag)) {
        [void]$tmp.Add($tag)
    }
}
$tags = $tmp

cd ${workdir}

foreach ($tag in $tags)
{
    $version = $tag
    if ($versionMap.$tag) {
        $version = $versionMap.$tag
    }
    if (!$versionRelease.Contains($version)) {
        Write-Host "跳过编译${version}..."
        continue
    }
    cd $rootdir
    $bindir = "${artifactsdir}/${version}/${rid}.${configuration}"
    if (!(Test-Path $bindir)) {
        mkdir -p $bindir
    }
    Write-Host "${version}编译中..."

    git reset --hard HEAD
    git checkout $tag

    # 获取short commit id
    $commithash = (git rev-parse --short HEAD)
    $version_nv = $version.TrimStart("v")
    $longcommit = (git rev-parse HEAD)
    $buildhash  = $commithash
    git am $patch
    git am --continue

    $libPath1   = "${workdir}/cli/fxr/${hostfxr}"
    $libPath2   = "${rootdir}/bin/${rid}.${configuration}/corehost/${hostfxr}"
    $libPath3   = "${rootdir}/artifacts/bin/${rid}.${configuration}/corehost/${hostfxr}"
    $libPath4   = "${rootdir}/Bin/obj/${rid}.${configuration}/corehost/cli/fxr/${configuration}/${hostfxr}"
    $libPath5   = "${rootdir}/Bin/obj/${rid}.${configuration}/corehost/cli/fxr/Release/${hostfxr}"
    $libPath    = ""
    if ((Test-Path $libPath1)) {
        rm $libPath1
    }
    if ((Test-Path $libPath2)) {
        rm $libPath2
    }
    if ((Test-Path $libPath3)) {
        rm $libPath3
    }
    if ((Test-Path $libPath4)) {
        rm $libPath4
    }
    if ((Test-Path $libPath5)) {
        rm $libPath5
    }
    cd ${workdir}
    $config = "
Configuration: ${configuration}
Arch: ${arch}
Version: ${version}
Commit: ${buildhash}"
    if ($Portable) {
        $config = "${config}
-portablebuild"
    }
    if ($Cross) {
        $config = "${config}
-cross"
    }
    if ($Stripsymbols) {
        $config = "${config}
-stripsymbols"
    }
    Write-Host "building ${config}"
    Delete-Unneed-Build
    if (Is-OS($Windows)) {
        Write-VersionInfo
        powershell $workdir/build.cmd ${configuration} ${arch} hostver ${version} apphostver ${version} fxrver ${version} policyver ${version} commit ${buildhash} ${pportable} rid ${RID} rootDir ${rootdir}
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
    if ((Test-Path $libPath1)) {
        $libPath = $libPath1
    } elseif ((Test-Path $libPath2)) {
        $libPath = $libPath2
    } elseif ((Test-Path $libPath3)) {
        $libPath = $libPath3
    } elseif ((Test-Path $libPath4)) {
        $libPath = $libPath4
    } elseif ((Test-Path $libPath5)) {
        $libPath = $libPath5
    }
    if ($libPath) {
        cp $libPath "${bindir}/${hostfxr}"
        if (!$versionBuilt.Contains($version)) {
            [void]$versionBuilt.Add($version)
        }
        $versionBuilt | Sort-Object | ConvertTo-Json -AsArray | Out-File -FilePath "${rootdir}/VersionBuilt.json"
        Write-Host "${version}编译完成
"
    } else {
        Write-Host "无法找到${version}编译后fxr位置
"
    }
    git am --abort
    git reset --hard ${tag}
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
