# CubismModel2D implementation status

`CubismModel2D` is the preferred native `Node2D` API under development. It owns
one internal `GDCubismUserModel`, retaining the existing allocation, resource
loading and renderer implementation. The internal child has no scene owner and
is not serialized. The public `model` resource supplies normal export dependency
edges. Legacy scenes and methods remain available during migration.

The implemented foundation includes resource assignment, load/unload/reload,
state and error queries, typed lifecycle signals, idle/physics/manual processing,
speed and pause controls, physics/pose switches, parameter/part IDs, parameter
writes, part-opacity writes and canvas information. It does **not yet complete**
the planned motion/handle API, autoplay/default cues, deterministic effects,
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
