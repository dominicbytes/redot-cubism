# Cubism SDK compatibility

| SDK | Compile | Runtime | Notes |
|---|---|---|---|
| 5-r.5 | Pending SDK acquisition | Pending | Required P0 baseline; source adaptations prepared |
| Older SDK | Unsupported | Unsupported | No automatic compatibility or mixed Core/Framework versions |
| Newer SDK | Untested | Untested | Requires a separately verified upgrade |

The selected Framework commit is
`145155d2c5bdd8d23475cef9cc3ab46d3220190c`. Source review confirms that motions
use `SetLoop` and `SetLoopFadeIn`, and the expression manager inherits
`StartMotion(motion, autoDelete)` without a priority argument. The regular motion
manager retains its existing priority API.

The new blend query returns a `csmBlendMode` object. The existing Redot shaders
map `csmColorBlendType_Normal` with `csmAlphaBlendType_Over`,
`csmColorBlendType_AddCompatible`, and `csmColorBlendType_MultiplyCompatible` to
the old normal/additive/multiplicative behavior, including masked and inverted
mask variants. Other blend pairs and models requiring offscreen compositing are
rejected before creating the renderer. This follows the legacy shader selection
in the pinned Framework's `CubismShader_OpenGLES2::GetShaderNamesBegin`.

These are source-level adaptations, not graphics or model-runtime qualification.
The existing drawable texture, culling and multiply/screen-color queries still
exist in the pinned headers and have not been renamed speculatively. The lifetime,
color-override and rendering requirements remain subject to the native tests.
