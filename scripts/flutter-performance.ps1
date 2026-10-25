param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-zA-Z0-9-]+$')][string]$Label,
    [string]$Flutter = 'flutter',
    [string]$ApiBaseUrl = 'http://localhost:3000/api/v1',
    [string]$ServiceTimeZone = 'Asia/Jakarta',
    [switch]$SplitDebugInfo
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$clientRoot = Join-Path $repoRoot 'apps/client'
$measurementRoot = Join-Path $repoRoot "tmp/flutter-performance/$Label"
New-Item -ItemType Directory -Path $measurementRoot -Force | Out-Null
New-Item -ItemType Directory -Path "$measurementRoot/apk" -Force | Out-Null
$defines = @("--dart-define=API_BASE_URL=$ApiBaseUrl", "--dart-define=SERVICE_TIME_ZONE=$ServiceTimeZone")

function Invoke-FlutterBuild([string]$Name, [string[]]$BuildArguments) {
    & $Flutter @BuildArguments *> "$measurementRoot/$Name.log"
    if ($LASTEXITCODE -ne 0) { throw "Build $Name gagal. Lihat $measurementRoot/$Name.log" }
}

function Clear-GeneratedApkOutput([string]$Variant) {
    # Incremental ZIP packaging can retain holes from removed assets. Recreate
    # only generated APK outputs; keep compiler caches and all source files.
    $allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $clientRoot 'build/app/outputs/apk'))
    $variantRoot = [System.IO.Path]::GetFullPath((Join-Path $allowedRoot $Variant))
    if (-not $variantRoot.StartsWith($allowedRoot + [System.IO.Path]::DirectorySeparatorChar)) { throw 'Output APK di luar direktori build' }
    if (Test-Path -LiteralPath $variantRoot) {
        Get-ChildItem -LiteralPath $variantRoot -File -Filter '*.apk' | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName
        }
    }
}

Push-Location $clientRoot
try {
    & $Flutter --version *> "$measurementRoot/flutter-version.txt"
    Invoke-FlutterBuild 'web' (@('build', 'web', '--release', '--no-wasm-dry-run', "--output=$measurementRoot/web") + $defines)
    Clear-GeneratedApkOutput 'debug'
    Invoke-FlutterBuild 'debug' (@('build', 'apk', '--debug') + $defines)
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-debug.apk' -Destination "$measurementRoot/apk/app-debug.apk"
    $symbols = if ($SplitDebugInfo) { @("--split-debug-info=$measurementRoot/symbols") } else { @() }
    Clear-GeneratedApkOutput 'release'
    Invoke-FlutterBuild 'release' (@('build', 'apk', '--release') + $defines + $symbols)
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination "$measurementRoot/apk/app-release.apk"
    Clear-GeneratedApkOutput 'release'
    Invoke-FlutterBuild 'split' (@('build', 'apk', '--release', '--split-per-abi') + $defines + $symbols)
    Copy-Item -Path 'build/app/outputs/flutter-apk/app-*-release.apk' -Destination "$measurementRoot/apk/"
} finally {
    Pop-Location
}

$webFiles = @(Get-ChildItem -LiteralPath "$measurementRoot/web" -File -Recurse)
$apkFiles = @(Get-ChildItem -LiteralPath "$measurementRoot/apk" -File)
$result = [ordered]@{
    label = $Label
    measuredAt = (Get-Date).ToUniversalTime().ToString('o')
    commit = (git -C $repoRoot rev-parse HEAD)
    splitDebugInfo = [bool]$SplitDebugInfo
    webBytes = ($webFiles | Measure-Object -Property Length -Sum).Sum
    webFiles = @($webFiles | ForEach-Object { @{ path = $_.FullName.Substring($measurementRoot.Length + 1); bytes = $_.Length } })
    apks = @($apkFiles | ForEach-Object { @{ name = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } })
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$measurementRoot/sizes.json" -Encoding utf8
$result | ConvertTo-Json -Depth 5
