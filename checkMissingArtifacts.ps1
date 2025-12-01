$rootdir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$artifactsdir = "${rootdir}/artifacts"


if (!(Test-Path "${artifactsdir}")) {
    Write-Host "no artifacts found"
    exit
}

$arches = (Get-Content "${artifactsdir}/runtime.supported.json") | ConvertFrom-Json

function Check-Arch($path) {
    $segment = $path.Split("/")
    $version = $segment[($segment.Count - 1)]

    foreach ($arch in $arches) {
        if ($arch -eq "win-arm64") {
            if ($version -match "^v1.") {
                continue
            }
            if ($version -match "^v2.") {
                continue
            }
            if ($version -match "^v3.") {
                continue
            }
            if ($version -match "^v5.") {
                continue
            }
        } elseif ($arch -eq "osx-arm64") {
            if ($version -match "^v1.") {
                continue
            }
            if ($version -match "^v2.") {
                continue
            }
            if ($version -match "^v3.") {
                continue
            }
            if ($version -match "^v5.") {
                continue
            }
        } elseif ($arch -eq "linux-loongarch64") {
            if ($version -match "^v1.") {
                continue
            }
            if ($version -match "^v2.") {
                continue
            }
            if ($version -match "^v3.") {
                continue
            }
            if ($version -match "^v5.") {
                continue
            }
            if ($version -match "^v6.") {
                continue
            }
            if ($version -match "^v7.") {
                continue
            }
            if ($version -match "^v8.") {
                continue
            }
            if ($version -match "^v9.") {
                continue
            }
        }

        if (!(Test-Path "${path}/${arch}.Release") -or !(Get-ChildItem "${path}/${arch}.Release").Length) {
            Write-Host "${version} does not contain arch ${arch}"
        }
    }
}

Get-ChildItem $artifactsdir | ForEach-Object -Process {
    if ($_.psiscontainer) {
        Check-Arch -Path "${artifactsdir}/$($_.Name)"
    }
}
