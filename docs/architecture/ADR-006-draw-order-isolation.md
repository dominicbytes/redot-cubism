# ADR-006: Keep drawable order within the model

Status: Implemented; broader renderer qualification remains open.

## Problem

Assigning Cubism render orders to drawable `z_index` values makes those values
canvas-wide offsets. Three Haru instances at model layers 0, 1 and 2 produced
drawable depth ranges 0–83, 1–84 and 2–85, allowing their parts to interleave.

## Decision

Keep generated drawable meshes at relative `z_index = 0`. Sort their sibling
positions by Cubism render order after updates, preserving drawable-index order
for ties. The model's own layer controls the character's canvas depth. Mask
SubViewports retain their separate composition.

This uses Redot's ordinary CanvasItem sibling ordering without requiring a
per-character render target. It does not change the model transform or blend
shaders. Generated meshes are renderer-owned; user content should not depend on
their child indices.

## Regression coverage and limits

Visible-window tests check three model layers, root-layer reordering and
single-model output in native and exported games. Headless updates cannot
qualify this behavior because the legacy renderer skips updates in an invisible
window.

Core-derived order tests cover Haru's left/right arm changes and restoration to
defaults. A normal-blend image oracle compares four two/three-character layer
orders against composited individual captures. CanvasGroup/SubViewport fallback
comparisons and destination-dependent blend composition require separate checks.
Per-frame sorting is retained until correctness and visual parity are qualified;
dynamic-flag optimization must preserve the same ordering contract.
