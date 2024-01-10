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

function Resolve-Compatibility-Path($Rid, $Runtimes, $level = 1, $index = 0) {
    [System.Collections.ArrayList]$result = @()

    if ($Runtimes.Contains($Rid) && $Runtimes.$Rid.Contains("#import")) {
        $map = $Runtimes.$Rid."#import"

        foreach($path in $map)
        {
            $index++
            [void]$result.Add(@{"index" = $index; "level" = $level; "rid" = $path})

            $_all = Resolve-Compatibility-Path $path $Runtimes ($level+1) ($index)

            foreach($_path in $_all)
            {
                $index = $_path."index"
                [void]$result.Add($_path)
            }
        }
    }

    return $result
}

function Resolve-Compatibility-Array($Rid, $Runtimes) {
    $result = Resolve-Compatibility-Path $Rid $Runtimes | Sort-Object -Property @{Expression = "level"; Descending = $false},@{Expression = "index"; Descending = $false}

    [System.Collections.ArrayList]$all = @($Rid)

    foreach($rid in $result)
    {
        if (!$all.Contains($rid."rid")) {
            [void]$all.Add($rid."rid")
        }
    }

    return $all
}

$compatibilityJsonUrl = "https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/Microsoft.NETCore.Platforms/src/runtime.json"

$compatibilityJson = (Get-NetworkString $compatibilityJsonUrl) | ConvertFrom-Json -AsHashTable
$supportedJson = (Get-Content $supportedpath) | ConvertFrom-Json

$minifyCompatibilityJson = @{}

foreach($runtime in $compatibilityJson."runtimes".GetEnumerator())
{
    $runtimes = Resolve-Compatibility-Array $runtime.Key $compatibilityJson."runtimes"

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
        $minifyCompatibilityJson[$runtime.Key] = $minifyRuntimes
    }
}

Sort-Dict -Dict $minifyCompatibilityJson | ConvertTo-Json -Compress | Out-File -NoNewline -Encoding "Utf8NoBom" $compatibilitypath
