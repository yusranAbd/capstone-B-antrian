# Packaging guard only: never deploys, modifies a server or changes credentials.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
  [string]$FlutterExecutable = 'flutter',
  [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
$publicUri = $null
if (-not [Uri]::TryCreate($ApiBaseUrl, [UriKind]::Absolute, [ref]$publicUri) -or
    $publicUri.Scheme -ne 'https' -or $publicUri.UserInfo -or $publicUri.Query -or $publicUri.Fragment -or
    -not $publicUri.AbsolutePath.TrimEnd('/').EndsWith('/api/v1')) {
  throw 'API publik wajib HTTPS, berakhir /api/v1, tanpa kredensial, query atau fragment.'
}
$apiHostName = $publicUri.DnsSafeHost.Trim('[', ']').ToLowerInvariant()
if ($publicUri.IsLoopback -or $apiHostName -eq 'localhost' -or
    $apiHostName -match '(^|\.)(local|localhost|internal|example|invalid|test)$' -or
    $apiHostName -match '(^|\.)example\.(com|net|org)$') {
  throw 'Endpoint development/placeholder tidak boleh dikemas sebagai build publik.'
}
$parsedAddress = $null
if ([Net.IPAddress]::TryParse($apiHostName, [ref]$parsedAddress)) {
  if ($parsedAddress.IsIPv4MappedToIPv6) { $parsedAddress = $parsedAddress.MapToIPv4() }
  $octets = $parsedAddress.GetAddressBytes()
  if ([Net.IPAddress]::IsLoopback($parsedAddress) -or $parsedAddress.IsIPv6LinkLocal -or
      ($octets.Length -eq 16 -and (($octets[0] -band 254) -eq 252)) -or
      ($octets.Length -eq 4 -and (
        $octets[0] -in @(0,10,127) -or
        ($octets[0] -eq 169 -and $octets[1] -eq 254) -or
        ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) -or
        ($octets[0] -eq 192 -and $octets[1] -eq 168)))) {
    throw 'Alamat loopback/private tidak boleh dikemas sebagai API publik.'
  }
}
if ($ValidateOnly) {
  Write-Output 'Validasi struktur URL lulus; DNS, TLS, API dan origin tetap harus diverifikasi.'
  exit 0
}
$clientDirectory = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $clientDirectory
try {
  & $FlutterExecutable build web --release --output build/web-public `
    "--dart-define=API_BASE_URL=$($publicUri.AbsoluteUri.TrimEnd('/'))" `
    '--dart-define=SERVICE_TIME_ZONE=Asia/Jakarta'
  if ($LASTEXITCODE -ne 0) { throw 'Build publik gagal; tidak ada deployment.' }
} finally {
  Pop-Location
}
