# RPG/dialogue example

Open `res://addons/gd_cubism/examples/character_workflows/rpg_dialogue.tscn` after
installing the addon and importing a licensed model. Select the root's
**Character** settings and assign **Model**, motion IDs and an expression. Choose
distinct idle, walk, talk and reaction motions to show those actions. Optional
**Voice** adds recorded audio; missing model features are not synthesized.

Run with F6. Use WASD or arrow keys to move, E/Enter to interact nearby, and R
for a reaction. Only the companion speaks. Two actors can share an imported
resource while retaining independent motion and effect state.

Collision uses a separate foot circle rather than the deforming Live2D mesh.
The actor's z index follows its feet, allowing complete characters to pass in
front of or behind each other and world objects. Nearby interaction is separate
from world collision. This is a small gameplay example, not a complete RPG or
dialogue framework.

See the [example setup and controls](../../demo/addons/gd_cubism/examples/character_workflows/README.md),
[dialogue integration](../dialogue-integration.md) and
[checked exporting](exporting.md). The sample courtyard targets 1280×720 with
canvas-items stretch; test your own camera, collision and display layout.
