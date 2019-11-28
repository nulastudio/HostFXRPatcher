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
$workdir      = Format-Path "${rootdir}/src/corehost"
$clidir       = Format-Path "${workdir}/cli"
$artifactsdir = Format-Path "${rootdir}/artifacts-patched"
$patch        = Format-Path "${rootdir}/0001-fix-additionalProbingPaths-resolver.patch"
$patch2       = Format-Path "${rootdir}/0002-use-pre-install-sdk.patch"

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
    $pportable = "portable"
}
if ($Cross) {
    $pcrossbuild = "--cross"
}
if ($Stripsymbols) {
    $pstripsymbols = "--stripsymbols"
}

$tags=(git tag)

if (!(Test-Path $artifactsdir)) {
    mkdir -p $artifactsdir
}

$versionMap = (Get-Content "VersionMapping.json") | ConvertFrom-Json

# 增量编译
# 每次发布新版本之后在这里写
# DO NOT DELETE THIS LINE
# $tags = "v3.0.0-preview-27122-01", "v3.0.0-preview-27324-5"
# $tags = "v2.0.0"

foreach ($tag in $tags)
{
    # 只编译2.x以及3.x
    if (($tag -like "v2*") -or ($tag -like "v3*")) {
        # 2.x版本只编译正式版
        if (($tag -like "v2*") -and ($tag -match "[^v\d\.]")) {
            continue
        }
        $version = $tag
        if ($versionMap.$tag) {
            $version = $versionMap.$tag;
        }
        cd $rootdir
        $bindir = "${artifactsdir}/${version}/${rid}.${configuration}"
        if (!(Test-Path $bindir)) {
            mkdir -p $bindir
        }
        Write-Host "${version}编译中..."
        git reset --hard HEAD
        git checkout $tag
        git am $patch
        git am $patch2
        git am --continue
        # 获取short commit id
        $commithash = (git rev-list --all --max-count=1 --abbrev-commit)
        $version_nv = $version.TrimStart("v")
        $longcommit = (git rev-list --all --max-count=1)
        $buildhash  = $commithash
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
portable"
        }
        if ($Cross) {
            $config = "${config}
crossbuild"
        }
        if ($Stripsymbols) {
            $config = "${config}
stripsymbols"
        }
        Write-Host "building ${config}"
        if (Is-OS($Windows)) {
            Write-VersionInfo
            powershell $workdir/build.cmd ${configuration} ${arch} hostver ${version} apphostver ${version} fxrver ${version} policyver ${version} commit ${buildhash} ${pportable} rid ${RID}
        } else {
            bash $workdir/build.sh --configuration ${configuration} --arch ${arch} --hostver ${version} --apphostver ${version} --fxrver ${version} --policyver ${version} --commithash ${buildhash} -${pportable} ${pcrossbuild} ${pstripsymbols}
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
        } else {
            Write-Host "无法找到${version}编译后fxr位置"
        }
        git am --abort
        git reset --hard ${tag}
        if ((Test-Path "${workdir}/CMakeCache.txt")) {
            rm "${workdir}/CMakeCache.txt"
        }
        cd ${clidir}
        git clean -df
        cd ${workdir}
        Write-Host "${version}编译完成
"
    }
}

cd ${rootdir}
