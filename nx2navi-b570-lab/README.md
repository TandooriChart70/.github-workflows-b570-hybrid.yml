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

## Major breakthrough: first playable Arc B570 native gameplay (2026-11-08 ~21:05 EST)

With the Test 4 baseline, `NX2NAVI_VK_VALIDATION=1` and `NX2NAVI_MOVIE_SKIP=1` set in the parent PowerShell environment, the user reports **no crash** and **no flickering** after the intro, with playable Link movement. A 33-second user-provided recording visually confirms a rendered environment, Link moving, terrain, buildings, vegetation, and lighting. Performance remains uneven. The recording is private and is **not** committed to the repository.

**Causality NOT proven.** The runtime log confirming whether `VK_LAYER_KHRONOS_validation` actually loaded has not been supplied. A missing layer makes the renderer continue without validation. The result could also be affected by cache warming, movie skipping, timing or an intermittent issue. Don't assume this is a stable fix until repeated on a second run and verified with logs.

### Preserve and verify

While the game still runs, open a second PowerShell window:

```powershell
$log = "$env:LOCALAPPDATA\Programs\NX2navi\game\logs\nx2navi.log"
Select-String -Path $log -Pattern 'validation|frametime:|vk: using gpu|FATAL:' | Select-Object -Last 35
```

If the full log includes `NX2NAVI_VK_VALIDATION set but VK_LAYER_KHRONOS_validation is not installed`, validation did not run. If it includes `vk validation warning` or `vk validation error`, save the context. An absence of errors does not alone prove the layer was enabled—see complete initialization lines. Save the whole log immediately after the successful session, along with the launch arguments. For performance, first enable the in-game F10 FPS overlay and measure steady-gameplay and worst frame times; validation can impose a large CPU overhead. Reduce game resolution from 1440p to 1080p only as a separate, recorded next test; avoid simultaneously changing other settings.

## Performance follow-up: playable but 3.8 FPS (2026-11-08)

The user preserved the first playable session log on their Desktop. Later 60-second windows reported 229–231 frames / 60 seconds (~3.8 FPS), with ~260-ms total frame time. Shader translation and pipeline-building times were ~0.0 ms on these steady-state frames, though earlier spikes included >900-ms pipeline builds. The replay component was typically ~30–65 ms in later samples, lower than the total frame time. Thus shader preload is not the main sustained 3.8 FPS bottleneck. The success happened with two parent environment settings simultaneously: `NX2NAVI_VK_VALIDATION=1` and `NX2NAVI_MOVIE_SKIP=1`. Validation-layer activation has not yet been confirmed from initialization logs. The next essential A/B test keeps movie skip enabled and turns validation off using `NX2NAVI_VK_VALIDATION=0` while preserving Test 4 baseline. If the game crashes again, that is also a meaningful result: validation or its side effects may alter timing/driver behavior. Don't erase the cache.

## Full successful session log changes the interpretation (uploaded 2026-11-08)

The 2233-line privately supplied log **explicitly states**: `NX2NAVI_VK_VALIDATION set but VK_LAYER_KHRONOS_validation is not installed; continuing without`. **Validation was NOT enabled**, and cannot explain the no-crash outcome or 3.8 FPS overhead. The user did have `NX2NAVI_MOVIE_SKIP=1`; this or changed execution order, caching or timing is a leading hypothesis. Don't claim movie skipping itself fixes the Intel crash without a repeat A/B test.

- First successful run: NX2navi 0.5.0, game 1.1.1, Intel Arc B570 driver 101.9175, Vulkan 1.4.359; `vk_recorder=0`, `gpl=0`, `vk_dyn_vertex=0`, `lib_prebuild=0`, `pipe_prebuild=0`, ASTC GPU, memory mirror, FIFO presentation. `WB_MERGE=1` did not crash in this run.
- The log has **zero fatal messages** through its final capture, and confirms movie decoders each ended around 1 second. Boot reported 46 shader program answers from earlier gameplay; they grew to ~1231 in this session, demonstrating ongoing discovery of new pipelines despite pretranslated shaders.
- There were *major* first-use pipeline build stalls: one worst frame was 119,508 ms (~119.5 sec), with 110,280 ms pipeline-build time; later other builds lasted multiple seconds. After the world warmed, frame reports show pipeline build ~=0 ms on most frames.
- Reported 60-second windows during active gameplay included 16.6, 11.6, 10.0 and 11.0 FPS; sustained 3.8 FPS windows followed repeated focus-loss events. The 3.8 FPS value **cannot be assumed to represent foreground game speed**: compare with F10 overlay while the game is focused.
- The game explicitly logs `resolution: the game's own (this build has no output and scene patch sets; output_res and render_scale do nothing)`. Do not recommend those keys as a performance fix for this particular build.
- Vulkan `REPLAY_ASYNC=1` is a possible *later* controlled performance experiment, not verified to help. More importantly, establish baseline focused FPS and test repeatability of startup success with `MOVIE_SKIP=1`, **without** unnecessary validation toggles (since the layer was absent). Preserve full log and caches.

## New slowdown reproduced after jumping (2026-11-08 ~21:18–21:22 EST)

While playing the native port using the Baseline Test 4 settings with movie skipping, Link appeared smooth initially, then the game sharply deteriorated after jumping. The user saved the full runtime log locally at `Desktop/NX2navi-JUMP-SLOWDOWN-20261108-212200.log`. The log has not yet been uploaded, but excerpts show successive one-minute windows:

- 2027 frames in 60s (**33.8 FPS**), worst frame 2205.1 ms with pipeline build 2078.9 ms; other worst frames have shader translation ~599–794 ms.
- 98 frames in 60s (**1.6 FPS**); frame 2072 shader translation 707.6 ms, but many slower frames already report no pipeline build or shader translation.
- 64 frames in 60s (**1.1 FPS**); worst frames 1428–1984 ms, shader translation and pipeline build both 0 ms, replay 37–64 ms.
- 43 and 40 frames in 60s (**0.7 FPS**); worst frames ~1591–1891 ms, shader and pipeline 0 ms, replay ~27–44 ms.

The log contains window-focus changes from 21:18:41 onward, **after** the severe drop began. Therefore the initial sharp slowdown cannot be attributed only to background-window throttling. In the source, `runtime/perf.c` measures frame time as the time between presents; the listed shader/pipeline/replay entries are not an exhaustive partition of that interval. The unaccounted time could be guest game processing, scheduling, waits or another path. Avoid assuming the initial shader-compilation burst explains the later persistent ~0.7 FPS.

### Next evidence / profiler

Get the entire saved `NX2navi-JUMP-SLOWDOWN-20261108-212200.log` before another test. Search it for `perf: frame`, `bound:`, `kernel:`, `sched:`, memory activity and later frame-scheduling notices.

If detailed logs do not explain the sustained stall, NX2navi already includes a Windows sampling profiler in `runtime/prof_win.c`: set `NX2NAVI_PROFILE=<absolute output path>`, `NX2NAVI_PROFILE_SLOW=1000` (capture stacks for frames slower than 1 second), `NX2NAVI_MOVIE_SKIP=1`, and `NX2NAVI_TRACE=perf` for one controlled repeat. The profiler adds overhead and may perturb timing. Limit the run and close normally so the main profile is written. The slow-frame dumps (`<profile>.f<frame>`) can reveal which threads are waiting. Do not touch shader caches or overwrite the previously successful log.

## Analysis of uploaded complete jump-slowdown log: guest application pool limit (2026-11-08)

The full 926-line `NX2navi-JUMP-SLOWDOWN-20261108-212200.log` shows the game started at 33.8 FPS, then fell to 1.6, 1.1 and 0.7 FPS without crashing. New evidence near the transition:

- **242** `MapPhysicalMemory ... failed 0x10801` messages (lines 607–867), all in a burst following entrance into 3D gameplay. Error 0x10801 is `R_LIMIT_REACHED` (`LimitReached`), **not** a generic GPU allocation failure. `runtime/memory.c` `alias_map()` explicitly returns it if `new alias bytes + already mapped alias bytes + heap_size + image_bytes() > L.pool`. Source: https://github.com/tangerineturtle1/NX2navi/blob/main/runtime/memory.c
- The retail Switch 2 game default application pool is 9,809 MiB. The last mapping failure's logged alias allocation ~2803 MiB plus heap 6910 MiB is already around 9713 MiB, without counting `image_bytes()`; the guest allocator appears to be approaching its configured pool limit. Raising the pool may allow memory mapping previously refused, but can also increase host memory use or change game behavior.
- The renderer reports `7512 of 8164 MiB` of its VRAM budget occupied (lines 841–844); small buffer mirrors are therefore left in slower imported memory. This is a separate **host GPU budget**, not the same as the guest `APP_POOL` limit.
- Window is `3200x1800`, internal game output `2560x1440`, FSR upscaling. The port supports *Ocarina*-specific `NX2NAVI_GAME_RES=1080`, unlike unsupported `OUTPUT_RES` and `RENDER_SCALE` in this game build. Using 1080 instead of 1440 reduces rendered pixels but is a **separate test**.
- The run started with 1098 pipeline records not prebuilt and saw temporary large pipeline compilation stalls. This alone doesn't explain persistent later frames with zero translation and pipeline build.

### Test 10: Increase the guest application pool, one variable only

Use the existing proven Baseline diagnostic launcher, with the familiar one-second movie-skip and an additional **process-only** environment override (no INI modification, no cache deletion):

```powershell
$script = "$env:USERPROFILE\Downloads\NX2navi-B570-Compatibility-Lab\NX2navi-B570-Test.ps1"
$env:NX2NAVI_MOVIE_SKIP = '1'
$env:NX2NAVI_APP_POOL = '0x300000000' # 12 GiB; default 9809 MiB
try {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Test Baseline
} finally {
    Remove-Item Env:NX2NAVI_APP_POOL -ErrorAction SilentlyContinue
    Remove-Item Env:NX2NAVI_MOVIE_SKIP -ErrorAction SilentlyContinue
}
```

Measure FPS before and after jumping, continue for ~1 minute to see if it recovers, then close the game normally. Confirm new logs lack the `MapPhysicalMemory ... failed 0x10801` storm; compare frametimes. If memory pressure or crashes worsen, exit; the process-scoped setting is gone after the test. Never change both `APP_POOL` and `GAME_RES` at the same time in the first A/B experiment. If Test 10 is inconclusive, Test 11 should change just `NX2NAVI_GAME_RES=1080` instead, to reduce framebuffer and VRAM demand. If the game still has 1–2-second frames with no pipeline work, use its `NX2NAVI_PROFILE_SLOW` thread profiler.

## Test 10 preliminary outcome: raised guest pool is a major improvement (2026-11-08 ~21:31 ET)

User reports native gameplay is **much smoother** using `NX2NAVI_APP_POOL=0x300000000` (12 GiB) alongside the existing Baseline launch script and `NX2NAVI_MOVIE_SKIP=1`. Their attached ~25-second gameplay capture shows Link running and jumping outdoors with rendered terrain, foliage and scenery, no obvious white flashing, and an onscreen overlay generally showing **8–11 FPS**. That compares favorably to the prior post-jump sustained 0.7–1.6 FPS, although capture conditions and different scene complexity mean this is a qualitative performance improvement rather than an exact matched benchmark. The video is private; do not commit it. Do **not** claim the guest-memory increase is the sole cause until runtime log verifies no `0x10801` mapping failures and test repeats.

The port is **still far below playable 30/60 FPS** and window/internal resolution and VRAM pressure may remain substantial.

### Before another reboot

In a second PowerShell window during Test 10, capture `nx2navi.log` as `Desktop/NX2navi-12GB-RESULT.log`, count `MapPhysicalMemory.*failed 0x10801` and display last `frametime: 60 s:` and `vram.*MiB` lines. Then if game is stable, test `NX2NAVI_GAME_RES=1080` while **keeping 12 GiB guest pool fixed**, as an isolated GPU rendering-load A/B. Note that `GAME_RES` is the *Ocarina*-specific resolution setting, whereas `OUTPUT_RES` is explicitly ineffective in this title's build. Do not modify shaders or pipeline caches.

## Test 10 later performance results: 12 GiB still hits guest memory limit (2026-11-08)

The user has ~48 GiB of installed system RAM (prior runtime logs reported ~48,993 MiB). Using `NX2NAVI_APP_POOL=0x300000000` (12 GiB guest pool) with the working Baseline launcher produced the following consecutive 60s performance summaries: 42.2 FPS (2556 frames), then 9.1 (548), 9.4 (562), and 7.3 FPS (436). The full runtime log reports **587** occurrences of `MapPhysicalMemory.*failed 0x10801` across that whole session, so the 12-GiB guest pool has **not** eliminated guest pool exhaustion. Raw total failure counts are not directly comparable across runs of different durations.

Hardware: Arc B570 has **10 GiB dedicated GDDR6 VRAM**, which is distinct from system RAM. The runtime's `memory=mirror` mode is valuable because without VRAM mirrors the GPU reads imported system-memory buffers over PCIe (upstream architecture documents as ~7 FPS in Kokiri Forest). **Do not** switch to `memory=import` merely to use more RAM; it is likely slower.

### Test 11: 16 GiB pool only

Try `NX2NAVI_APP_POOL=0x400000000` (16 GiB) as a single change, continuing `NX2NAVI_MOVIE_SKIP=1` and `-Test Baseline`. Keep `NX2NAVI_GAME_RES` at previous default for a controlled memory comparison. Record latest steady-gameplay FPS and 0x10801 count. This value is a *guest budget*, not an immediate 16-GiB physical memory allocation, but may let the game's memory requests use more host RAM. If process memory rises rapidly / commit pressure begins, exit and revert. Upstream source `runtime/memory.c` returns `R_LIMIT_REACHED=0x10801` when `new alias + existing alias + heap + image bytes > L.pool`; it does not test discrete GPU VRAM. This is an experiment, not a proven fix.

If Test 11 still degrades to single-digit FPS, **keep the safer pool value** and try a separate single change `NX2NAVI_GAME_RES=1080` (Ocarina-specific) to reduce rendering load and VRAM pressure. Independently measure GPU dedicated/shared usage in Task Manager. Preserve the compiled game, save files and shader and pipeline caches.

## Test 11 failed: 16 GiB guest pool causes SDK Break (2026-11-08 ~21:40 ET)

Two consecutive fresh launches with `NX2NAVI_APP_POOL=0x400000000` (16 GiB), movie skip on, and Baseline settings exited **70 before entering gameplay**:

```
FATAL: svc #0x26 unknown at sdk+0x1a5560: Break (the SDK aborted)
FATAL: svc #0x26 unknown is not implemented
[host] fatal: memory commit: this process ~1600 MB, system ~11.5 of 52 GB
```

There were **zero 0x10801 errors and no 60-second FPS records**, but these are **not successes**, because the game aborted during initialization. The user's available system RAM is not exhausted. Do not increase APP_POOL further: the 16 GiB value appears incompatible with game SDK/runtime expectations in this build. The exact SDK abort reason is not determined without the complete log and Break reason, and the code is not safe to patch over.

Upstream `runtime/memory.c` reserves only a 12-GiB contiguous guest heap window (`HEAP_CAP`) while `APP_POOL` is a separate total budget; this does not by itself prove why SDK aborted.

**Revert to known-good** `NX2NAVI_APP_POOL=0x300000000` (12 GiB). For next controlled performance experiment **keep 12 GiB fixed** and change only `NX2NAVI_GAME_RES=1080`. This is supported for Ocarina in upstream `runtime/widescreen.c`; verify log contains `widescreen: picture 1920x1080, scene ...` and not `generated C has no widescreen patch sets`. With 12 GiB otherwise unchanged, 1080p lowers internal picture pixels from 2560x1440 by ~44%, and can mitigate VRAM use and GPU frame cost. Does not address 0x10801 directly. Continue to keep compiled game, saves, shaders and pipeline cache intact.

PowerShell launch:
```powershell
$script = "$env:USERPROFILE\Downloads\NX2navi-B570-Compatibility-Lab\NX2navi-B570-Test.ps1"
$env:NX2NAVI_APP_POOL = '0x300000000'
$env:NX2NAVI_GAME_RES = '1080'
$env:NX2NAVI_MOVIE_SKIP = '1'
try {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Test Baseline
} finally {
    'NX2NAVI_APP_POOL','NX2NAVI_GAME_RES','NX2NAVI_MOVIE_SKIP' | ForEach-Object { Remove-Item "Env:$_" -ErrorAction SilentlyContinue }
}
```

After run, compare sustained FPS and count `0x10801` from the **same** session log. If aborted, restore pure 12 GiB with no `GAME_RES`. Avoid claiming that changing system RAM settings can increase the 10 GiB dedicated VRAM of the Intel B570.
