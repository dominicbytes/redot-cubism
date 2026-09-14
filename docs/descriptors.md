# Motion and expression resources

These native Resources store imported animation metadata. They do not start
playback, load source files, execute event strings or synchronize audio.

`CubismMotionDescriptor` stores `id` and `group` as StringName, `index` as int,
`source_path` and `sound_path` as String, a real `sound: AudioStream` reference,
`fade_in_seconds`, `fade_out_seconds`, `duration_seconds`, `loop`, an optional
`animation: Animation`, `events: Array[CubismMotionEvent]` and `metadata`.

The importer must assign IDs using `<group>/<manifest-index>` and validate
identity consistency. Setters preserve supplied values; they do not derive IDs
or renumber descriptors. Reordering a manifest changes index-based identities.
The optional Animation field supports serialization only; motion conversion
remains a separate P1 feature and is not enabled by this resource class.

`CubismMotionEvent` stores `time_seconds` and a String `value`. Event values are
data, including Unicode text. Native playback delivers deferred events through
`CubismMotionHandle.event` and `CubismModel2D.motion_event`; see the
[runtime guide](preferred-runtime.md) for timing and completion behavior.

`CubismExpressionDescriptor` stores `id: StringName`, `source_path`, fade-in
and fade-out seconds, and `parameters: Array[CubismExpressionParameter]`.
Each parameter stores `id: StringName`, numeric `value` and `operation`:

- `ADD` (0)
- `MULTIPLY` (1)
- `OVERWRITE` (2)

Fade fields default to -1 to preserve an absent override until source parsing
resolves it. Events start at time zero, parameters default to ADD/value zero,
and optional resources/arrays start empty. All properties have native setters
and getters; setters emit `changed`. Consumers must validate imported values
before invoking Cubism and must not mutate shared descriptor data during play.

`CubismModelResource.motion_groups` can contain ordered arrays of motion
descriptors; `expressions` can contain expression descriptors. Saving that graph
preserves their native types and nested audio resource dependencies. The native
test runner creates a synthetic silent WAV, imports it through Redot and tests
the graph in both source and exported execution. These tests establish data
round trips and dependency retention, not audio playback or motion evaluation.
