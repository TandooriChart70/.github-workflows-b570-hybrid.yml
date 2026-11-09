# Independent NX2navi Intel Arc B570 diagnostic launcher.
# No game files, shaders, binaries, or source code are copied.
[CmdletBinding()]
param(
    [ValidateSet('WritebackOff','DriverNoOpt','DescriptorFallback','SubgroupOff','Baseline')]
    [string]$Test = 'WritebackOff',
    [string]$GameDir = "$env:LOCALAPPDATA\Programs\NX2navi\game"
)
$ErrorActionPreference = 'Stop'
# Official NX2navi launcher's built game is ocarina.exe; manual source builds
# may instead use nx2navi.exe. Never select the NX2navi.exe launcher stub.
$gameExeNames = @('ocarina.exe', 'nx2navi.exe')
$exe = $null
foreach ($name in $gameExeNames) {
    $candidate = Join-Path $GameDir $name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $exe = $candidate; break }
}
$log = Join-Path $GameDir 'logs\nx2navi.log'
$ini = Join-Path $GameDir 'nx2navi.ini'
if (-not $exe) {
    throw "No built game executable (ocarina.exe or nx2navi.exe) found in $GameDir. Supply -GameDir with the path from the NX2navi launcher."
}
if (@(Get-Process -Name ocarina,nx2navi -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Close the running NX2navi game before starting this diagnostic.'
}

# Test 4 settings allowed the opening movie to play. Each run starts from
# that baseline, changing only one extra feature in the selected experiment.
# These process-scoped environment variables override the INI for this launch.
$settings = [ordered]@{
    NX2NAVI_VK_RECORDER = '0'
    NX2NAVI_GPL = '0'
    NX2NAVI_VK_DYN_VERTEX = '0'
    NX2NAVI_LIB_PREBUILD = '0'
    NX2NAVI_PIPE_PREBUILD = '0'
    NX2NAVI_ASTC = 'auto'
    NX2NAVI_VK_PRESENT = 'fifo'
    NX2NAVI_WB_MERGE = '1'
    NX2NAVI_VK_NOOPT = '0'
    NX2NAVI_DESC_TEMPLATE = '1'
    NX2NAVI_VK_SUBGROUP_PIN = '1'
}
switch ($Test) {
    'WritebackOff'        { $settings['NX2NAVI_WB_MERGE'] = '0' }
    'DriverNoOpt'        { $settings['NX2NAVI_VK_NOOPT'] = '1' }
    'DescriptorFallback' { $settings['NX2NAVI_DESC_TEMPLATE'] = '0' }
    'SubgroupOff'        { $settings['NX2NAVI_VK_SUBGROUP_PIN'] = '0' }
    'Baseline'           { }
}

$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop) { $desktop = $env:USERPROFILE }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$results = Join-Path (Join-Path $desktop 'NX2navi-B570-Results') ("{0}-{1}" -f $stamp, $Test)
New-Item -Path $results -ItemType Directory -Force | Out-Null
$settings.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value } |
    Set-Content -Path (Join-Path $results 'settings.txt') -Encoding UTF8
if (Test-Path -LiteralPath $ini -PathType Leaf) {
    Copy-Item -LiteralPath $ini -Destination (Join-Path $results 'nx2navi.ini.snapshot.txt') -Force
}
Write-Host "NX2navi B570 test: $Test" -ForegroundColor Cyan
Write-Host "Result folder: $results"
Write-Host 'The installed game and shader caches are unchanged. Complete the intro or close the game normally.'

$old = @{}
$started = Get-Date
$exitCode = $null
try {
    foreach ($key in $settings.Keys) {
        $old[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $settings[$key], 'Process')
    }
    $p = Start-Process -FilePath $exe -WorkingDirectory $GameDir -PassThru -Wait
    $exitCode = $p.ExitCode
} finally {
    foreach ($key in $settings.Keys) {
        [Environment]::SetEnvironmentVariable($key, $old[$key], 'Process')
    }
}
$report = @("Test: $Test", "Start: $($started.ToString('o'))", "Exit code: $exitCode")
if (Test-Path -LiteralPath $log -PathType Leaf) {
    if ((Get-Item -LiteralPath $log).LastWriteTime -lt $started.AddSeconds(-5)) {
        $report += 'WARNING: Log is older than this test.'
    } else {
        $saved = Join-Path $results 'nx2navi.log'
        Copy-Item -LiteralPath $log -Destination $saved -Force
        $report += @(Select-String -LiteralPath $saved -Pattern 'mem: write-back merge|FATAL:|igvk64.dll|vk: using gpu|movie: video decoder finalised' |
            Select-Object -Last 20 | ForEach-Object { $_.Line })
        if ($Test -eq 'WritebackOff' -and -not ($report -match 'mem: write-back merge off')) {
            $report += 'No OFF confirmation in log. Verify the full log before drawing conclusions.'
        }
    }
} else {
    $report += 'No game log found.'
}
$report | Set-Content -Path (Join-Path $results 'summary.txt') -Encoding UTF8
$report | ForEach-Object { Write-Host $_ }
Write-Host "Upload summary.txt and nx2navi.log from $results if the game crashes."
