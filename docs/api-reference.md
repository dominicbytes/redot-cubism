# Current API reference

The XML files linked here are the current public class descriptions for this port.
This index covers every `doc_classes/*.xml` file present in the checkout: 33 classes
at the tested baseline, with the preferred API first and the legacy compatibility
surface separated below. The XML signatures and property metadata are authoritative.

## Preferred and supporting API

| Class | Inherits | Role |
|---|---|---|
| [`CubismModel2D`](../doc_classes/CubismModel2D.xml) | `Node2D` | Preferred model node with independent runtime, motion, effects, hit testing and rendering. |
| [`CubismModelResource`](../doc_classes/CubismModelResource.xml) | `Resource` | Serializable imported model data shared by independent model nodes. |
| [`CubismModelImporter`](../doc_classes/CubismModelImporter.xml) | `EditorImportPlugin` | Editor-only explicit model import and option validation. |
| [`CubismModelFactory`](../doc_classes/CubismModelFactory.xml) | `RefCounted` | Validated source-to-resource data factory. |
| [`CubismCharacterController`](../doc_classes/CubismCharacterController.xml) | `Node` | Motion, expression, recorded-voice, lip-sync and checkpoint coordination. |
| [`CubismMotionHandle`](../doc_classes/CubismMotionHandle.xml) | `RefCounted` | Retained status and deferred events for one native motion. |
| [`CubismSpeechHandle`](../doc_classes/CubismSpeechHandle.xml) | `RefCounted` | Retained terminal result for one character cue. |
| [`CubismMotionPriority`](../doc_classes/CubismMotionPriority.xml) | `RefCounted` | Native motion priority constants. |
| [`CubismEffect`](../doc_classes/CubismEffect.xml) | `Node` | Preferred custom parameter-effect base. |
| [`CubismLipSync`](../doc_classes/CubismLipSync.xml) | `Node` | Audio-envelope or manual-value lip-sync component. |
| [`CubismLipSyncProfile`](../doc_classes/CubismLipSyncProfile.xml) | `Resource` | Shared envelope and mouth-form settings. |
| [`CubismDependencyTracker`](../doc_classes/CubismDependencyTracker.xml) | `Node` | Imported dependency refresh and status tracking. |
| [`CubismManifestParser`](../doc_classes/CubismManifestParser.xml) | `RefCounted` | Bounded manifest and descriptor parsing. |
| [`CubismExportValidator`](../doc_classes/CubismExportValidator.xml) | `RefCounted` | Resource/file export validation. |
| [`CubismBuildInfo`](../doc_classes/CubismBuildInfo.xml) | `RefCounted` | Loaded build, SDK and sanitizer identity information. |
| [`CubismExpressionDescriptor`](../doc_classes/CubismExpressionDescriptor.xml) | `Resource` | Imported expression metadata and parameters. |
| [`CubismExpressionParameter`](../doc_classes/CubismExpressionParameter.xml) | `Resource` | One imported expression parameter operation. |
| [`CubismMotionDescriptor`](../doc_classes/CubismMotionDescriptor.xml) | `Resource` | Imported motion metadata, audio and event information. |
| [`CubismMotionEvent`](../doc_classes/CubismMotionEvent.xml) | `Resource` | One imported motion event value and timestamp. |

### Common contracts

`CubismModel2D.load_model(resource)` returns a Redot `Error` and accepts a
`CubismModelResource`. `play_motion(motion_id, priority, loop, speed)` returns a
`CubismMotionHandle`; check `is_finished()` before awaiting its `finished` signal.
The exact declarations are in `doc_classes/CubismModel2D.xml` (the `play_motion`
declaration starts at XML line 23) and `doc_classes/CubismMotionHandle.xml`.

`CubismModelImporter.import_model(source_file, destination, strict_optional_files)`
and `import_model_with_options(source_file, destination, options)` are editor-only
and return `Error`. `CubismModelFactory.build(source_path, strict_optional_files)`
and `build_with_options(source_path, options)` return dictionaries rather than
saving resources. See `doc_classes/CubismModelImporter.xml` (method declarations
start at XML line 8) and `doc_classes/CubismModelFactory.xml` (XML line 8).

`CubismCharacterController.speak(stream, motion_id, expression_id, profile)` and
`perform(motion_id, expression_id)` return `CubismSpeechHandle`. A profile is
optional; recorded audio is explicit. See `doc_classes/CubismCharacterController.xml`
(XML line 13) and `doc_classes/CubismSpeechHandle.xml`.

Use the [model workflow](usage/cubism-model-2d.md),
[motions and expressions](usage/motions-and-expressions.md),
[lip-sync guide](usage/lip-sync.md), and [dialogue integration](dialogue-integration.md)
for task-oriented examples.

## Legacy compatibility API

These classes remain for existing GDCubism scenes and scripts. New scenes should
prefer the classes above; migration and resource-bridge behavior are described in
[Migrating from GDCubism](migration/from-gd-cubism.md).

| Class | Inherits | Role |
|---|---|---|
| [`GDCubismUserModel`](../doc_classes/GDCubismUserModel.xml) | `Node2D` | Existing legacy model node and resource bridge. |
| [`GDCubismEffect`](../doc_classes/GDCubismEffect.xml) | `Node` | Legacy effect base. |
| [`GDCubismEffectBreath`](../doc_classes/GDCubismEffectBreath.xml) | `GDCubismEffect` | Legacy breath effect. |
| [`GDCubismEffectCustom`](../doc_classes/GDCubismEffectCustom.xml) | `GDCubismEffect` | Legacy callback-based custom effect. |
| [`GDCubismEffectEyeBlink`](../doc_classes/GDCubismEffectEyeBlink.xml) | `GDCubismEffect` | Legacy eye-blink effect. |
| [`GDCubismEffectHitArea`](../doc_classes/GDCubismEffectHitArea.xml) | `GDCubismEffect` | Legacy hit-area effect. |
| [`GDCubismEffectTargetPoint`](../doc_classes/GDCubismEffectTargetPoint.xml) | `GDCubismEffect` | Legacy target-point effect. |
| [`GDCubismMotionEntry`](../doc_classes/GDCubismMotionEntry.xml) | `Resource` | Legacy motion descriptor resource. |
| [`GDCubismMotionLoader`](../doc_classes/GDCubismMotionLoader.xml) | `ResourceFormatLoader` | Legacy motion resource loader. |
| [`GDCubismMotionQueueEntryHandle`](../doc_classes/GDCubismMotionQueueEntryHandle.xml) | `Resource` | Legacy motion queue handle. |
| [`GDCubismParameter`](../doc_classes/GDCubismParameter.xml) | `GDCubismValueAbs` | Legacy parameter value resource. |
| [`GDCubismPartOpacity`](../doc_classes/GDCubismPartOpacity.xml) | `GDCubismValueAbs` | Legacy part-opacity value resource. |
| [`GDCubismValueAbs`](../doc_classes/GDCubismValueAbs.xml) | `Resource` | Legacy value base. |
| [`GDCubismPlugin`](../doc_classes/GDCubismPlugin.xml) | `EditorPlugin` | Legacy editor plugin class. |

The preserved upstream AsciiDoc pages are not a second current API. They are
explicitly marked as historical in [the archive note](../docs-src/README.md) and
in the [documentation index](README.md); their old Godot/C# examples should not be
used to infer Redot 26.2 signatures.
