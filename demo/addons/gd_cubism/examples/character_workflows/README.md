# Character workflows

Two GDScript examples for the preferred `CubismModel2D` and
`CubismCharacterController` API on Redot 26.2:

- `visual_novel.tscn`: a conversation with optional recorded voice, motion,
  expression, pointer look, pause, show/hide, and a dialogue checkpoint.
- `rpg_dialogue.tscn`: WASD/arrow movement, facing, idle, nearby interaction with
  E/Enter, a reaction with R, and two independently animated characters.

The public scenes contain no licensed model or voice assets. They open with a
setup message until a model is assigned.
The shared UI script is attached to each scene's `Interface` CanvasLayer so it
is also an explicit dependency in a selected-resource export. Redot 26.2 does
not enumerate GDScript `preload()` dependencies during export discovery.

## Setup

1. Build/install the native addon as described in the repository README and
   dependencies guide. Its editor commands register when the extension loads.
2. Import your licensed `.model3.json` using **Project → Tools → Import Cubism
   Model**. Stock Redot 26.2 does not automatically discover this compound
   extension on a fresh scan.
3. Open either scene. Select its root, expand **Character**, and assign the
   imported `CubismModelResource` to **Model**.
4. Assign **Idle Motion**, **Talk Motion**, **Walk Motion**, **Reaction Motion**
   and **Talk Expression** using IDs in the model inspector. Motion IDs have the
   form `Group/index`; expression IDs use their source names. Blank motion
   fields use the first available motion, so assign distinct IDs to demonstrate
   your character's distinct actions. A model with no motions can still use
   voice and expression; an unvoiced empty cue finishes immediately.
5. Optionally assign an `AudioStream` to **Voice**. The sample reuses this clip
   on each line; a game normally selects a different clip per line. Leave it
   empty to demonstrate motion without audio. Run the scene with F6.

Use a model containing blink groups, physics, pose, expressions and lip-sync
parameters to see all effects. The preset enables those systems; it cannot
invent data absent from the model. Authored mouth motion has priority over the
audio envelope by default. Both scenes use native per-character effect state,
even when the RPG actors share a preset and imported resource.

## Conversation and checkpoints

**Next line** starts a one-shot cue. **Pause** freezes the controller and its
voice. **Hide** cancels the cue and fades the character; **Show** restores it.
Normal completion returns to the chosen idle. Save after a cue/fade finishes;
Restore can interrupt a newer cue. The JSON file in the project's user-data
directory contains the line index and validated stable controller state.
Restore restarts idle from the beginning; it does not seek a recording, restore
motion phase or reproduce a physics simulation. The model must already be
loaded and match the saved import fingerprint.

The RPG foot circle is a `CircleShape2D` with radius 14. It collides with world
geometry independently of the Live2D mesh, scaling, facing and deformation.
The complete actor's z index follows its feet; moving above/below the companion
or planter changes whole-character order. Characters can overlap to make this
ordering visible. Their `InteractionArea` detects nearby actors separately
from world collision. Only the companion speaks in this scene.

The courtyard is designed for a 1280×720 canvas with `canvas_items` stretch.
The VN refits its character to the viewport after a resize. These are small
examples, not a dialogue framework, save-system framework or asset recorder.
Author Live2D motion files in Cubism Editor and import them; the examples play
existing motions on cue.

See [dialogue integration](../../../../../docs/dialogue-integration.md) for
connecting an arbitrary dialogue manager, selecting per-line audio, handling
terminal cues and assigning separate voice buses for simultaneous speakers.
