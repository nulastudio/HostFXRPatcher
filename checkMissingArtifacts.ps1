$rootdir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$artifactsdir = "${rootdir}/artifacts"


if (!(Test-Path "${artifactsdir}")) {
    Write-Host "no artifacts found"
    exit
}

$arches = "win-x86", "win-x64", "linux-x64", "osx-x64"

function Check-Arch($path) {
    $segment = $path.Split("/")
    $version = $segment[($segment.Count - 1)]
    foreach ($arch in $arches) {
        if (!(Test-Path "${path}/${arch}.Release")) {
            Write-Host "${version} does not contain arch ${arch}"
        }
    }
}

Get-ChildItem $artifactsdir | ForEach-Object -Process {
    if ($_.psiscontainer) {
        Check-Arch -Path "${artifactsdir}/$($_.Name)"
    }
}
