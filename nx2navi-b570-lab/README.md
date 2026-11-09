# NX2navi Intel Arc B570 Compatibility Lab

Independent PowerShell diagnostics for the **existing** installed NX2navi PC port. This is not a validated crash fix and not a modified copy of NX2navi. No Nintendo game data, shader caches, executables, or NX2navi code are included.

## What we know

- Intel Arc B570 on Windows 11, Intel graphics driver 101.9175, NX2navi 0.5.0, game 1.1.1.
- Repeated access violation at `igvk64.dll+0x79ddf3`, reading address `0x190`, launcher exit code 71.
- With `vk_recorder=0`, `gpl=0`, `vk_dyn_vertex=0`, `lib_prebuild=0` and `pipe_prebuild=0`, the intro video ran, but the transition to 3D crashed.
- The last successful run logged `mem: write-back merge on (NX2NAVI_WB_MERGE)` shortly before the crash. The upstream renderer reads this setting to select an optional Vulkan compute pipeline. That **might** be responsible; the log alone does not establish causality.
- NX2navi already preloaded the ~36,031 shader variants. Prior Eglantine V-series emulator caches cannot be plugged into NX2navi; shader/pipeline behavior is still useful diagnostic context.

## First run (priority)

From Windows PowerShell, with the downloaded script in the current directory:

```powershell
powershell -NoProfile -File .\NX2navi-B570-Test.ps1 -Test WritebackOff
```

This temporarily sets `NX2NAVI_WB_MERGE=0` for the launched process while retaining the previous Test 4 conditions. It undoes the unsuccessful CPU ASTC experiment and requests FIFO presentation to reduce screen tearing. It does **not** overwrite `nx2navi.ini`, saves, binaries, or the shader cache.

Results are saved locally at `Desktop\NX2navi-B570-Results\<timestamp>-WritebackOff\`. Review the log before sharing, because it may contain Windows user paths. No upload is automatic.

## Other one-variable experiments

Run these only after analyzing the first test:

```powershell
powershell -NoProfile -File .\NX2navi-B570-Test.ps1 -Test DriverNoOpt
powershell -NoProfile -File .\NX2navi-B570-Test.ps1 -Test DescriptorFallback
powershell -NoProfile -File .\NX2navi-B570-Test.ps1 -Test SubgroupOff
```

These test disabling driver pipeline optimization, descriptor-update templates, and fixed subgroup-size pinning, respectively. None is a confirmed workaround.

If NX2navi was installed elsewhere, add `-GameDir 'D:\Path\To\game'`.

## Upstream license boundary

NX2navi source is readable publicly, but its added code is all-rights-reserved and may not be redistributed without written permission. This branch contains **only original** testing scripts and explanations. See [upstream license](https://github.com/tangerineturtle1/NX2navi/blob/main/LICENSE-ADDITIONS).

## Result: write-back merge did not fix the crash

The 2026-11-08 `WritebackOff` test played both opening videos but exited 71 at the same `igvk64.dll+0x79ddf3` access violation. The log confirmed `mem: write-back merge off (NX2NAVI_WB_MERGE)`. This hypothesis is therefore not sufficient to fix the transition-to-3D crash.

### Next targeted test: disable driver pipeline optimization

The upstream renderer's `VK_NOOPT` switch applies `VK_PIPELINE_CREATE_DISABLE_OPTIMIZATION_BIT` when creating Vulkan graphics pipelines. It was added specifically as an experiment for crashing driver shader compilers.

To run the next test *without replaying the full opening movie*, set the game's supported movie skip setting in the **PowerShell parent process** and launch the existing script:

```powershell
$script = "$env:USERPROFILE\Downloads\NX2navi-B570-Compatibility-Lab\NX2navi-B570-Test.ps1"
$env:NX2NAVI_MOVIE_SKIP = '1'
try {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Test DriverNoOpt
} finally {
    Remove-Item Env:NX2NAVI_MOVIE_SKIP -ErrorAction SilentlyContinue
}
```

`NX2NAVI_MOVIE_SKIP=1` tells the host movie decoder to produce its end marker after one second of samples; it is **not** the same as `NX2NAVI_MOVIES=off`, which causes this title to quit. Movie skipping changes the test workload, so if the game boots further, repeat without movie skipping to validate the result. Keep backups; do not delete the compiled game, shader pack or pipeline cache. The script saves a summary and full runtime log on the Desktop and does not send them anywhere.
