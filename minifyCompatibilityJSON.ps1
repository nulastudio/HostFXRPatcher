$rootdir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$artifactsdir = "${rootdir}/artifacts"
$compatibilitypath = "${artifactsdir}/runtime.compatibility.json"
$supportedpath = "${artifactsdir}/runtime.supported.json"

function Get-NetworkString($url)
{
    $webClient = New-Object System.Net.WebClient
    $webClient.Encoding = [System.Text.Encoding]::UTF8
    return $webClient.DownloadString($url)
}

function Sort-Dict($Dict) {
    $hashtable = [ordered]@{}
    foreach ($key in $Dict.GetEnumerator() | Sort-Object -Property Name) {
        $hashtable[$key.Key] = $key.Value
    }
    return $hashtable
}

$compatibilityJsonUrl = "https://raw.githubusercontent.com/dotnet/runtime/master/src/libraries/pkg/Microsoft.NETCore.Platforms/runtime.compatibility.json"

$compatibilityJson = (Get-NetworkString $compatibilityJsonUrl) | ConvertFrom-Json
$supportedJson = (Get-Content $supportedpath) | ConvertFrom-Json

$minifyCompatibilityJson = @{}

foreach($runtime in $compatibilityJson.psobject.properties.name)
{
    $runtimes = $compatibilityJson.$runtime
    [System.Collections.ArrayList]$minifyRuntimes = @()
    foreach($supportedRuntime in $supportedJson)
    {
        if ($runtimes.Contains($supportedRuntime)) {
            [void]$minifyRuntimes.Add($supportedRuntime)
            # NOTE: 原来的json已经拥有优先级，第一个匹配出来的必然是最优选择，添加一个就够了
            break
        }
    }
    if ($minifyRuntimes.Length) {
        $minifyCompatibilityJson[$runtime] = $minifyRuntimes
    }
}

Sort-Dict -Dict $minifyCompatibilityJson | ConvertTo-Json -Compress | Out-File -NoNewline -Encoding Utf8NoBom $compatibilitypath
