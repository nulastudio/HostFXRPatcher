function Get-Separator
{
    return (Join-Path . .).Trim('.')
}

function Format-Path($path)
{
    $separator = Get-Separator
    return "${path}".Replace('/', $separator).Replace('\', $separator)
}

function Get-NetworkString($url)
{
    $webClient = New-Object System.Net.WebClient
    $webClient.Encoding = [System.Text.Encoding]::UTF8
    return $webClient.DownloadString($url)
}

$rootdir = Format-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition)

[System.Collections.ArrayList]$versions = @()

$releasesIndexUrl = "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json"

$releasesIndex = (Get-NetworkString $releasesIndexUrl) | ConvertFrom-Json

foreach ($releaseIndex in $releasesIndex."releases-index") {
    # 不需要1.x版本
    if ($releaseIndex."channel-version" -match "^1") {
        continue
    }
    $releaseJsonUrl = $releaseIndex."releases.json"
    $releaseJson = (Get-NetworkString $releaseJsonUrl) | ConvertFrom-Json
    foreach ($release in $releaseJson."releases") {
        $sdks = $release."sdks"
        if (!$sdks) {
            $sdks = @($release."sdk")
        }
        foreach ($sdk in $sdks) {
            $runtimeVersion = ""
            if ($sdk."runtime-version") {
                $runtimeVersion = $sdk."runtime-version"
            } else {
                $runtimeVersion = $release."runtime"."version"
            }
            # 2.x版本只需要正式版
            if (($runtimeVersion -match "^2") -and ($runtimeVersion -match "[^\d\.]")) {
                continue
            }
            $runtimeVersion = "v${runtimeVersion}"
            if ($versions.Contains($runtimeVersion)) {
                continue
            }
            # Write-Host "${runtimeVersion} found."
            [void]$versions.Add($runtimeVersion)
        }
    }
}

$json = $versions | Sort-Object | ConvertTo-Json

if (!$json) {
    $json = "[]"
}

WriteFile -Path "${rootdir}/VersionReleased.json" -Value $json
