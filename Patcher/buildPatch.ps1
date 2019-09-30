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
    Write-Host "--rid <RID> --configuration <Configuration=Debug|Release> [--portable] [--cross] [--stripsymbols]"
}

function Check-Arguments
{
    if (!$RID) {
        Print-Usage
        exit
    }
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
    $pportable = "-portable"
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

# 增量编译
# 每次发布新版本之后在这里写
$tags="v2.0.0","v3.0.0","v3.0.0-rc1-19456-20"
# $tags="v3.0.0"

foreach ($tag in $tags)
{
    # 只编译2.x以及3.x
    if (($tag -like "v2*") -or ($tag -like "v3*")) {
        # 2.x版本只编译正式版
        if (($tag -like "v2*") -and ($tag -match "[^v\d\.]")) {
            continue
        }
        cd $rootdir
        $bindir = "${artifactsdir}/${tag}/${rid}.${configuration}"
        if (!(Test-Path $bindir)) {
            mkdir -p $bindir
        }
        Write-Host "${tag}编译中..."
        $version = $tag
        git reset --hard HEAD
        git checkout $tag
        git am $patch
        git am --continue
        # 获取short commit id
        $commithash = (git rev-list --all --max-count=1 --abbrev-commit)
        $buildhash  = $commithash
        $libPath1   = "${workdir}/cli/fxr/${hostfxr}"
        $libPath2   = "${rootdir}/bin/${rid}.${configuration}/corehost/${hostfxr}"
        $libPath3   = "${rootdir}/artifacts/bin/${rid}.${configuration}/corehost/${hostfxr}"
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
        cd ${workdir}
        $config = "--configuration ${configuration} --arch ${arch} --hostver ${version} --apphostver ${version} --fxrver ${version} --policyver ${version} --commithash ${buildhash} ${pportable} ${pcrossbuild} ${pstripsymbols}"
        Write-Host "building ${config}"
        if (Is-OS($Windows)) {
            # TODO: windows build
            Write-Host "TODO: windows build"
            exit
        } else {
            bash $workdir/build.sh --configuration ${configuration} --arch ${arch} --hostver ${version} --apphostver ${version} --fxrver ${version} --policyver ${version} --commithash ${buildhash} ${pportable} ${pcrossbuild} ${pstripsymbols}
        }
        if ((Test-Path $libPath1)) {
            $libPath = $libPath1
        } elseif ((Test-Path $libPath2)) {
            $libPath = $libPath2
        } elseif ((Test-Path $libPath3)) {
            $libPath = $libPath3
        }
        cp $libPath "${bindir}/${hostfxr}"
        git am --abort
        git reset --hard ${tag}
        if ((Test-Path "${workdir}/CMakeCache.txt")) {
            rm "${workdir}/CMakeCache.txt"
        }
        cd ${clidir}
        git clean -df
        cd ${workdir}
        Write-Host "${tag}编译完成
"
    }
}
