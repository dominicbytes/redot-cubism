# Cubism SDK compatibility

| SDK | Compile | Runtime | Notes |
|---|---|---|---|
| 5-r.5 / Core 6.0.1 | Linux x86_64 debug/release pass | Linux model/motion/expression and exported-template smoke pass | Windows and complete rendering gates remain open |
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

The renderer factory now receives canvas width/height; the two R5 render-target
hooks are no-ops because Redot owns canvas submission. `GetRenderOrders()`
replaces `GetDrawableRenderOrders()`; with offscreen objects rejected, the
drawable-indexed order array retains the required meaning.

See [native test evidence](../gamedev/pr-02b-native-report.md) for actual coverage.
The existing drawable texture, culling and multiply/screen-color queries still
exist in the pinned headers and have not been renamed speculatively. The lifetime,
color-override and rendering requirements remain subject to the native tests.
