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

## First 1080p recording reviewed (2026-11-08 ~21:44 ET)

A ~9-second video from the user after Test 12 (`NX2NAVI_APP_POOL=0x300000000`, `NX2NAVI_GAME_RES=1080`, movie skipping, Baseline) shows the game rendering Link and the forest correctly, without obvious flashing or a crash. However the in-game FPS overlay fluctuates around **2–6 FPS** in the recording, **not yet a sustained improvement** over the earlier 12-GiB, 1440p 7–9 FPS gameplay. The game is in a window beside a browser and terminal, with multiple log lines of window focus loss/gain; this can confound a foreground-FPS comparison. The visible terminal contains one `frametime: 60 s` line averaging **30.9 FPS**, but several very long frame-time spikes and repeated graphics pipeline waits in the same session.

**Don't infer that 1080p definitively worsens or helps FPS from this short video.** Request the complete current-session runtime log to confirm `widescreen: picture ...` and last 5 `frametime: 60 s` windows, 0x10801 errors, and whether the game was in focus. If sustained foreground FPS remains single digit with no pipeline-translation activity, use the built-in sampling profiler `NX2NAVI_PROFILE` + `NX2NAVI_PROFILE_SLOW` rather than further guessing GPU settings. Preserve the working 12-GiB configuration/caches. Do not publish the user's recording.

## Resolution test verification: 1080p setting had no effect (Nov 8 ~21:49 ET)

The user ran the 12-GiB pool + `NX2NAVI_GAME_RES=1080` test and reported the following from its live `nx2navi.log`:
```
[host] gfx: the game presents 2560x1440 images of format 37
[host] vk: FSR upscales 2560x1440 to 3200x1800 (sharpness 80)
Memory-limit failures: 137
[host] frametime: 60 s: 2973 frames in 60.0 s, mean 49.5 fps, 1% low 10.2 fps
```
This **does not prove 1080p was activated**; the game is presenting the same 2560x1440 internal picture, upscaled to 3200x1800. A prior successful run logged `patches: wide_out off, wide_scene off ...` and no widescreen patch sets. Upstream `runtime/widescreen.c` requires `wide_out, wide_scene, wide_aspect, wide_hud, wide_movie` sets for `NX2NAVI_GAME_RES=1080` to actually change the output; absent sets means no resolution change. Thus this attempt was NOT a meaningful 1440p vs 1080p comparison.

The 49.5 FPS 60-second window is not confirmed sustained gameplay (may include intro/menu), especially since the contemporaneous ~9-s video showed intermittent 2–6 FPS with multiple focus changes. 137 `0x10801` failures shows guest pool exhaustion persists at 12 GiB. These failure totals are duration dependent.

**Next diagnostic**: Keep `APP_POOL=0x300000000` and existing Baseline settings, remove ineffective `GAME_RES`, and enable upstream instrumentation `NX2NAVI_TRACE=perf`, `NX2NAVI_PROFILE=<Desktop/unique-prof-path>`, `NX2NAVI_PROFILE_SLOW=300` or `500`. Source: `runtime/perf.c` prints per-60-present GPU busy, VRAM budget, CPU/GPU-bound diagnostics, while `runtime/prof_win.c` samples all Windows threads and writes slow-frame stack traces `<profile>.f<frame>` when a frame exceeds the specified ms threshold, as well as main profile at clean exit. Profiler overhead may affect FPS; use this as diagnosis, not benchmark. Keep a short run and zip the main profile, recent slow-frame traces and game log. Do not touch caches, executables or INI.

**Important nuance**: `NX2NAVI_APP_POOL` changes guest-memory budget, not system RAM allocation, and no amount of host RAM turns into Arc B570's 10 GiB dedicated VRAM. Default memory=mirror uses VRAM buffers for speed; do not switch to import.

## SlowTrace profile: user correction (Nov 8 ~21:56 ET)

The user explicitly corrected the interpretation of the profiling run: **FPS is steady at only 2–3**, not smooth or meaningfully playable. The main profile `NX2navi-SlowTrace-20261108-215259.prof` has `samples 778067`, 113 thread records, 4000 RIP entries and 6000 stack entries. The top recorded instruction samples are in ntdll waits, which does **not** imply that idle threads account for the bottleneck (the profiler samples waiting threads). `igc-default64.dll` (Intel shader compiler) accounts for 48,270 *recorded instruction samples*, but these counts are not CPU utilization percentages. `ow-graphics-vulkan.dll` and `ow-graphics-hook64.dll` from Overwolf are actually loaded in this process; no causal link yet.

Upstream `runtime/prof_win.c` uses a ~1ms sampling loop that suspends/resumes each thread to obtain instruction pointers, with optional stack sampling for `PROFILE_SLOW`; sampling >100 threads can materially change the timing of the running game. Therefore **do not benchmark with all-thread sampling enabled** and don't interpret the 2–3 FPS profiler run as representative of the earlier 12-GiB no-profiler ~7–9 FPS performance.

### Next controlled A/B

Launch with the known-working 12-GiB APP_POOL and movie skip under the Baseline script, **explicitly removing** `NX2NAVI_PROFILE`, `NX2NAVI_PROFILE_SLOW`, `NX2NAVI_PROFILE_CHAINS`, `NX2NAVI_PROFILE_RENDER`, `NX2NAVI_PROFILE_MAIN`, `NX2NAVI_TRACE`, `NX2NAVI_PERF_SLOW_MS` from the process environment. Keep current resolution/other settings, record *foreground gameplay FPS* in the same area after >1 min; preserve full log. If it goes back to 7–9 FPS rather than 2–3, instrumentation burden is substantial. If it stays low, repeat same settings **after exiting Overwolf completely** as an isolated interference A/B; don't uninstall software or alter GPU driver. Once this is ruled out, consider a render-thread-only profiler (PROFILE_RENDER=1) with minimal burden or fuller slow traces.

## Test 13 no-profile results: jump-triggered degradation persists (Nov 8 ~22:00 ET)

The user ran the 12-GiB APP_POOL Baseline configuration **without NX2NAVI_PROFILE / NX2NAVI_TRACE**. They report 9–12 FPS at first, then after jumping down to the lower area FPS fell **again to 2–3**, and stayed there. Thus full-thread profiling overhead is *not* the only cause; it may still have worsened Test 12 performance but the fundamental area-triggered stall is reproducible unprofiled.

Avoid conflating the act of jumping with the visibility/load of the new region or new GPU effects. Both guest application pool exhaustion (0x10801), Intel Arc Vulkan driver synchronization, VRAM mirror refusal, and an injected Vulkan overlay may contribute; no causality is proven yet. Previous log with 12-GiB pool still had 587 recoverable memory-limit errors; 16 GiB caused reproducible SDK Break before gameplay.

Request the full new **unprofiled** game log immediately after the 2–3 FPS collapse (copy `.../game/logs/nx2navi.log` to Desktop before quitting). Then isolate the Overwolf hook: profile previously included `ow-graphics-vulkan.dll` and `ow-graphics-hook64.dll` inside game. After closing NX2navi, quit Overwolf and its apps entirely via system tray and Task Manager, then re-run exact same 12-GiB Baseline (no trace). Do not change shader caches, resolution, driver, or other config in this A/B. Compare initial and **post-drop sustained** FPS at same location. Keep 12-GiB as rollback baseline.

If overhead-free Overwolf-free test still stalls, run `NX2NAVI_TRACE=perf` **without** `NX2NAVI_PROFILE` for GPU/CPU-bound and VRAM diagnostics from `runtime/perf.c` and gather last `perf: frame`, `bound:`, `mem: mirror frame`, `MapPhysicalMemory` lines. Avoid a second all-thread sampling profile for benchmarking.

## After-jump log uploaded, 2.3 FPS sustained, VRAM pressure confirmed (Nov 8 ~22:05 ET)

Complete `NX2navi-AFTER-JUMP.log` (754 lines) was provided. The 12-GiB APP_POOL baseline (without expensive sampling profiler) reproduced the same drop in four one-minute logs:

- 1639 frames in 60.2s = **27.2 FPS** (early menus+gameplay),
- 161 frames = **2.7 FPS**,
- 147 frames = **2.4 FPS**,
- 139 frames = **2.3 FPS**.

**78 guest pool mapping LimitReached failures (0x10801)** in a contiguous burst around frames ~1450 and after heavy content load. Critically, **VRAM used 8,794 MiB vs budget 8,544 MiB** (from `mem: pool ... stays imported`, log lines 659–662). The mirror summary at frame 1800 reports 61 pools / 13.3 MiB which **could not be mirrored into fast local VRAM because of budget**, despite 586 other mirrors using 860.5 MiB. Imported buffers stay in system memory and can incur slower PCIe reads. The mirror telemetry at frame 1800 includes ~24.8 MiB upload/frame, ~13.9 MiB write-back/frame and 121 synchronizations/frame, showing active transfers but not by themselves proof of causation. ASTC cumulative decoded regions rise from 1,069 to >62,000 across gameplay, showing heavy texture activity/churn.

**Persistent slow frames cannot be attributed to pipeline building**: examples frames 1970/1961/1952 take ~770–881ms with 0ms xlate, 0ms pipeline build, 0ms fence/present wait, only ~28–42ms replay. The unaccounted CPU interval may include guest core work, driver waits not represented by these fields or starvation. First minute worst frame 1466=3567ms, frame 1465=2812ms (0ms shader and pipeline); 1452=796ms 307ms texture upload/664ms replay. The window first lost focus after frame ~1700, AFTER the transition. VRAM memory pressure and guest memory limit errors are real, not definitively the cause of the CPU stall.

Upstream `runtime/vk_headroom.c` already *drops* speculative VRAM reserve anchors at >=85% budget, so setting `NX2NAVI_VRAM_HEADROOM=0` is less promising than directly influencing texture eviction. `runtime/vk_texture.c` `sweep_pressure` reads `NX2NAVI_TEX_VRAM_PRESSURE` (default **90**). At >threshold, every 8 submits it evicts up to 32 oldest **released, recoverable** images, so earlier trigger (e.g. **75**) may reduce VRAM pressure/allocator churn but can increase redecoding and is NOT guaranteed.

### Proposed Test 14: lower released-texture VRAM trigger (one-variable experiment)

Maintain **APP_POOL=0x300000000 (12 GiB)**, MOVIE_SKIP=1 and Baseline runner without profiler or TRACE. Add **`NX2NAVI_TEX_VRAM_PRESSURE=75`** only. Start, verify log reports `vk: released textures under VRAM pressure: dropped above 75%`. At same scene jump, compare sustained post-jump FPS after 60-120s vs known **2.3 FPS**. Save log and count `0x10801`, check `stays imported`/VRAM budget. Avoid modifying shaders, code, INI or driver's state. If performance worsens, restore environment/default 90, no persistent change. If test remains ~2-3 FPS, isolate Overwolf Vulkan hook (present in previous profiler) **as next independent test** or use `NX2NAVI_TRACE=perf` (without full sampler) for accurate GPU-boundedness.

## 17-second Task Manager capture: GPU utilization saturated, not VRAM percentage (Nov 8 ~22:13 EST)

User says dedicated VRAM is maxed out. Their new 17-second 3840x2160 capture shows Task Manager on the **CPU** performance page, with side-panel Intel Arc B570 **GPU 0 at 99% utilization** and ~49°C temperature; CPU ~27% (~3.79 GHz); system RAM **25.7/47.8 GB (54%)**. Game onscreen FPS around 4–7 during clip. The clip **does not show Task Manager GPU detail page or its dedicated/shared GPU memory figures**, so do not infer 99% means 99% *memory* occupancy. However the preceding `NX2navi-AFTER-JUMP.log` independently reported Vulkan device-local use **8,794 MiB against budget 8,544 MiB** and a number of budget-refused VRAM buffer mirrors. Therefore both near-max GPU utilization and significant VRAM-budget pressure are documented; GPU utilization does not by itself distinguish compute shader/graphics load from memory thrashing or synchronization.

Do not propose adding more system RAM as extra high-speed VRAM; Arc B570 has **10 GiB GDDR6 dedicated** and mirrors imported host buffers to VRAM to avoid PCIe bottlenecks. 16-GiB guest APP_POOL aborted at startup; 12-GiB remains workable. Existing experiment `NX2NAVI_TEX_VRAM_PRESSURE=75` is intended to evict released recoverable textures sooner; await its full log and sustained foreground post-jump FPS before modifying further variables. The video has NX2navi at 3200x1800 window while browser and Task Manager stay open. If pressure remains, next controlled experiment should adjust `NX2NAVI_WINDOW_SIZE=1920x1080` (upscaling target only; game internal 2560x1440 remains unchanged without widescreen patch sets), and/or isolate Overwolf Vulkan hooking. Ask user to click Task Manager > Performance > GPU 0 and report **Dedicated GPU memory** (used/total) and **Shared GPU memory** (used/total) for a reliable split; the CPU page only shows utilization.

## Direct Task Manager VRAM measurement (Nov 8 ~22:17 ET)

User supplied Task Manager > Performance > Intel Arc B570 screenshot during low-FPS gameplay:
- GPU **3D engine 98% utilized**, temperature **53 C**;
- **dedicated GPU 9.6/10.0 GB (96%)**;
- **shared GPU 8.5/31.8 GB (~27%)**;
- **total GPU memory 18.0/41.8 GB**;
- system RAM used **25.9/47.8 GB (54%)**;
- CPU **18%**; Arc driver **32.0.101.9175**.

This definitively confirms VRAM saturation and substantial allocation in system shared memory, beyond previous Vulkan budget logs (8794 MiB usage / 8544 MiB budget). **Not all 8.5 GB of allocated shared memory necessarily represents frequent per-frame PCIe reads; Task Manager utilization is not a bandwidth meter.** CPU 18% total utilization also does not rule out a main-thread bottleneck.

The screenshot likely was taken near the ongoing `NX2NAVI_TEX_VRAM_PRESSURE=75` test, but the user has **not yet confirmed** which run or supplied the corresponding run log and post-jump FPS. Do not claim the 75% experiment failed without verification. The next diagnostic is to gather the `NX2navi-VRAM75.log` and confirm `released textures under VRAM pressure: dropped above 75%` and sustained FPS. Also use Windows Task Manager > Details with GPU memory columns (or simply close other GPU-heavy apps) to check whether NX2navi alone accounts for most allocations. Use the GPU memory graph to monitor and compare.

Potential next single-variable experiment if the 75% setting failed: reduce window output from **3200x1800 to 1920x1080** using `NX2NAVI_WINDOW_SIZE=1920x1080`; this affects **presentation and swapchain** memory, but due to missing Ocarina patch sets **internal game 2560x1440 stays unchanged**, so expected VRAM reduction may be modest. Could also test smaller released texture retention cap `NX2NAVI_TEX_RELEASED_MB`, with upstream's cautious re-upload caveats. Preserve baseline 12-GiB guest APP_POOL, don't switch from `memory=mirror` to import, don't increase 16-GiB guest pool (SDK startup abort).

## Wallpaper background GPU use disabled; performance rises 2–3 to 6–10 FPS (Nov 8 ~22:30 ET)

User discovered a dynamic desktop wallpaper consuming roughly 30% of GPU 3D resources at desktop and disabled it. Subsequently they reported **6–10 FPS** in the native Zelda game, much better than the 2–3 FPS prior run. An attached 31s 4K screen recording shows Link moving and 3D forest rendering correctly, the on-screen overlay around **7 FPS**, with Task Manager still showing **dedicated 9.7–9.8/10 GB VRAM**, **shared ~8.9–9.0/31.8 GB**, GPU ~78–91% while playing, system memory ~26/48 GB. Movie frames show a **1920x1080 window** (the game picture may still be internally rendered at 2560x1440 due to missing wide patch sets), browser and Task Manager simultaneously open, which causes window focus switching. Since the wallpaper was disabled *and* the smaller game window was active, **cannot isolate their individual contributions**. GPU VRAM remains saturated; wallpaper removal appears to have relieved competition for 3D execution, not appreciably the 10GB dedicated memory allocation.

Source: `runtime/vk_texture.c` supports `NX2NAVI_TEX_RELEASED_MB` as a cap on the own memory of already released images; default `RAM/16` (on 48 GB ~3 GiB), with an eviction sweep for stale entries after 120 frames. This could be a future *isolated* 1024 MiB test to reclaim VRAM, but it may cause extra reloads or black texture flashes in scenes, so only try after an overlay/app interference A/B. In contrast `TEX_VRAM_PRESSURE=75` starts dropping released recoverable textures above a VRAM budget threshold and prior trial only reached ~3 FPS before wallpaper removal; do not attribute new 6–10 FPS to that setting without verification.

**Next**: preserve current 12-GiB APP_POOL, no profiler, no dynamic wallpaper and current 1920x1080 window. Close Overwolf completely (its Vulkan injection was explicitly observed in the previous profile) without changing any NX2navi setting and play through the same jump **with game foreground** for 1-2 min; compare FPS, VRAM and GPU load. If overlays don't matter, consider a single-variable `TEX_RELEASED_MB=1024` experiment, using separate process-scoped env, and compare to this 6–10 FPS baseline. Avoid deleting caches or altering driver. To determine bottleneck, monitor **GPU 3D utilization and dedicated/share** independently: GPU 3D still high and VRAM still near 10 GB after wallpaper off.

## Fullscreen breakthrough: peak 15 FPS, transient white flashes (Nov 8 ~22:35 ET)

User reports that **fullscreen gameplay peaked at 15 FPS**, felt smoother, but exhibited **brief off-white flashing or incomplete 3D rendering that resolved once the environment loaded**. Dynamic desktop wallpaper already disabled, GPU previous measurement was near VRAM limit. Previous smaller window 1920x1080 runs reported 6–10 FPS. This is a **peak** measured by user, not a guaranteed sustained 15 FPS; the only supported claim is visible improvement in that run.

The transient white flashing might be from unfinished shader/pipeline work (noteworthy `NX2NAVI_PIPE_PREBUILD=0`, `NX2NAVI_LIB_PREBUILD=0`, `NX2NAVI_GPL=0`), texture upload/redecode under VRAM pressure, or render-target alias / sync issues. **Don't change multiple render flags or purge caches**: the existing baseline is unusually stable for Intel Arc B570, and previous variants crashed. First test if the exact flashing location flashes again when revisited *without restarting game*; if only first visit, shader/pipeline warming becomes more plausible. Obtain full `nx2navi.log` from this session; inspect `vk_exec: ... waited for its pipeline`, `gfx_shader`, `vk: ...`, `frametime:`, `texture`, `vk: headroom`, `mem: mirror`, `released`, `gfx: window focus`, and presentation resolution. Determine whether full screen performance gain is sustained, and if fullscreen is native 3840x2160 presentation or another window size. This will guide whether to safely re-enable prebuild *one flag at a time* or isolate texture alignment. Need verify parameters before suggesting any prebuild modification. No direct claim of render fix yet.

## Uploaded fullscreen log analysis and graphics-white-flash test (Nov 8 ~22:40 ET)

The user uploaded `NX2navi-FULLSCREEN-15FPS.log` (790 lines) from the fullscreen run. Facts grounded in the complete log:

- On start `gfx: window 1920x1080`, internal picture remains **2560x1440**, and after selecting fullscreen the log explicitly says `vk: FSR upscales 2560x1440 to 3840x2160 (sharpness 80)`, so 4K output scaling happens when fullscreen.
- Opening 60 seconds: 1639 frames in 60.1 s = 27.3 FPS but includes startup/menu. Final 114 frames in 9.6 s = **11.9 FPS**, 1% low 9.3 FPS, consistent with user reporting peak **15 FPS** in gameplay. The process exited normally (`gfx: window closed; exiting`), **no FATAL**.
- `NX2NAVI_PIPE_PREBUILD=0` gave **2023** records not prebuilt; `NX2NAVI_GPL=0`, `NX2NAVI_LIB_PREBUILD=0`; the host says `vk_exec: draws skipped while their pipeline builds: those and full-screen draws (NX2NAVI_PIPE_SKIP=fullscreen)`. The vertex draw census at frame 600 counts 23 draws skipped for pending pipelines; the next 600 counts 3; `first mesh draw skipped because: pipeline still building (program 6783)` appears in gameplay. Only four explicit one-shot waits were logged: 8.3ms, 2.1ms, 2.9ms, and 13.7ms.
- Worst opening frame 1214 2211.5ms with 98.7ms texture upload (20ms ASTC), 196.5ms graphics replay, zero shader or pipeline build; frame 1204 719.4ms with 268.0ms texture upload and 595.5ms replay; another frame 1551 has 68.1ms shader translation and 125.8ms pipeline build. The start and end frame time statistics demonstrate multiple independent causes of uneven pacing.
- `MapPhysicalMemory.*failed 0x10801` count **189**, in a contiguous burst around frames 1200-1600; guest app pool still 12-GiB test; this is `LimitReached` and known recoverable, not a GPU crash.
- Near memory load: four tiny 4 KiB pools stay imported as their VRAM mirror is denied at 7581 MiB use / 8627 MiB budget (other reserved headroom/threshold applies), so VRAM pressure persists but mirrors alone not enough to explain flashing.
- High ASTC GPU decode activity: 27,653 cumulative regions, ~2.68 billion decoded texels. It can cause visible first-use texture stutter but not necessarily persistent white flashes.
- No focused proof the white flashes were from a skipped pipeline vs texture/alias upload; video/timestamp correlation absent.

### Next isolated test: restrict pipeline skipping to per-frame passes

NX2navi upstream source `runtime/vk_exec_draw.c` defines `NX2NAVI_PIPE_SKIP` modes: `strict` skips only draws in passes where *all* targets were rendered in previous frame; `any` allows some targets; default `fullscreen` also skips full-screen draws. The user sees transient off-white flashed/incomplete scene as a pass appears and then resolves. To test skipped-draw hypothesis **change only** `NX2NAVI_PIPE_SKIP=strict`, retaining working 12 GiB guest pool, movie skip, current window/fullscreen settings, and Baseline script (recorder/gpl/dynamic vertex/prebuild off). It will force more first-use draws to **wait for pipeline**, possibly trading white flashes for more stutters (or a Vulkan driver fault). Do not delete caches. Compare visual white flashes **at the same location, on first and second visit**, and sustained FPS. Abort/revert if stalls worsen. Environment override should be removed at end. If `strict` changes flashing, work on pipeline warmup/prebuild separately, but only after verifying that prebuild won't reproduce old Intel Arc crash. If it doesn't, investigate texture/alias/guest pool via source and minimal tracing, not random toggles.

Sample settings:
```powershell
$script = "$env:USERPROFILE\Downloads\NX2navi-B570-Compatibility-Lab\NX2navi-B570-Test.ps1"
$env:NX2NAVI_APP_POOL='0x300000000'
$env:NX2NAVI_MOVIE_SKIP='1'
$env:NX2NAVI_WINDOW_SIZE='1920x1080'
$env:NX2NAVI_PIPE_SKIP='strict'
try { powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Test Baseline } finally {
  'NX2NAVI_APP_POOL','NX2NAVI_MOVIE_SKIP','NX2NAVI_WINDOW_SIZE','NX2NAVI_PIPE_SKIP' |
    ForEach-Object { Remove-Item "Env:$_" -ErrorAction SilentlyContinue }
}
```
The previous environment may hold a fullscreen setting saved by the in-game menu in `nx2navi.ini`; do **not** change it for this A/B. Re-enter fullscreen using same method as before. Keep wallpaper disabled.

## Test 16 strict skip first 35-second video + user FPS correction (Nov 8 ~22:46 ET)

User tested `NX2NAVI_PIPE_SKIP=strict` with the otherwise successful fullscreen 12-GiB baseline and recorded ~34.7s gameplay. All 12 evenly sampled frames show fully drawn scene, character, forest path, trees, light rays, HUD, and **no conspicuous large white flash**; on-screen overlay in those samples is generally 6–9 FPS. **Important user correction**: **this Test 16 ALSO peaked at 15 FPS**, same as previous fullscreen `PIPE_SKIP=fullscreen`. Do not call the strict run a lower-FPS test merely because 6–9 FPS appeared in some video frames; peak is unchanged, but sustained averages not yet established, so evidence is for apparent improved visual completeness, NOT a definite sustained-speed win or loss.

Source `runtime/vk_exec_draw.c`: `strict` skips only draws in passes all of whose targets were previously rendered; `fullscreen` skips more draws, including fullscreen draws while their pipelines build. Visual improvement is consistent with skipped-draw artifact hypothesis, but not proven causal without explicit log/pipeline correlation and matched scene first-time traversal. User's launcher automatically saves `Desktop/NX2navi-STRICT-TEST.log` after Test 16. Next step: user should provide this log for count of skipped draws and long frames, verify `vk_exec: draws skipped while their pipeline builds: only draws into per-frame passes`, compare with previous fullscreen log. Preserve caches and working baseline, avoid simultaneous settings changes; investigate separately whether `PIPE_PREBUILD=1` for shader-warm first visit is safe before proposing it.

## Test 16 strict fullscreen uploaded LOG confirmed (Nov 8 22:44–22:46 EST)

Analyzed complete `NX2navi-STRICT-TEST.log` (879 lines) and compared to `NX2navi-FULLSCREEN-15FPS.log`:
- Strict **verified** `vk_exec: draws skipped while their pipeline builds: only draws into per-frame passes (NX2NAVI_PIPE_SKIP=strict)`. Internal render stays 2560x1440; fullscreen scales to 3840x2160. Default texture eviction back to 90%, no heavy profiler, pipeline prebuild **off**, `2053` pipeline key records not built.
- **190 guest `0x10801` LimitReached errors** (previous fullscreen: 189), so guest app pool exhaustion unchanged. Frame 1800: `579` mirrored pools (~860.2 MiB), `79` VRAM-budget-denied pools (~15.1 MiB), ~22.6 MiB/frame mirror uploads, ~12.7 MiB/frame writebacks, ~106 mirror syncs/frame. Significant streaming/VRAM pressure remains.
- **Late steady frame rate** 541 frames/60.1sec = **9.0 FPS**, 1% low 4.5. Final 78 frames/8s = **9.8 FPS**. User explicitly saw peak **15 FPS**, as before; do not confuse these different metrics. Prior fullscreen `PIPE_SKIP=fullscreen`: final 114 frames/9.6s = 11.9 FPS; not matched workloads/locations, so strict not clearly faster or slower.
- **32 explicit one-shot/fullscreen pipeline waits** (previous fullscreen: 4), including frame 1869 **1464.4 ms graphics pipeline wait** (one-shot shader), resulting 1594.9ms frame. At frames 2294–2309 **16 consecutive ~49–50ms waits** for fullscreen pipelines still being built, and skipped after timeout despite strict. Draw census frame 1800: **526 skipped vertex draws of 867,829**; next 600 frames: **196 skipped of 800,320**, despite strict mode. This supports first-use missing draw artifacts, but white flashes may also relate to texture/alias/VRAM. In source `runtime/vk_exec_draw.c`, strict mode doesn't prohibit skipping every draw, so occasional white screen can remain. No fatal crashes.
- User video shows scene mostly complete; strict may reduce obvious flashes but **does not eliminate unready pipelines or persistent ~9-10fps CPU/GPU bottleneck**.

### Candidate Test 17: known graphics pipeline prebuild at boot

Upstream `runtime/vk_pipeline.c` implements `NX2NAVI_PIPE_PREBUILD=1`, which translates/builds recorded pipelines **before the game starts**. This directly targets the 1464ms first-use stall and some missing-pass issues. **Crucial**: our downloaded `NX2navi-B570-Test.ps1` Baseline explicitly *overrides* `NX2NAVI_PIPE_PREBUILD = '0'` inside the launcher. Merely setting `$env:NX2NAVI_PIPE_PREBUILD='1'` before calling `-Test Baseline` WILL NOT WORK. Create a separate temp copy of launcher with the single exact line changed to `'1'`; don't overwrite known-good script. Keep all other fixed Baseline config (GPL=0, lib prebuild=0, vk recorder=0, dyn vertex=0) identical. Restore 12 GiB `APP_POOL`, movie skip, window size 1920x1080, strict skip, wallpaper off.

**Risk:** with GPL=0 the port waits for **all** recorded known pipelines to finish before guest game startup; ~2053 may create substantial CPU compilation / startup delay, resource pressure, or trigger known Intel Vulkan driver crash. Upstream protects repeated failed boots through `pipeline-prewarm-running.txt` / `pipeline-prewarm-skip.txt` so a crash marks driver+GPU and next prebuild skips, while regular Baseline bypasses prewarm. Prebuilding can warm previously seen pipelines but **cannot prebuild unseen shaders** or fix persistent memory pressure. Monitor host memory / crashes, and immediately restore original launcher if problems. Do not delete caches.

If avoiding prewarm risk, another next isolated performance option is `NX2NAVI_TEX_RELEASED_MB=1024` to reduce retained stale texture memory, but that has potential for texture reuploads and increased flashing, and doesn't solve recorded pipeline waits.

## Test 17 result: full pipeline prewarm gave stable ~10–14 FPS; remove movie skip (Nov 8 22:59 ET)

The user tested the separate patched Test 17 launcher `Desktop/NX2navi-B570-Prebuild-Test.ps1` that **only** changes its internally forced `NX2NAVI_PIPE_PREBUILD` from `0` to `1`, keeps `NX2NAVI_GPL=0`, `NX2NAVI_LIB_PREBUILD=0`, `NX2NAVI_VK_DYN_VERTEX=0`, `NX2NAVI_VK_RECORDER=0`, and runs with APP_POOL 12 GiB, movie-skip=1, window 1920x1080, PIPE_SKIP=strict, and fullscreen selected in app. The user reports **14 FPS peak**, generally **did not dip below 10 even when jumping**, and remaining transient white flashing. This is the first user-reported post-jump performance improvement that persists through that area, but no identical-workload controlled comparison of sustained averages.

Uploaded `NX2navi-PREBUILD-TEST.log` (873 lines) confirms prewarm succeeded:
- `vk_pipeline: prewarm: 2106 records ... 1287 pipelines built, 0 failed, 819 already built, 0 dropped; shaders 6485 ms, pipelines 222 ms on 16 threads, total 6708 ms`. Game guest starts ~6.8 s after process start. There are **0 logged `vk_exec: frame ... waited ... for its pipeline`** events and no `FATAL:` in this run (vs Test16 frame 1869 1464 ms pipeline wait). The 60s window is 1997/60=33.3 FPS including menu+startup; late gameplay exit window 97/8.5 = **11.5 FPS** (1% low 9.6) consistent with user-reported 10–14 FPS.
- Still **249 `MapPhysicalMemory ... failed 0x10801`** guest limit errors and device-local budget usage **8974 of 9012 MiB**, with 47 mirror pools / 9.0 MiB kept imported due to VRAM budget; guest + GPU memory pressure remains.
- First 3D load: frame 1647 592.6ms incl **315.8ms texture upload** (ASTC 57.7), graphics replay 586.3ms; frame 1648 727.8ms incl texture upload 95.0ms, replay 225.1ms. No big pipeline wait at these frames. White flashes are therefore no longer strongly explained by previously recorded pipeline stalls; possible texture/alias/sync, but **not proven**.

**Explicit user request**: remove intro-movie skipping, because the forced one-second movie skip makes startup/load black screen feel glitchy. Log clearly confirms `movie: movies end after 1.0 s (NX2NAVI_MOVIE_SKIP)`. **Do not** disable prewarm; keep Test17's working prebuild enabled and **remove the `MOVIE_SKIP=1` override only**. Do not replace with `NX2NAVI_MOVIES=off` (that caused an exit previously). The next isolated run allows full normal intro with prewarm on. It may take longer; no proof yet that removing skip fixes black loading screen. When comparing, ensure no other settings or environment change.

Created a separate wrapper `NX2navi-B570-Prebuild-NormalIntro.ps1` for the user. It requires the existing `Desktop/NX2navi-B570-Prebuild-Test.ps1`; unsets inherited `NX2NAVI_MOVIE_SKIP`, sets APP_POOL=12GiB/WINDOW_SIZE=1920x1080/PIPE_SKIP=strict, calls the proven prebuild launcher, and writes `Desktop/NX2navi-PREBUILD-NORMAL-INTRO.log`. The working Test17 script is left untouched. The wrapper is available as a downloadable file in the current conversation and also will be committed to this branch. Once tested, user can compare the intro and gameplay FPS/flashes.

Next performance objective: target texture/alias and VRAM pressure separately, not pipeline prebuild again; don't delete caches or raise guest pool to 16 GiB (SDK aborts).
