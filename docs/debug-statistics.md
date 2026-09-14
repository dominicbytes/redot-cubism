# Runtime diagnostic statistics

`CubismBuildInfo.get_debug_statistics()` returns a snapshot for all live Cubism
runtimes, including legacy nodes and the internal runtimes of `CubismModel2D`.
Call it on the main thread. Addon debug builds return `enabled: true`; release
builds return only `{"enabled": false}` and compile out the instrumentation.
A debug editor does not enable counters in a release addon library.

| Field | Measurement |
|---|---|
| `loaded_models` | Initialized native models |
| `live_drawable_nodes` | Runtime-owned `MeshInstance2D` nodes, including mask and fallback instances |
| `live_mesh_resources` | Distinct meshes referenced by those instances |
| `live_material_resources` | Distinct materials referenced by those instances |
| `live_mask_viewports` | Runtime-owned mask composition viewports |
| `live_compositor_viewports` | Runtime-owned fallback atlas viewports |
| `live_motion_handles` | Handles retained by native playback, including fading motions |
| `frame_id` | `Engine.get_process_frames()` for the sampled interval |
| `model_update_usec` | Accumulated CPU microseconds in native model/effect evaluation |
| `renderer_update_usec` | Accumulated CPU microseconds in drawable and compositor updates |
| `vertex_bytes_uploaded_last_frame` | Vertex-buffer bytes submitted during the interval, including initial surfaces and the fallback output quad |
| `mask_redraws_last_frame` | Distinct mask viewports requested to update during the interval |

Resource counts describe runtime ownership. They exclude resources kept alive
only by caller references after unload, texture/shader caches, and engine/GPU
allocations. A caller-retained finished motion handle therefore does not count
as a live playback handle. Use sanitizer and engine resource checks alongside
these counters when investigating leaks.

Despite the `last_frame` suffix, the work counters accumulate in the **current
process-frame interval** identified by `frame_id`. Read after model evaluation
(or `RenderingServer.frame_post_draw` for a rendered frame), before the next
process frame. Multiple manual or physics steps in that interval add their work;
entering a new process frame resets the work counters, including idle intervals.
The initial process signal can still have frame ID zero and include loading work.
Warm up and wait for the frame ID to change before measuring steady-state work.

CPU timings include callbacks inside their respective scopes and exclude GPU
execution. A callback that evaluates another model can cause nested time to be
counted in both evaluations. Renderer timing excludes render-thread/GPU work;
vertex bytes exclude indices, UVs, textures, and driver-internal transfers.
Mask requests are deduplicated per viewport per process frame. They are not a
count of completed GPU draws: an `UPDATE_ALWAYS` viewport can render without a
new model evaluation. Hidden/culled masks that receive no redraw request contribute
zero. Snapshot construction itself scans owned resources and allocates temporary
containers, so collect snapshots outside the CPU sections being measured.

The native graphics regression checks ownership against the actual scene tree
in Direct and SubViewport Fallback modes, additive manual-step uploads, frame
reset, hidden-mask requests, and ownership returning to zero after unload.
`tools/run_model2d_tests.py --graphics --motion` includes this check in both the
source project and checked export. The [benchmark runner](benchmarks.md) records the plan's eight scenarios using
these counters. Diagnostic checks alone do not establish a performance baseline.
