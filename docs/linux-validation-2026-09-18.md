# Linux validation snapshot (2026-09-18)

Linux debug and release libraries built from native source `55dd0604d605586e79f65664d448f78d9a8dad36` passed the bounded functional, SDK comparison, visual, and sanitizer checks below. A test-only checked-export UI correction at `62994327e05adacf6244d82c53f5c0d572d0a295` was used for the completed export checks; the native libraries were **not** rebuilt at that commit. This snapshot is not final release qualification.

| Area | Verified result |
| --- | --- |
| Native builds | Debug and release builds passed. Debug library SHA-256: `b8981dafb37357e57c381ccc0a5025fb17a527a26414d434ecb8621a811fe629`; release: `b7ce294fc56d2f0bea79c750c889b00f027c6c9122c64a700a4e51518e399297`. |
| Desktop functional | Debug coverage passed across ten stages as a **composite** of the original run, a corrected checked-export rerun, and three later export stages. The original debug aggregate remains **FAIL**: six stages passed, checked-export failed on the test's fabricated PID, and three stages were not run. The corrected checked-export rerun passed 7/7. One release aggregate passed all ten stages with the corrected harness and frozen release library. |
| Model2D | Debug and release stages each passed 45/45 checks. Each included native and exported 98-assertion motion checks, 99-check overlays, and 40-check controller audio timing. |
| SDK and visual checks | 384/384 SDK motion comparisons passed across ordinary and uncapped manual stepping in both build variants. The reviewed visual matrix passed 92/92 cases across eight fixture families in both variants. |
| Sanitizers | The matched Linux ASan/UBSan run passed 26/26 checks and 250 lifecycle cycles. The addon and public Framework were instrumented; proprietary Core and a prebuilt binding archive were not. |
| Later asset change | At `b338d9cd8527321bfa566ca827e3696a59a79dd3`, focused static asset references, normal SVG import, and installed-addon scene/texture loading passed with the frozen `55dd060` native library. This does not claim a new native build or model playback at the successor commit. |

Three sequential Linux VM benchmark trials then passed all eight workloads using the frozen `55dd060` **debug** library: 60 warmup and 300 measured frames per workload, for 7,200 measured frames across 24 scenario runs. Each child workload and cleanup check passed. The viewport was 1024×768 with fixed 1/60 simulation steps, VSync off, and no FPS cap. The renderer was X11 GL Compatibility through Mesa virgl on an NVIDIA-hosted VM. These are observed debug-instrumented VM measurements, not release-build or native NVIDIA-driver FPS.

| Workload | Observed rendered FPS range | Frame p95 range (ms) | Model CPU p95 range (ms) | Renderer CPU p95 range (ms) |
| --- | ---: | ---: | ---: | ---: |
| Static, 1 model | 86.60–99.81 | 13.27–16.61 | 0.93–1.14 | 2.02–2.70 |
| VN, 2 models | 44.97–54.20 | 24.79–31.37 | 1.32–1.69 | 4.66–6.07 |
| Party, 3 models | 30.02–38.59 | 36.61–50.85 | 1.72–2.18 | 7.83–10.31 |
| Crowd, 8 models | 12.56–15.33 | 96.68–114.98 | 3.54–4.37 | 22.71–27.41 |
| Masks, 1 model | 35.32–36.69 | 34.47–39.12 | 0.89–0.96 | 5.68–6.11 |
| Physics, 3 models | 35.35–41.16 | 33.01–44.65 | 1.72–2.48 | 6.97–9.54 |
| Offscreen, 8 models | 29.37–39.05 | 44.66–62.39 | 2.61–3.75 | 19.99–27.05 |
| Hidden, 8 models | 27.07–37.17 | 44.35–59.31 | 2.60–4.05 | 21.00–28.19 |

Rendered FPS is the reciprocal of each trial's **mean** frame interval. Frame p95 describes the slow tail; the separate CPU phase p95 values cannot be added to derive it. Offscreen and hidden workloads still advance models manually; their measured mask redraw requests were zero, but their CPU work was not. Benchmark status is `PASS` with `MEASURED_ONLY` qualification: there is no accepted dedicated-machine baseline or reviewed regression threshold.

An earlier benchmark attempt passed six workloads, then its offscreen child ended without a raw result. That runner did not retain the child's exit code, and no system crash or out-of-memory record was found. A focused offscreen rerun passed 300 samples with zero mask requests, followed by the three complete passing trials above. The first failure remains unexplained and is retained as a separate failed result.

The remaining gates are final cross-platform integration of the test-only correction, a reviewed dedicated Linux GPU benchmark baseline and threshold, protected licensed CI on the agreed final source, manual editor/physical-display coverage, and final release and rights review. Automated single-output VM checks do not establish physical GPU, mixed-display, drag/grid, or native-minimize behavior. No licensed model, SDK binary, private project path, or private test artifact is included here.

## Parser robustness follow-up

Clean source `3d1ed624c29afdd065d40eaaa9d877e97ccd1aba` includes the Windows
import-option diagnostic repair: nontext keys produce textual paths and echoed
option names are bounded to 4096 characters. Matching Linux debug and release
libraries were built with the same pinned dependencies. Their SHA-256 values are
`57fbb0e741c8bc345cf0f25ebc3a86afeab2992e47d005032ad688c7d3f2ebef` (debug) and
`d28aba506de64ec709da44a42da37a1e9735acce18c7d647e329d80a2c667796` (release).

Both variants passed the bounded 108-case parser campaign with two fresh-process
replays per case: 432 worker executions total. Import/class preflights passed;
no supervisor violations, unexpected engine diagnostics or replay differences
occurred. Every case's canonical result matched both Windows `a6133ba` variants.
The Linux supervisor used its unchanged 2 GiB per-worker address-space limit;
this is not an aggregate process-tree memory cap or proprietary Core fuzzing.
The seven Python corpus/contract/supervisor regressions also passed on Linux.

Real-model importer checks passed all 23 headless stages per variant, including
88 import-option assertions, restart, cache removal, runtime loading and
source-absent exported model/texture/alpha checks. Stock compound-suffix
`automatic_discovery` remained false. The three graphical dependency-change
stages were outside this targeted run.

This follow-up covers the changed parser/importer behavior. The full desktop,
SDK, visual, sanitizer and benchmark results above retain their `55dd060`
library identities. Pure `3d1ed62` still lacks the separately reviewed `6299432`
checked-export test correction; no full desktop aggregate on pure `3d1ed62`
or final release qualification is claimed.
