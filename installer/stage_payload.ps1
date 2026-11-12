$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root "build"
$payload = Join-Path $PSScriptRoot "payload"
$assets = Join-Path $PSScriptRoot "assets"

if (-not (Test-Path (Join-Path $src "FH_KAOK.exe"))) {
    throw "FH_KAOK.exe not found in build/. Run build.bat + deploy.bat first."
}

if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
New-Item -ItemType Directory -Force -Path $payload, $assets | Out-Null

$files = @(
    "FH_KAOK.exe","Qt6Core.dll","Qt6Gui.dll","Qt6Multimedia.dll","Qt6Network.dll",
    "Qt6Svg.dll","Qt6Widgets.dll","opengl32sw.dll","d3dcompiler_47.dll","dxcompiler.dll",
    "dxil.dll","avcodec-61.dll","avformat-61.dll","avutil-59.dll","swresample-5.dll",
    "swscale-8.dll","vc_redist.x64.exe"
)
foreach ($f in $files) {
    $from = Join-Path $src $f
    if (Test-Path $from) { Copy-Item -Force $from $payload }
}
foreach ($d in @("platforms","styles","imageformats","iconengines","multimedia","generic","networkinformation","tls")) {
    $from = Join-Path $src $d
    if (Test-Path $from) { Copy-Item -Recurse -Force $from (Join-Path $payload $d) }
}

Write-Host "Payload staged:" (Get-ChildItem $payload -Recurse -File | Measure-Object).Count "files"
