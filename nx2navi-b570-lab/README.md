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

## Result: driver-no-opt did not fix the crash (2026-11-08 20:48 ET)

`DriverNoOpt` with `NX2NAVI_MOVIE_SKIP=1` completed shortened intro clips, exited 71, and again reported `igvk64.dll+0x79ddf3` reading `0x190`. The script requested `NX2NAVI_VK_NOOPT=1`, but its short summary does not include the renderer's confirmation line. Verify `vk_pipeline: pipelines built without the driver's optimiser` in the full `nx2navi.log` before claiming the flag actually changed pipeline creation.

### Next controlled experiment: descriptor-update templates

The native renderer uses `vkCmdPushDescriptorSetWithTemplateKHR` / `vkUpdateDescriptorSetWithTemplate` when available. `NX2NAVI_DESC_TEMPLATE=0` forces plain descriptor write structures. A failure at the same Intel driver offset might involve driver-side descriptor handling, but we have no proof. Keep all other Test 4 settings the same, and avoid full intro playback with the movie-skip feature:

```powershell
$script = "$env:USERPROFILE\Downloads\NX2navi-B570-Compatibility-Lab\NX2navi-B570-Test.ps1"
$env:NX2NAVI_MOVIE_SKIP = '1'
try {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Test DescriptorFallback
} finally {
    Remove-Item Env:NX2NAVI_MOVIE_SKIP -ErrorAction SilentlyContinue
}
```

To check actual settings and exact crash location, inspect the saved full log with:

```powershell
$latest = Get-ChildItem "$env:USERPROFILE\Desktop\NX2navi-B570-Results" -Directory |
    Where-Object Name -Like '*-DescriptorFallback' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) {
    Select-String -Path (Join-Path $latest.FullName 'nx2navi.log') -Pattern 'descriptor update templates|FATAL:|igvk64.dll|cfg: read'
}
```

Do **not** delete the main game pipeline cache or the pretranslated shader pack. If the same crash repeats, stop tuning random switches and use Vulkan validation / crash captures with the upstream developers.

## Result: descriptor template fallback did not fix the crash (2026-11-08 20:51 ET)

`DescriptorFallback` with `NX2NAVI_MOVIE_SKIP=1` still exited 71 at `igvk64.dll+0x79ddf3`, reading address `0x190`. The log **confirmed** `vk_pipeline: descriptor update templates off (NX2NAVI_DESC_TEMPLATE=0)`. This eliminates that switch alone as a fix. These three distinct tests—write-back merge off, driver pipeline optimizations off (activation not yet verified), and descriptor-update templates off—each reached the same Intel driver crash. No tested setting is a verified gameplay workaround.

### Next step: Vulkan API validation and full logs

The native renderer supports `NX2NAVI_VK_VALIDATION=1`, **if** the installed Vulkan loader can find `VK_LAYER_KHRONOS_validation`. The source logs an explicit warning and continues without validation otherwise. Unlike a random gameplay setting, this can reveal an invalid Vulkan API usage preceding the driver fault. Validation substantially slows the game; skip the movies when capturing the crash. Run the existing local launcher with `-Test Baseline` and set both `NX2NAVI_VK_VALIDATION=1` and `NX2NAVI_MOVIE_SKIP=1` only in the parent process. After the run inspect the saved complete `nx2navi.log` for `vk validation error`, `vk validation warning`, and `validation set but`. Don't claim validation ran if the layer was missing.

A matching crash is independently reported in another native PC recompilation on Intel Arc B580 with driver 101.9150: https://github.com/valentderah/totk-pc-recomp/issues/774. This suggests a common path, but does **not** prove the issue is only inside Intel's driver; invalid API use can also crash drivers.
