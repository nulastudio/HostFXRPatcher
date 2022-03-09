$checkArch = "linux-arm", "linux-arm64"

Get-ChildItem "./artifacts/*" | ForEach-Object {
    if ($_ -is [System.IO.DirectoryInfo]) {
        $baseDir = $_.FullName
        $version = $_.Name
        foreach ($arch in $checkArch) {
            $lib = "${baseDir}/${arch}.Release/libhostfxr.so"
            if (Test-Path($lib)) {
                $dependencies = "$(readelf -d $lib | grep NEEDED)"

                $needLib = "ld-linux"
                if ($arch -eq "linux-arm") {
                    $needLib = "ld-linux-armhf"
                }
                if ($arch -eq "linux-arm64") {
                    $needLib = "ld-linux-aarch64"
                }

                if (!$dependencies.Contains($needLib)) {
                    $curLib = ""
                    if ($dependencies -match "ld-linux-(\w+)") {
                        $curLib = $matches[0]
                    }

                    Write-Host "${version} ${arch} is wrong, need ${needLib}, current is ${curLib}"
                }
            }
        }
    }
}
