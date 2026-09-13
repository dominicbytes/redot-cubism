# CubismModel2D implementation status

`CubismModel2D` is the preferred native `Node2D` API under development. It owns
one internal `GDCubismUserModel`, retaining the existing allocation, resource
loading and renderer implementation. The internal child has no scene owner and
is not serialized. The public `model` resource supplies normal export dependency
edges. Legacy scenes and methods remain available during migration.

The implemented foundation includes resource assignment, load/unload/reload,
state and error queries, typed lifecycle signals, idle/physics/manual processing,
speed and pause controls, physics/pose switches, parameter/part IDs, parameter
writes, part-opacity writes and canvas information. Native motion playback now
provides IDs/groups, priorities, independent speed/loop state, fades and retained
handles with deferred events and terminal signals. It does **not yet complete**
expression control, autoplay/default cues, deterministic effects,
look/hit testing, advanced rendering policies or character/audio controller.
Those remain required work in the canonical plan.

```gdscript
var character := CubismModel2D.new()
character.playback_process_mode = CubismModel2D.MANUAL
add_child(character)
if character.load_model(load("res://character.res")) == OK:
    character.set_parameter_value(&"ParamAngleX", 10.0)
    character.advance(1.0 / 60.0)
```

Loading completes synchronously when native loading is not already busy.
Lifecycle signals are delivered afterwards, in started/ready or started/failed
order. Superseded loads and unloading cancel stale notifications. Use Redot's
normal `queue_free()` when deleting from a signal callback; removing the node
from its parent during that callback is supported. `unload_model()` retains the
public resource selection for `reload_model()` but disables automatic loading
until an explicit load/reload. Ordinary tree exit disposes the internal runtime;
tree reentry recreates a previously loaded selection without needing another
`_ready()` call. Assigning a null model also clears the public selection.

`playback_process_mode` is distinct from inherited `Node.process_mode`. Native
internal notifications drive idle/physics updates even if a user script overrides
or disables its regular callbacks. Manual `advance()` respects scene-tree pause,
the node's `paused` property and `speed_scale`. Zero speed, zero delta and
nonfinite delta do not consume queued writes. The existing finite-step cap and
speed range remain in force; this is not an arbitrary-time seeking API.

Parameter writes are queued in call order for the next successful update, after
physics/pose and before Core updates drawable state (`POST_EFFECT`). Each write
is consumed once. Continuous control resubmits each step. Getters report the last
evaluated value, so queuing a write does not change a getter immediately. Reload,
unload and tree exit discard pending writes. This leaves legacy parameter-setter
semantics unchanged.

For current value `c`, requested value `v` and weight `w`, set computes
`c * (1-w) + v*w`, add computes `c + v*w`, and multiply computes
`c * (1 + (v-1)*w)`. Each result is clamped to the real model parameter range.
Values and weights must be finite; weights must lie in `[0,1]`. Unknown IDs
return `ERR_DOES_NOT_EXIST`; writes without a ready model return
`ERR_UNCONFIGURED`. Use `has_parameter()` before reading optional IDs; an unknown
parameter getter returns zero. Part opacity is queued at the same stage and
clamped to `[0,1]`. The bounded write queue reports `ERR_OUT_OF_MEMORY` rather
than growing indefinitely.

`tools/run_model2d_tests.py` uses the private Haru imported fixture. It checks
resource lifetime, parameters, signals, pause and native processing, then loads
a saved public node through a source-free checked export. Its graphics option
compares normal and transformed/part-opacity captures with the legacy runtime.
This comparison establishes wrapper equivalence for those states, not full SDK
renderer parity or Windows qualification.

## Native motion playback

Use the imported stable IDs (for example `Idle/0`) from `get_motion_ids()`, or
`play_motion_from_group(group, index)`. Low-level playback never starts audio,
even when the descriptor has a sound association. Motions are authored/exported
in Cubism; this API does not record animations in the engine.

```gdscript
var handle := character.play_motion(&"Idle/0", CubismMotionPriority.NORMAL)
if not handle.is_finished():
    await handle.finished
if handle.get_reason() == CubismMotionHandle.FAILED:
    print("Motion failed: ", handle.get_error())
```

Every call returns a `CubismMotionHandle`. Rejected calls are already terminal
with reason `FAILED` and a Redot error code; check state before awaiting.
Accepted handles have unique instance IDs and start in `PLAYING`. Handles own
status, source ID, elapsed time and loop count, never a native model pointer.
They remain readable after unloading or deleting the node.

Priority `IDLE` is 1, `NORMAL` is 2 and `FORCE` is 3. A new motion must have higher
priority than the active one; `FORCE` can always replace it. `NONE` is the idle
reservation value and cannot start playback. Rejection leaves the active motion
unchanged. Every accepted playback owns an independent SDK motion and queue
entry, including two plays of the same source with different loop/speed options.
The loaded catalog and source bytes are snapshots; reload to adopt edits.

Per-playback speed must be finite and in `(0,256]`. It multiplies model speed;
pause freezes both. The first successful update advances from motion time zero,
so a linear motion is already at `delta * speed` on its first evaluated frame.
One-shot elapsed time stops at its native duration. The pinned R5 V2 SDK includes
one source frame (`1 / Meta.Fps`) in a looping cycle; event and loop counters use
that same period. Time-zero events fire on the first update of each cycle, and
Unicode event values retain their contents. Finite bounded updates are required;
this API does not seek or rewind.

`stop_motion(0)` removes active motion influence immediately. A positive fade is
measured in model time, before per-motion speed, and advances only with the model.
The default `-1` uses the native motion's fade duration in motion time. A stopped
or interrupted handle becomes terminal immediately, while its native influence
can continue fading. Fading blends against the saved parameter pose; it does not
implicitly return every parameter to zero. Outgoing terminal plays emit no new
motion events. Starting another motion uses the outgoing motion's default fade.

The handle emits `event(value)`, `looped(count)` and `finished(reason)`. The node
forwards these with the handle and exposes `motion_started(handle, motion_id)`.
Signals are deferred until native iteration is safe. End events precede natural
completion; each accepted handle terminates once. Reasons distinguish completed,
stopped, interrupted, failed, unloaded, reloaded and model disposed. A loop emits
loop boundaries without completing. A deleted node cannot forward signals, but
a retained handle still delivers its terminal notification. Use `queue_free()`
for node deletion from callbacks.

The runtime bounds retained fading plays to 256 and returns `ERR_BUSY` when full.
It terminates adversarial event/loop bursts with `FAILED` rather than spending
unbounded time in one update. Invalid or ambiguous catalog IDs and invalid event
times are rejected. No new SDK model or renderer is allocated for a playback.

Add `--motion` to `tools/run_model2d_tests.py` to import private synthetic curves
on Haru and exercise timing, priorities, replay, events, fades and handle lifetime
in both the editor and source-free export. With `--graphics`, an animated pose
is also compared pixel-for-pixel with a separately assigned legacy parameter pose.
