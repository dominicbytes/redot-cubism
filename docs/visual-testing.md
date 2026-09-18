# SDK visual comparisons

`tools/run_visual_tests.py` captures imported models at independently recorded
SDK states. It compares the stored RGB channels and alpha separately, preserves
diff images, and rejects mismatched resources, textures, states, dimensions,
graphics hardware, runtime errors and incomplete captures. It supports multiple
models in explicit drawing order and affine transforms. It does not evaluate
the reference motion or effects through the addon: use the numeric motion suite
and native behavior suites for those contracts.

Use the pinned Redot editor and a native Linux/Windows x86_64 graphics session.
Install `tools/requirements-visual.txt` into the runner's project-local Python
environment. Prepare a private Redot project with imported model resources.
SDK files, models, reference images, copied projects and reports remain private.
No licensed assets or reference captures are supplied by this repository.

## Reference fixtures

Capture the pinned official SDK output independently, recording all parameter
and part values, the complete model-view-projection matrix, source manifest/MOC/
texture hashes, texture encoding and executable identity. Use a transparent
background and save the framebuffer RGB plus its actual alpha as an RGBA PNG;
do not synthesize opaque alpha from an RGB-only screenshot. Include the model
layout in the recorded MVP. Use the same texture encoding and explicit mask
quality for the SDK and candidate. The candidate's mask buffers are adaptive,
so an equal maximum size does not imply identical mask sampling.

Source atlas samplers explicitly repeat in both UV directions, matching the
pinned SDK's `CubismShader_OpenGLES2::SetupTexture`, and use trilinear mipmap
filtering. Clamping changes atlas-edge samples, especially when a model is
strongly minified. The shader choice is independent of the surrounding canvas's
repeat setting and does not change the texture import data. Generated mask
buffers keep their separate bounds and sampling contract.

Transform fixtures should include unequal axis scales, a negative determinant,
strong minification, and enlargement that clips visible geometry at the viewport
edge. Apply these transforms after model layout, keeping the native animation
state fixed. When extending the SDK capture hook, retain neutral and existing
transform captures as unchanged controls. Compare both texture encodings and
debug/release builds; matching candidate images establish build consistency,
not agreement with the SDK or an approved visual tolerance.

For multi-model order fixtures, reverse only the drawing order. Verify each
model's recorded state and transform remain identical, and verify the SDK
images actually differ in the overlap. For blend and mask coverage, record
visible drawable flags and nonzero opacity at the captured state. A model
containing hidden additive meshes does not establish additive image coverage.

The private fixture JSON has this shape. Hash placeholders must be replaced
with actual SHA-256 values; image paths are relative to the fixture JSON:

```json
{
  "reference": {
    "framework_sha256": "<pinned Framework source hash>",
    "core_sha256": "<reference Core library hash>",
    "executable_sha256": "<SDK reference executable hash>",
    "description": "Capture procedure, fixed steps and graphics configuration"
  },
  "cases": [{
    "id": "neutral",
    "size": [512, 512],
    "image": "reference/neutral.png",
    "image_sha256": "<RGBA reference image hash>",
    "models": [{
      "resource": "res://Character.res",
      "manifest_sha256": "<model3.json hash>",
      "moc_sha256": "<MOC hash>",
      "texture_sha256": ["<first source PNG hash>"],
      "premultiplied_alpha": false,
      "mask_quality": 2,
      "mvp": [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
      "parameters": {"ParamAngleX": 0},
      "parts": {"PartBody": 1}
    }]
  }]
}
```

Include **every** model parameter and part, not just the ones shown above.
Source texture hashes follow manifest texture order. Models are drawn in array
order, each at opacity one; reference states with other model opacity require a
separate capture contract. `mask_quality` is 0/1/2 for low/medium/high. Perspective
and 3D matrices are rejected. Parameters and parts must match within `1e-5`.
The reference procedure and hashes provide provenance; the runner does not
certify that arbitrary supplied images actually came from the SDK.

```sh
REDOT_BIN=/private/redot python tools/run_visual_tests.py \
  --project /private/prepared-project --library /private/addon-library.so \
  --fixtures /private/visual-fixtures.json --output /private/visual-measurements \
  --measure-only
```

The output status is `MEASURED`, never a visual pass. RGB RMS uses the union of
nontransparent reference/candidate pixels; alpha RMS uses that same union.
Maximum channel differences and pixel counts above 3/255 are also reported.
RGB under pixels transparent on both sides is ignored. Empty output on both
sides fails. The runner copies the prepared project, installs the selected
library and current repository shaders, and records their hashes. It does not
hand-edit engine-owned import metadata. Output must be outside that project.

## Explicit acceptance limits

Review SDK reference images and error regions on the intended runner before
selecting limits. Store a private limits JSON with `fixtures_sha256`, a nonempty
`review` record, `platform` (`Linux` or `Windows`), exact `renderer` and `adapter`
strings, and a `cases` object keyed by every reference case ID. Each entry must
specify finite `rgb_rms`, `alpha_rms`, `rgb_max` and `alpha_max` limits in 0–255
units. No limits are chosen or relaxed automatically. The exact fixture hash
ties the review to image, state and asset identities.

Replace `--measure-only` with `--limits /private/visual-limits.json` to enforce
that policy, or use the aggregate command:

```sh
REDOT_BIN=/private/redot python tools/run_tests.py --suite visual \
  --visual-project /private/prepared-project --library /private/addon-library.so \
  --visual-fixtures /private/visual-fixtures.json \
  --visual-limits /private/visual-limits.json --output /private/visual-results
```

The aggregate command requires limits. Windows uses native DLL/EXE paths and a
Windows-generated reference/limits set; Linux uses X11. `--graphics forward_plus`
selects that backend explicitly and needs its own reviewed policy. A passing
report applies only to its listed cases, hardware, library and shaders. It
always leaves `release_qualified` false: full release qualification also needs
the complete planned fixture matrix, other desktop suites and remaining gates.

The standalone command above continues to accept one project, fixture manifest
and limits file. The private desktop workflow instead requires
`CUBISM_VISUAL_MATRIX`, a versioned JSON index with `project`, `fixtures` and
`limits` paths for exactly eight required family/encoding IDs: transforms,
effects, pair ordering and visible additive coverage, each in straight and
premultiplied texture form. The licensed aggregate validates the manifests'
exact case sets, per-case model counts and actual `premultiplied_alpha` values,
then runs all eight entries with both debug and release libraries. It rejects
duplicate fixture or limits content, so relabeling one passing family cannot
satisfy another. Each result must also match its preflighted fixture hash,
complete reviewed limits object and exact case-ID set; duplicate, truncated,
relabelled or mid-run changed coverage fails. Provision platform-specific native
references and reviewed limits separately on each Windows/Linux runner. Forward+
remains a separate renderer gate with its own reviewed policies.
