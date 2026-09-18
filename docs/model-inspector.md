# Model Inspector

Selecting a `CubismModelResource` shows its source path, texture count, motion
count and groups, expression count, canvas size and hit-area count above the
ordinary resource properties. The summary displays imported metadata; it does
not certify current source files, rendering parity or export readiness.

Import warnings appear as plain text. The compact summary shows up to eight
warnings, each limited to 512 characters; the complete stored list remains in
the Import Warnings property below. An empty resource explains how to import
model data through Project → Tools → Import Cubism Model.

The summary updates on the resource's `changed` signal, including property
replacement after reimport. Inspector switching disconnects the previous summary
from the resource. The import menu opens the cached resource so dependency reimport
replacement updates the same object shown in the Inspector. Viewing metadata
writes no model or source files and creates
no rendering instance. Existing property editors remain available.

The extension descriptor registers a small mesh icon for `CubismModelResource`
and `GDCubismUserModel`. The SVG is original addon artwork, distributed with the
source under MIT. It is not a Live2D logo. The Inspector plugin and summary class
are registered as internal classes only in editor processes, keeping them out of
game-node creation menus. A shared native library may still
contain their compiled code.

Inspector-assisted preview, parameter editing, dedicated reimport controls and
preferred-node creation conveniences remain separate planned work. The
`CubismModel2D` runtime itself is available now; add the node and assign a
`CubismModelResource` as described in [Using CubismModel2D](usage/cubism-model-2d.md).
