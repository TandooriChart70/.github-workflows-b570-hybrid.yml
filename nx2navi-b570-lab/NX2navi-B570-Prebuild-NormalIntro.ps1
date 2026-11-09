# NX2navi B570: Test17 pipeline prebuild, normal (unskipped) intro.
# Requires Desktop/NX2navi-B570-Prebuild-Test.ps1 from the existing Test 17 setup.
$ErrorActionPreference = 'Stop'
$desktop = [Environment]::GetFolderPath('Desktop')
$launcher = Join-Path $desktop 'NX2navi-B570-Prebuild-Test.ps1'
$log = Join-Path $env:LOCALAPPDATA 'Programs\NX2navi\game\logs\nx2navi.log'
if (-not (Test-Path -LiteralPath $launcher)) { throw "Test 17 launcher not found: $launcher" }
Remove-Item Env:NX2NAVI_MOVIE_SKIP -ErrorAction SilentlyContinue
$env:NX2NAVI_APP_POOL = '0x300000000'
$env:NX2NAVI_WINDOW_SIZE = '1920x1080'
$env:NX2NAVI_PIPE_SKIP = 'strict'
Remove-Item Env:NX2NAVI_PROFILE -ErrorAction SilentlyContinue
Remove-Item Env:NX2NAVI_PROFILE_SLOW -ErrorAction SilentlyContinue
Remove-Item Env:NX2NAVI_TRACE -ErrorAction SilentlyContinue
Remove-Item Env:NX2NAVI_GAME_RES -ErrorAction SilentlyContinue
Write-Host 'Normal intro, pipeline prebuild ON, 12 GiB guest pool.' -ForegroundColor Cyan
try {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Test Baseline
} finally {
    'NX2NAVI_APP_POOL','NX2NAVI_WINDOW_SIZE','NX2NAVI_PIPE_SKIP' | ForEach-Object {
        Remove-Item "Env:$_" -ErrorAction SilentlyContinue
    }
    Remove-Item Env:NX2NAVI_MOVIE_SKIP -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath $log) {
    $copy = Join-Path $desktop 'NX2navi-PREBUILD-NORMAL-INTRO.log'
    Copy-Item -LiteralPath $log -Destination $copy -Force
    Write-Host "Saved game log: $copy" -ForegroundColor Green
    Write-Host 'Pipeline prebuild:' -ForegroundColor Cyan
    Select-String -LiteralPath $copy -Pattern 'vk_pipeline: prewarm:' | Select-Object -Last 1 | ForEach-Object { $_.Line }
    Write-Host 'Intro skip present? (should be blank):' -ForegroundColor Cyan
    Select-String -LiteralPath $copy -Pattern 'movie: movies end after 1.0 s' | ForEach-Object { $_.Line }
    Write-Host 'Recent FPS:' -ForegroundColor Cyan
    Select-String -LiteralPath $copy -Pattern 'frametime: (60 s:|exit:)' | Select-Object -Last 4 | ForEach-Object { $_.Line }
}
