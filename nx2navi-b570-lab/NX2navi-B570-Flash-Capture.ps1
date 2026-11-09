# NX2navi native Windows PC port: Intel Arc B570 flash / long-frame capture.
# Uses the user's existing working Test 17 launcher. Does not edit game data,
# launcher scripts, installed binaries, settings INI, or shader caches.
[CmdletBinding()]
param(
    [string]$Launcher = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'NX2navi-B570-Prebuild-Test.ps1'),
    [ValidateRange(64, 240)]
    [int]$HistoryFrames = 120,
    [ValidateRange(0, 10000)]
    [int]$SpikeMs = 120
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Launcher -PathType Leaf)) {
    throw "Working Test 17 launcher not found: $Launcher . Supply -Launcher 'C:\path\NX2navi-B570-Prebuild-Test.ps1'."
}
$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop) { $desktop = $env:USERPROFILE }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$results = Join-Path $desktop ("NX2navi-Native-Flash-{0}" -f $stamp)
$flight = Join-Path $results 'flight'
New-Item -ItemType Directory -Path $flight -Force | Out-Null
$vars = [ordered]@{
    NX2NAVI_APP_POOL        = '0x300000000'   # Known-working 12 GiB, NOT 16 GiB
    NX2NAVI_WINDOW_SIZE     = '1920x1080'
    NX2NAVI_PIPE_SKIP       = 'strict'
    NX2NAVI_FLIGHT          = '1'
    NX2NAVI_FLIGHT_FRAMES   = "$HistoryFrames"
    NX2NAVI_FLIGHT_SPIKE_MS = "$SpikeMs"
    NX2NAVI_FLIGHT_THUMBS   = '1'
    NX2NAVI_FLIGHT_DIR      = $flight
    NX2NAVI_FLIGHT_AT       = $null
    NX2NAVI_MOVIE_SKIP     = $null           # User requested normal full intro
}
$prior = @{}
$gameLog = Join-Path $env:LOCALAPPDATA 'Programs\NX2navi\game\logs\nx2navi.log'
$launchTime = Get-Date
$exit = 'unknown'
Write-Host 'NX2navi native PC-port flash capture (Intel Arc B570)' -ForegroundColor Cyan
Write-Host 'Preserves the existing Test 17 settings and pipeline prebuild.' -ForegroundColor Green
Write-Host "Capture location: $results"
Write-Host 'After a white flash, press F8 while the game has focus; keep playing for 8-10 seconds.'
Write-Host 'Long frames will also trigger a capture automatically. Close the game normally after a short test.'
Write-Host 'Do not run an emulator as part of this test.'
try {
    foreach ($key in $vars.Keys) {
        $prior[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $vars[$key], 'Process')
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Launcher -Test Baseline
    $exit = $LASTEXITCODE
} finally {
    foreach ($key in $vars.Keys) {
        [Environment]::SetEnvironmentVariable($key, $prior[$key], 'Process')
    }
    $summary = @(
        'NX2navi native PC-port Intel Arc B570 flash capture'
        ("Started: {0}" -f $launchTime.ToString('o'))
        ("Child exit code: {0}" -f $exit)
        ("Test 17 launcher: {0}" -f $Launcher)
        'Baseline: 12 GiB guest pool, 1920x1080 window, PIPE_SKIP=strict; working Test17 pipeline prebuild'
        ("Flight frames: {0}; automatic spike: {1} ms; manual trigger: F8" -f $HistoryFrames, $SpikeMs)
        'No movie skipping; graphics caches and saves untouched'
    )
    if (Test-Path -LiteralPath $gameLog -PathType Leaf) {
        if ((Get-Item -LiteralPath $gameLog).LastWriteTime -ge $launchTime.AddSeconds(-5)) {
            Copy-Item -LiteralPath $gameLog -Destination (Join-Path $results 'nx2navi.log') -Force
            $summary += 'Game log: copied from this session'
            $summary += @(Select-String -LiteralPath $gameLog -Pattern 'flight: dump|flight: on:|frametime: (60 s:|exit:)|FATAL:' |
                Select-Object -Last 15 | ForEach-Object { $_.Line })
        } else {
            $summary += 'WARNING: game log not updated during this session'
        }
    } else {
        $summary += 'WARNING: game log not found'
    }
    $dumps = @(Get-ChildItem -LiteralPath $flight -Recurse -File -Filter 'frames.tsv' -ErrorAction SilentlyContinue)
    $summary += ("Flight dump frame tables: {0}" -f $dumps.Count)
    if ($dumps.Count -eq 0) {
        $summary += 'No frames.tsv: F8 might not have triggered or the game closed before 30 post-trigger frames.'
    }
    $summary | Set-Content -LiteralPath (Join-Path $results 'summary.txt') -Encoding UTF8
    $zip = "$results.zip"
    try {
        Compress-Archive -LiteralPath $results -DestinationPath $zip -CompressionLevel Fastest -Force
        Write-Host "Result ZIP: $zip" -ForegroundColor Green
    } catch {
        Write-Warning "Could not ZIP results ($($_.Exception.Message)); files remain at $results"
    }
    $summary | ForEach-Object { Write-Host $_ }
    Write-Host 'Review logs before sharing: they may contain local Windows paths. No upload is automatic.'
}
