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
advanced rendering policies or character/audio controller.
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

## Expressions

`get_expression_ids()` returns the loaded expression names. Use
`set_expression(id, fade_seconds)` and `clear_expression(fade_seconds)` to control
the expression layer independently of body motion. A successful change queues
`expression_changed(id)`; clearing queues an empty ID. Unload/reload suppress
stale expression notifications. Unknown IDs and invalid fades return errors
without changing the active expression. Clear without a loaded model is a no-op;
invalid clear arguments report `runtime_warning`.

The default fade argument `-1` preserves the expression file's native fade values.
A nonnegative override sets that playback's fade-in and fade-out durations; zero
is immediate on the next evaluation. Fade time follows the model clock, including
speed and pause. R5 expression fades start at the first evaluated frame, unlike
the preferred body's motion-time-zero convention. Every set creates a new SDK
expression owned by the existing expression queue. It uses cached validated bytes
and never changes a shared expression resource or a previous play's fade settings.
At most 256 pending expressions may overlap before an update; further sets return
`ERR_BUSY` until the native manager can retire old entries or the layer is cleared.

Normal expression transitions preserve R5's add/multiply/overwrite blending.
Expressions apply after primary motion and before physics/pose and queued user
parameter writes. An explicit clear interpolates the evaluated expression result
back to the current primary pose using sine easing. This adapter is necessary
because an empty R5 expression drops overwrite values without fading them. It
does not freeze body motion while clearing. When a new expression interrupts a
clear, partial layer influence recovers over the incoming expression's fade;
a zero-duration set restores full layer influence immediately. Repeated clear
requests begin at the current layer influence. Once clearing finishes, the SDK
expression manager is reset, including its private fade-weight bookkeeping.

The `--motion` test fixture includes simple add/multiply/overwrite expressions.
Tests compare default fade trajectories with the legacy SDK manager, check
motion composition, clear/replay and lifecycle behavior in editor and exported
builds, and compare expression/half-cleared render states to known parameter poses.

## Autoplay defaults

Set `autoplay = true`, `default_motion` and/or `default_expression` before loading
or entering the scene tree. Autoplay is off by default. Startup runs once when a
loaded node is inside the tree. For loads inside the tree, defaults start before
the `model_ready` callback. A model loaded outside the tree waits for entry;
its ready signal may already have been delivered. Reloading or leaving and reentering the tree
starts the configured defaults again; explicit unload and null assignment do not.
Changing these properties after startup configures the next load/entry; it does
not start or interrupt a live cue. Empty default IDs skip that layer.

The default motion uses `IDLE` priority and its loaded descriptor's loop setting.
One-shot defaults finish normally and are not restarted every frame. Autoplay
does not play descriptor audio. The default expression uses source fade values.
Successful explicit play/set calls before deferred startup suppress the default
for that layer; explicit stop/clear calls do so too. A `model_ready` handler can
replace the idle default with a normal-priority cue. Invalid defaults emit one
`runtime_warning` per requested layer and leave the model usable.

These properties are serialized on the public node. The `--motion` suite saves
and reopens an autoplay scene, then exercises it again from a source-free export.

## Procedural blink and breath

`enable_eye_blink` and `enable_breath` are off by default. Enable either explicitly
when the character should receive procedural animation. They run after expressions
and before custom effects, physics, pose and queued `POST_EFFECT` writes. Turning
an effect off releases its influence and freezes its clock until reenabled.
Model pause and speed controls apply to both effects. Reload/reentry resets their
state while retaining the selected settings.

Blink uses the manifest's existing eye parameter IDs. As in the pinned SDK's
`CubismEyeBlinkUpdater`, any primary-motion update suppresses procedural blink
for that frame, including an outgoing fade and the final motion frame. Its clock
also pauses during suppression. This preserves authored eye curves and native
motion effect-ID ownership. Expressions retain the SDK update order, where a
procedural blink can follow an expression if no primary motion is updating.

`deterministic_seed` selects an instance-owned xorshift64* stream for blink timing;
it never calls process-global `srand()` or `rand()`. Setting the seed resets blink
timing, including setting the same value again; it does not reset breath. The
documented profile uses the R5 default close/hold/open durations (0.1/0.05/0.15
seconds), a uniform wait in `[0,7)` seconds, and no carry of step overshoot across
phase transitions. The random sequence deliberately differs from platform libc
`rand()`. Repeatability requires the same model, seed, engine/SDK/platform, fixed
steps and effect settings; this is not a cross-architecture float identity claim.

Breath delegates to `CubismBreath` with the five standard SDK sample profiles for
head angles, body angle and breath. Only real model parameters are registered.
Its trajectory is compared against the existing legacy breath effect. Procedural
tests also verify seed independence under reversed construction/update order,
phase durations, reload, pause, disable/resume, authored eye motion/fades, and final
user overrides. Graphics checks compare closed eyes to an explicit parameter pose
and breathing to the legacy SDK effect. Procedural settings are checked in saved
and source-free exported scenes.


## Look targeting

`set_look_target(local_target, weight)` accepts node-local pixels, the same space
as the rendered model. For a world-space point, pass `to_local(global_point)`.
Imported layout translation and scale are undone before normalization; half of
each canvas dimension corresponds to full look deflection on that axis. Y is
converted to the SDK's upward direction, and each direction is clamped to [-1,1].
The model origin is neutral. The target stays local when the node moves; call the
method again to follow a stationary world point or the mouse.

`enable_look_target` defaults to true but has no effect until a target is assigned.
The SDK's `CubismTargetPoint` provides smoothing, including its initial neutral
evaluation. Standard head angles use range 30, body angle 10, and eye direction 1;
only existing parameters are affected. A finite weight in [0,1] scales the
additive contribution. The effect runs after breath, before custom effects,
physics, pose and queued manual overrides. Model speed and pause govern its clock.
Disabling releases influence on the next evaluation and freezes smoothing;
reenabling resumes it. Weight zero releases influence while smoothing continues.

`clear_look_target()` removes influence on the next evaluation and resets the
SDK smoothing state. Reload, unload and tree exit discard targets; the enable
flag is retained and serialized. Targets are transient. Invalid coordinates or
weights emit `runtime_warning(ERR_INVALID_PARAMETER, ...)` without changing the
active target; setting a target before model readiness emits `ERR_UNCONFIGURED`.

The look suite compares parameter trajectories against the legacy SDK target
point effect, including imported layout, mirrored/rotated node transforms,
clamping, weights, pause, disable/resume, speed, invalid input and reload.


## Hit queries and tracked pointer targets

`get_hit_area_names()` returns unique manifest names in their original order.
`hit_test(name, local_point)` uses the SDK's inclusive bounding box of each
current deformed hit drawable. Coordinates are node-local rendered pixels,
including imported layout. Duplicate names aggregate their drawables. Missing
names/drawables, empty drawables, nonfinite coordinates and unloaded models miss.
This is a geometry query: hidden or transparent hit drawables still define areas;
it does not test texture alpha or individual triangles and does not emit signals.

For hover transitions, feed one pointer with `set_hit_test_target(local_point)`
and call `clear_hit_test_target()` when interaction ends or leaves its surface.
This follows the legacy effect's explicit target workflow and supports mouse,
touch, controller selection and manually routed viewport input. The plugin does
not capture or consume mouse events. A mouse-driven scene can update the target:

```gdscript
var pointer_inside := false

func _process(_delta: float) -> void:
    if pointer_inside:
        character.set_hit_test_target(character.get_local_mouse_position())

func _on_interaction_surface_mouse_entered() -> void:
    pointer_inside = true

func _on_interaction_surface_mouse_exited() -> void:
    pointer_inside = false
    character.clear_hit_test_target()
```

Connect the interaction surface's mouse enter/exit signals to these handlers.
For a point from world space use `character.to_local(global_point)`; for custom
viewport input convert that viewport's point into the character's local space.
The target stays local as a node moves. Updating it each input/frame lets it
follow a stationary world pointer. Animation updates reevaluate retained targets.

Transitions are deferred and coalesce to the newest target before delivery.
Exits precede enters, each in manifest order. All overlapping logical areas can
enter; a stationary pointer does not repeatedly enter. Reload, unload and tree
exit discard the target and exit previously reported areas. Hiding or disabling
scene processing emits exits; showing/enabling reevaluates a retained target.
The model's `paused` flag only freezes geometry, so supplied target movement can
still change hover. Invalid target coordinates warn and retain the old target.
Targets and hover state are not serialized. Callbacks may clear, reload, unload,
hide or remove the node without delivering stale subsequent enters; use
`queue_free()` for deletion and do not expect exit callbacks during destruction.

With `--graphics`, the hit suite maps an animated SDK drawable to a test-only
region and compares queries with the renderer's current CPU-computed mesh
bounds across head poses, imported layout, rotation and mirrored/nonuniform scale.
It also checks UTF-8 names, overlapping aliases, missing areas, deferred ordering,
visibility, pause, processing, clear/reload/unload/tree exit and callback unload.
The headless path uses the fixture's original static hit areas because the existing
renderer compatibility guard skips mesh refresh without a visible window.
Animated geometry coverage requires the graphics run.


## Deterministic lip sync

Add a `CubismLipSync` node and assign its `target_model`. One live component may
own a model; a second assignment returns `ERR_ALREADY_IN_USE` and retains the
previous selection. Each component owns its envelope while profiles can be shared. A null profile uses
internal defaults; assign a new CubismLipSyncProfile to customize settings.
The model drives the component after look, before custom effects, physics, pose
and queued manual overrides. No child processing priority or extra advance call
is needed. Model pause/speed and the model's 0.1-second step cap govern its clock.
`enable_lip_sync` defaults to true and has no effect without an attached component;
disabling the model switch freezes the envelope and releases its contribution.

`MANUAL_VALUE` retains the newest finite nonnegative `submit_sample(value)` input,
clamped to [0,1]. Invalid samples return an error without changing the input.
`submit_peak_db(left, right)` supplies manual input through the same dB conversion
as bus sampling; negative infinity means silence, while NaN/+infinity are errors.
`AUDIO_BUS_PEAK` reads the maximum channel peak from the selected Redot audio bus.
Give each character its own voice bus to prevent unrelated sounds driving its
mouth. A missing bus produces silence and `ERR_DOES_NOT_EXIST` from `get_last_error()`.

The profile gates amplitude before gain, then clamps the desired envelope to [0,1].
For a time constant `tau`, one step follows `desired + (old - desired) * exp(-dt/tau)`;
attack is used when rising, release when falling, and zero means immediate change.
The normalized result maps between `minimum` and `maximum` and is added to each
existing target parameter. Empty IDs use the manifest lip-sync group; duplicates
apply once, and missing IDs are skipped and reported. Defaults are gain1, gate0.02,
attack0.03s, release0.08s, minimum0 and maximum0.8 (the SDK sample's additive weight).
The optional mouth-form ID receives a fixed configured value instead of amplitude.

Motion parameter curves, Model/LipSync curves and active expression parameters
retain ownership by default, including native outgoing fades. Ownership is read
from loaded motion bytes and native expression entries, not mutable descriptor
metadata. `blend_with_authored=true` explicitly allows additive envelope influence;
optional mouth form then writes its configured value. Final manual overrides still
win. This preserves the SDK's saved primary pose: disabling the envelope releases
its addition, not any pose authored by a motion or expression.

Setting component `enabled=false` stops and resets its sample/envelope. `reset()`
clears state while retaining enablement; a nonzero profile minimum can still
contribute. Reload/unload and component tree exit reset state. Profiles and target
selection serialize; samples and envelopes do not. Model destruction clears the
component target. Audio stopping makes a bus-driven envelope release toward silence;
use a zero release or disable the component for immediate removal.

This component does not start audio or maintain audio/motion alignment. The
character controller provides that coordination as described below.
The lip suite uses known amplitude vectors and generated PCM voices with Dummy
audio, including two separate buses; no microphone or audio device is required.

## Recorded voice and animation cues

`CubismCharacterController` owns an internal voice player and lip component and
targets an existing `CubismModel2D`. Its current implementation covers cue clocks
and retained completion handles, idle resumption, show/hide transitions and viewport
look targeting. Saved-state DTOs and VN/RPG examples remain under development.

```gdscript
@onready var character: CubismCharacterController = $CharacterController

func say_line(stream: AudioStream) -> void:
	var speech := character.speak(stream, &"Talk/0", &"Happy")
	if not speech.is_finished():
		await speech.finished
	if speech.get_error() != OK:
		push_error("Character cue failed: %s" % speech.get_error())
```

Assign `target_model` and an existing `voice_bus`. A separate bus per character
keeps envelope sampling isolated. `perform(motion_id, expression_id)` runs the
same native animation without audio; descriptor `Sound` is never played implicitly.
`speak` requires an explicit finite prerecorded nonlooping stream. Pass a lip
profile to enable volume-driven mouth animation, or null to use authored animation.
Authored mouth curves retain ownership unless that profile explicitly enables
blending. Changing target interrupts the active cue; a second controller cannot
claim the same model clock. Invalid IDs are rejected before replacing a valid cue.

During a cue the controller owns manual model advancement at speed 1, subdividing
steps to at most 0.1 seconds. An external `model.advance()` cannot double advance
the model. Prior model speed and playback process mode are restored on release.
Changing model speed during a cue fails it; use controller/target pause instead.
Controller pause and inherited scene pause stop both clocks. Target pause is
observed by the controller and also pauses its voice player.

Voiced playback follows the engine's playback position plus time since the last
mix minus output latency. Samples that cross a mixer timestamp reset retain the
previous estimate until the next update. Extrapolation is capped at one mixer
interval to bound prediction during audio-thread stalls. Backward jitter up to
the greater of 0.05 seconds or one mixer interval plus 0.005 seconds is clamped;
larger backward jumps terminate with `ERR_UNAVAILABLE`. Manual-clock tests retain
the fixed 0.05-second allowance. Catch-up is subdivided and
bounded to 60 seconds per call. General audio seeking is unsupported: interrupt
and start a fresh cue to restart. This is estimated audible alignment, not a claim
of sample-accurate output or measured physical device latency.

`cue_offset_seconds` is set while idle and accepts [-60,60]. Positive values delay
the motion while voice/effects run; negative values pre-roll the native model
before starting voice. `perform` ignores the voiced offset. When audio ends first,
model time continues until the assigned motion finishes; when motion ends first,
voice continues. The player can discard its clock before emitting `finished`, so
the controller detects inactive playback and drains the remaining time to the
known stream duration. A speech handle completes only after both are done.

Cancellation terminates a handle immediately and only once. `stop_speaking` may
fade voice and motion for up to 60 seconds before releasing the clock; zero stops
immediately. Hide, unload/reload, tree exit, target destruction and controller
destruction terminate outstanding handles with an inspectable reason. Lifecycle
cancellation also works when controller or scene processing is paused/disabled: the model
notifies its controller directly on lifecycle changes. Cancellation during a native
effect callback also stops the controller's remaining catch-up steps. Signals are
deferred after state changes, and immediate failures are already terminal; always
check before awaiting. Internal voice/lip children are implementation details.

For deterministic testing, `manual_process=true` uses `controller.advance(delta)`.
`manual_audio_clock=true` additionally suppresses audio output and accepts absolute
timestamps through `submit_audio_clock(position, finished)`. Keep that clock fixed
while paused. Manual clock mode does not sample an audio bus. The test suite drives
a 30-second native motion at 15/30/60 fps and checks both handle time and authored
mouth values against independent curve values. Real generated-audio checks cover
voice-only lip sync, authored mouth ownership, pause/resume and short-voice endings.
The optional `tools/run_model2d_tests.py --motion --audio-timing` suite plays real
30-second WAV cues at 15/30/60 fps caps and variable updates with 250 ms stalls.
It compares native motion time and authored mouth values against independent
player-clock samples. The declared tolerance is 120 ms against the buffered
engine clock, with `0.12 / 15 + 0.0001` mouth error for the fixture's triangular
curve. Logs report the observed buffer duration, scheduling and maximum errors.
Two controller voices on separate buses are checked through pause, stop and
asynchronous playback release. Physical-device latency, broader platform
coverage and complete controller workflows remain release requirements.

## Character checkpoint state

`capture_state()` returns `{ok, error, state}`. Its version 1 `state` dictionary
contains only JSON-compatible strings, numbers, booleans and arrays. It records
the model source path and import fingerprint, idle ID and active policy,
selected expression ID, local look target and weight, local visibility,
transform, tint, voice bus, cue offset, transition duration, automatic idle
resumption and controller pause. No resource, node, native pointer or live handle
is placed in the save data. Scene-owned process settings and model effect
configuration remain part of the character scene.

Capture at a dialogue checkpoint after the current cue and visibility fade end.
An owned idle loop may be running. Active cues, foreign clock ownership, native
callbacks and externally started motions return `ERR_BUSY`. A changed idle ID
must first be applied with `return_to_idle()` or the old loop stopped. Invalid
configured IDs or non-finite presentation values also reject capture.

```gdscript
var captured := character.capture_state()
if captured.ok:
    var file := FileAccess.open("user://character.json", FileAccess.WRITE)
    file.store_string(JSON.stringify(captured.state))

# Recreate the character scene and load its model before restoring.
var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://character.json"))
if saved is Dictionary:
    var error := character.restore_state(saved)
    if error != OK:
        push_warning(error_string(error))
```

`restore_state` requires all version 1 fields with their original types (JSON
numeric values may be integral floats), valid IDs and an existing voice bus.
Unknown fields, a mismatching model fingerprint and malformed values are
rejected before interrupting current playback. A private copy of validated data
keeps scene callbacks from changing the ongoing restoration. It loads no files from the saved
paths. After validation it interrupts an active cue, restores presentation,
restarts the selected expression without its old blend queue, and starts a fresh
idle loop if requested. Target destruction/reload from a synchronous scene
callback can interrupt this operation and returns `ERR_UNAVAILABLE`.

This checkpoint represents stable character choices. It does not capture the
current pose's parameter values, motion phase, voice position, physics/blink
history or an unfinished transition. Store dialogue progression with the game's
own save data; resume a line by starting a fresh cue. General seeking remains
unsupported.

## Idle, visibility and look utilities

Assign `idle_motion` and call `return_to_idle()` to stop a cue and start that motion
looping at IDLE priority. The controller retains its exclusive model clock while
idle, so `controller.advance()` also drives it in manual processing mode. A call
for the same running idle does not restart it. `is_idle()` distinguishes this state
from speech; `get_motion_handle()` returns the current idle handle. Idle does not
reset the character's expression. Invalid idle IDs leave an active cue intact.

`auto_return_to_idle` defaults to false. When enabled, normal cue completion starts
the configured idle; stops, interruptions, errors and hiding do not. An automatic
idle failure emits a deferred `runtime_warning(code, message)`. New cues replace
the idle. An external higher-priority motion can interrupt idle, after which the
controller releases its clock rather than repeatedly restarting it.

`show_character()` and `hide_character()` accept `none` or `fade`. Immediate changes
are the default. Fades use `transition_seconds` (default 0.2, finite range [0,60]);
zero makes them immediate. Hiding cancels speech with HIDDEN immediately and fades
any outgoing voice/motion. New cues are rejected while fading out. Showing does not
implicitly play idle. Controller/model/scene pause freezes fade progress.

Fades change modulate alpha while preserving RGB and the target's original alpha.
Hide completion restores that alpha while leaving the node hidden, so subsequent
shows recover its appearance. Reversing a fade keeps the same original opacity.
Retargeting or disposing the controller cancels a partial fade and restores opacity.
The controller owns alpha during the transition; avoid simultaneously animating it
from another script. The graphics suite compares a half-faded preferred model with
the same legacy-renderer opacity.

`look_at_screen_position(position)` accepts coordinates in the model's owning
viewport, such as `get_viewport().get_mouse_position()`. It inverts the model's
global canvas transform before calling the local look API, including camera and
canvas transforms. These are not desktop pixels. Nonfinite inputs or a singular
transform return `ERR_INVALID_PARAMETER` and preserve the prior look target.
