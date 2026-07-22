$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Windows counterpart of ci/setup_sdk.sh. cjv v0.2.20 publishes Windows x64,
# and the selected matrix contains Windows x64 only.
$Toolchain = if ($env:CJCJ_TOOLCHAIN) { $env:CJCJ_TOOLCHAIN } else { "nightly-1.2.0-alpha.20260721165458" }
$CjvVersion = if ($env:CJV_VERSION) { $env:CJV_VERSION } else { "v0.2.20" }
$HeapSize = if ($env:CJ_HEAP_SIZE) { $env:CJ_HEAP_SIZE } else { "12GB" }
$Tools = Join-Path $HOME ".local\bin"
$Cjv = Join-Path $Tools "cjv.exe"

function Write-SetupLog([string] $Message) {
    Write-Host "[platform setup_sdk.ps1] $Message"
}

$HostArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
if ($HostArch -ne "X64") { throw "unsupported Windows architecture: $HostArch" }

if (-not (Test-Path $Cjv)) {
    New-Item -ItemType Directory -Force -Path $Tools | Out-Null
    $Archive = Join-Path $env:RUNNER_TEMP "cjv_windows_amd64.zip"
    $Extract = Join-Path $env:RUNNER_TEMP "cjv-windows"
    $Url = "https://github.com/Zxilly/cjv/releases/download/$CjvVersion/cjv_windows_amd64.zip"
    Write-SetupLog "install cjv $CjvVersion from $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Archive
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Extract
    Expand-Archive -Path $Archive -DestinationPath $Extract
    $Downloaded = Get-ChildItem -Path $Extract -Filter "cjv.exe" -Recurse | Select-Object -First 1
    if (-not $Downloaded) { throw "cjv.exe missing from $Archive" }
    Copy-Item $Downloaded.FullName $Cjv
}

$env:Path = "$Tools;$env:Path"
if ($env:GITCODE_API_KEY) {
    & $Cjv set gitcode-api-key $env:GITCODE_API_KEY *> $null
    Write-SetupLog "gitcode-api-key set"
}
Write-SetupLog "cjv install $Toolchain -c stdx"
& $Cjv install $Toolchain -c stdx
if ($LASTEXITCODE -ne 0) { throw "cjv install failed with exit code $LASTEXITCODE" }

$CangjieHome = Join-Path $HOME ".cjv\toolchains\$Toolchain"
$StdxPath = Join-Path $HOME ".cjv\stdx\$Toolchain\static\stdx"
if (-not (Test-Path $CangjieHome -PathType Container)) {
    throw "toolchain directory missing: $CangjieHome"
}
$Paths = @(
    (Join-Path $CangjieHome "bin"),
    (Join-Path $CangjieHome "tools\bin"),
    (Join-Path $CangjieHome "runtime\lib\windows_x86_64_cjnative"),
    (Join-Path $CangjieHome "tools\lib"),
    $Tools
)
if ($env:GITHUB_ENV) {
    "CANGJIE_HOME=$CangjieHome" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
    "CANGJIE_STDX_PATH=$StdxPath" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
    "cjHeapSize=$HeapSize" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
    "PATH=$($Paths -join ';');$env:PATH" | Out-File $env:GITHUB_ENV -Encoding utf8 -Append
    $Paths | Out-File $env:GITHUB_PATH -Encoding utf8 -Append
}
Write-SetupLog "CANGJIE_HOME=$CangjieHome"
