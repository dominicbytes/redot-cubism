# Lip sync and recorded voice

`CubismCharacterController.speak()` coordinates an `AudioStream`, optional motion
and expression, and a `CubismLipSyncProfile`. Assign its `target_model` to an
already loaded `CubismModel2D`. Use one active controller per target. The
controller creates its own voice/lip-sync children; do not add a second lip
component to the same character.

Lip sync measures an audio bus envelope. It requires neither a microphone nor a
phoneme service. Give simultaneous speakers separate existing `voice_bus` values
so another voice or music does not drive the wrong mouth. The model needs suitable
lip-sync parameters. Authored mouth curves take priority by default, and the
profile controls envelope response; this is not phoneme recognition.

The returned `CubismSpeechHandle` can already be finished when a cue is rejected
or empty. Check its terminal state and reason before treating it as delivered.
Normal completion waits for both motion and voice. Pausing freezes their clocks;
stopping, hiding or unloading interrupts the cue. General voice/motion seeking
is unsupported.

Use `perform()` for a motion/expression cue without recorded audio. The runnable
[VN example](visual-novel-example.md) demonstrates both choices. For per-line
audio selection, cue completion and save boundaries, follow
[dialogue integration](../dialogue-integration.md). Low-level types are documented
in [CubismLipSync](../../doc_classes/CubismLipSync.xml) and
[CubismLipSyncProfile](../../doc_classes/CubismLipSyncProfile.xml).
