$rootdir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$artifactsdir = "${rootdir}/artifacts"
$artifactspath = "${artifactsdir}/ArtifactsVersion.json"
$artifactstxtpath = "${artifactsdir}/ArtifactsVersion.txt"
$md5path = "${artifactsdir}/Md5.json"

$ArtifactsVersion = @{}
$Md5 = @{}
[bool]$script:hasUpdate = $false

if (Test-Path($artifactspath)) {
    $json = (Get-Content $artifactspath) | ConvertFrom-Json
    foreach($key in $json.psobject.properties.name)
    {
        $ArtifactsVersion[$key] = $json.$key
    }
}

if (Test-Path($md5path)) {
    $json = (Get-Content $md5path) | ConvertFrom-Json
    foreach($key in $json.psobject.properties.name)
    {
        $Md5[$key] = $json.$key
    }
}

function Write-Runtime-JSON() {
    if (!($ArtifactsVersion.Contains("runtime/compatibility"))) {
        $ArtifactsVersion["runtime/compatibility"] = "0"
        $script:hasUpdate = $true
    }
    if (!($ArtifactsVersion.Contains("runtime/supported"))) {
        $ArtifactsVersion["runtime/supported"] = "0"
        $script:hasUpdate = $true
    }
}

Write-Runtime-JSON

function File-MD5($File) {
    return (Get-FileHash $File -Algorithm MD5).Hash
}

$arches = (Get-Content "${artifactsdir}/runtime.supported.json") | ConvertFrom-Json

function Update-Artifact($Artifact) {
    [int]$version = 0
    [void][int]::TryParse($ArtifactsVersion[$Artifact], [ref]$version)
    $version++
    $ArtifactsVersion[$Artifact] = $version.ToString()
}

function Check-Arch($path) {
    $segment = $path.Split("/")
    $version = $segment[($segment.Count - 1)]
    foreach ($arch in $arches) {
        $abspath = "${path}/${arch}.Release"
        if (Test-Path $abspath) {
            $key = "${version}/${arch}"
            $files = Get-ChildItem $abspath
            $filecount = ($files | Measure-Object).Count
            $file = ""
            if ($filecount -eq 0) {
                continue
            } else {
                if ($filecount -eq 1) {
                    $file = $files.FullName
                } else {
                    $file = $files[0].FullName
                }
            }
            $filemd5 = File-MD5 -File $file
            # if (!($Md5.Contains($key))) {
            #     $Md5[$key] = ""
            # }

            if (!($ArtifactsVersion.Contains($key))) {
                Write-Host "Add ${key}"
                $ArtifactsVersion[$key] = "0"
                $Md5[$key] = $filemd5
                $script:hasUpdate = $true
            } elseif ($Md5[$key] -ne $filemd5) {
                Write-Host "Update ${key}"
                Update-Artifact -Artifact $key
                $Md5[$key] = $filemd5
                $script:hasUpdate = $true
            }
        }
    }
}

if (Test-Path "${artifactsdir}") {
    Get-ChildItem $artifactsdir | ForEach-Object -Process {
        if ($_.psiscontainer) {
            Check-Arch -Path "${artifactsdir}/$($_.Name)"
        }
    }
}

$ht_runtime = @{
    "runtime/compatibility"=(File-MD5 -File "${artifactsdir}/runtime.compatibility.json");
    "runtime/supported"=(File-MD5 -File "${artifactsdir}/runtime.supported.json");
}

foreach ($key in $ht_runtime.GetEnumerator()) {
    if ($Md5[$key.Key] -ne $key.Value) {
        Write-Host "Update $($key.Key)"
        if ($Md5.Contains($key.Key)) {
            Update-Artifact -Artifact $key.Key
        }
        $Md5[$key.Key] = $key.Value
        $script:hasUpdate = $true
    }
}

function Sort-Dict($Dict) {
    $hashtable = [ordered]@{}
    foreach ($key in $Dict.GetEnumerator() | Sort-Object -Property Name) {
        $hashtable[$key.Key] = $key.Value
    }
    return $hashtable
}

function Full-Update([bool]$UpdateRuntime=$true) {
    $ArtifactsVersion.Keys.Clone() | ForEach-Object {
        if ($UpdateRuntime -or !($_ -like "runtime*")) {
            Update-Artifact -Artifact $_
        }
    }
}

function Update-Runtime-Compatibility-JSON() {
    Update-Artifact -Artifact "runtime/compatibility"
}

function Update-Runtime-Supported-JSON() {
    Update-Artifact -Artifact "runtime/supported"
}

# 更新所有Artifacts
# Full-Update -UpdateRuntime $false
# 更新runtime/compatibility
# Update-Runtime-Compatibility-JSON
# 更新runtime/supported
# Update-Runtime-Supported-JSON

if ($hasUpdate) {
    $timestamp = (([DateTime]::Now.ToUniversalTime().Ticks - 621355968000000000)/10000000).tostring().Substring(0,10)
    $timestamp | Out-File -Encoding "Utf8NoBom" -NoNewline $artifactstxtpath
}

Sort-Dict -Dict $ArtifactsVersion | ConvertTo-Json | Out-File -Encoding "Utf8NoBom" $artifactspath
Sort-Dict -Dict $Md5 | ConvertTo-Json | Out-File -Encoding "Utf8NoBom" $md5path
