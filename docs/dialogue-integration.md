# Dialogue integration

`CubismCharacterController` owns a character cue and coordinates native motion,
expression, voice playback and lip sync. A dialogue manager supplies text and
per-line choices. The controller has no dependency on a particular framework.
The runnable [VN and RPG examples](../demo/addons/gd_cubism/examples/character_workflows/README.md)
show both recorded voice and motion-only dialogue.

Set `target_model` to an already loaded `CubismModel2D`. Choose a valid
`idle_motion` and enable `auto_return_to_idle` for normal cue completion. For
one line, select an imported motion ID, expression ID and optional audio:

```gdscript
func play_line(voice: AudioStream, motion: StringName, expression: StringName) -> CubismSpeechHandle:
    if voice != null:
        return $Controller.speak(voice, motion, expression, CubismLipSyncProfile.new())
    return $Controller.perform(motion, expression)

func run_line(voice: AudioStream, motion: StringName, expression: StringName) -> void:
    var cue := play_line(voice, motion, expression)
    # A rejected or empty cue may already be terminal.
    if not cue.is_finished():
        await cue.finished
    if cue.get_reason() == CubismSpeechHandle.COMPLETED:
        # Notify your dialogue manager that the audiovisual cue has ended.
        pass
```

Show the text through your own UI when calling `play_line`. If advancing also
requires a player click or text-reveal completion, track that condition in the
dialogue manager alongside cue completion. Do not treat an interrupted, hidden,
unloaded or failed cue as successful delivery. Check `get_error()` for failures.
For event-driven UI, retain the current handle and ignore callbacks belonging
to older handles, as the VN example does when restoring a checkpoint.

Use `stop_speaking()` to cancel when skipping a line or leaving a conversation.
A new cue interrupts the controller's prior cue predictably. Hiding, unloading
or removing the character also terminates its pending cue. Motion and audio
may have different durations; the cue waits for both. A paused controller
freezes its voice and model clock. Scene-tree pause follows the controller's
normal Node process mode; do not set it to Always unless that is intentional.
General audio/motion seeking is unsupported.

The controller creates internal voice/lip-sync children. Do not add another lip
component to the same target. Assign `voice_bus` to a dedicated existing bus per
simultaneous speaker to prevent another voice, music or sound effect driving
its mouth. Lip sync measures that bus's output envelope; it is not phoneme
recognition. A `CubismLipSyncProfile` adjusts envelope response. Authored mouth
curves take priority by default. Keep one active controller per target model.

For saves, store your dialogue manager's line/branch state alongside a successful
`capture_state().state` result. Capture is allowed at a stable boundary, including
owned idle. After loading the matching imported model, call `restore_state()`
and check its Error before advancing your dialogue UI. It validates primitive
JSON fields and the model's import fingerprint before changing state. Stable
state includes presentation, expression, look and idle choices; a restored idle
starts a fresh loop. It excludes in-flight voice position, motion phase and
physics history. Never serialize native pointers or feed arbitrary save paths
directly to a resource loader.

See [preferred runtime](preferred-runtime.md) for the detailed clock, ownership,
completion and checkpoint contracts, and [checked exports](export-validation.md)
for packaging models and their dependencies. A selected-resource export must
include the configured scene/preset or otherwise explicitly retain dynamically
selected models and audio.
