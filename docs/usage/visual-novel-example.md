# Visual-novel example

After [installing and importing a model](../quick-start.md), open
`res://addons/gd_cubism/examples/character_workflows/visual_novel.tscn`.
Select the root, expand **Character**, and assign the imported resource to
**Model**. Choose valid **Idle Motion**, **Talk Motion** and **Talk Expression**
IDs. Optionally assign **Voice**; leaving it empty demonstrates an unvoiced cue.
Run the scene with F6. Public scenes contain no licensed models or recordings and
show a setup message until configured.

**Next line** plays a one-shot cue. **Pause** freezes voice and model, **Hide**
cancels the cue, and **Show** restores the character. Normal completion returns
to idle. The sample reuses one voice clip; a game should select its own audio per
dialogue line using [the controller integration](../dialogue-integration.md).

Save at a stable cue/fade boundary. Restore validates the model fingerprint and
stable controller state, and can interrupt a newer cue. It restarts idle rather
than seeking recorded audio or restoring motion phase and physics history.

The [example README](../../demo/addons/gd_cubism/examples/character_workflows/README.md)
describes setup, viewport behavior and checkpoints. Keep the scene's Interface
script dependency and character resource references when making a selective
[checked export](exporting.md).
