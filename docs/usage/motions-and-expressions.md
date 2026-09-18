# Motions and expressions

Author and export Live2D motions in Cubism Editor, then import the model and its
declared motion/expression files. This addon plays existing animation; it does
not record a new Live2D motion inside the game.

Motion IDs use `Group/index`, preserving manifest order. Expression IDs use their
declared names. Read them from the [Model Inspector](../model-inspector.md) or
resource descriptors instead of assuming every model has `Idle/0` or `Smile`.
`CubismModel2D.play_motion(id, priority, loop, speed)` returns a
`CubismMotionHandle`; `play_motion_from_group` selects the group and index
explicitly. A rejected request may already be terminal, so check `is_finished()`
before awaiting `finished`. Retain the handle to distinguish a previous cue's
completion from the current one.

`set_expression(id, fade_seconds)` returns a Redot `Error`. Its default negative
fade value uses the source fades. `clear_expression()` fades back to the current
primary-motion pose. Expressions, loop state and handles are independently owned
by each character. Pause and speed apply to evaluation and fades.

Direct motion playback does not start audio. Use a
`CubismCharacterController` cue when voice and motion should start together and
completion should wait for both, or use its `perform()` method without voice.
See [dialogue integration](../dialogue-integration.md), the
[motion-handle reference](../../doc_classes/CubismMotionHandle.xml) and
[native SDK comparison scope](../sdk-motion-testing.md).
