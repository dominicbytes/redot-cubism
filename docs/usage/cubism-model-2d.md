# Using CubismModel2D

Add a `CubismModel2D` node and assign an imported `CubismModelResource` to its
`model` property. Each node owns its runtime state; characters may share the
imported resource without sharing active motion/effect state. Generated meshes,
materials and renderer children are internal and are not saved as scene content.

The default rendering mode is Direct. Start with GL Compatibility, the renderer
exercised on the Linux test host. Keep model scale/position on the node and use
the mask settings documented in the [preferred runtime guide](../preferred-runtime.md).
The explicit SubViewport fallback has size and composition limits; it is not
required for normal model display.

For scripted loading, call `load_model(resource)` and check its Redot `Error`.
Lifecycle notifications are deferred; use `queue_free()` when deleting a model
from a callback. `unload_model()` releases native state while retaining the
selection for `reload_model()`. Assigning a null model clears the selection.

Use `playback_process_mode` to select idle, physics or manual evaluation. Manual
`advance(delta)` respects pause and speed; it is not arbitrary-time seeking.
Native internal updates continue when a GDScript overrides `_process`.
Parameter writes are queued for evaluation; choose their layer deliberately when
combining them with motion, expressions or physics.

See the [class reference](../../doc_classes/CubismModel2D.xml) and
[detailed runtime contracts](../preferred-runtime.md) for properties, clock rules,
parameter layers, rendering policies and ownership behavior.
