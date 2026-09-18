# Upstream GDCubism documentation archive

This directory preserves the original GDCubism 0.9 documentation and examples.
For the Redot 26.2 port, start with the [current guides](../docs/README.md).

The archived build commands, SDK versions and platform claims describe upstream
Godot support. In particular, the shader snippets under `modules/ROOT/examples`
use the old `auto_scale`/`canvas_size` mask interface. Do not install those snippets
into the Redot addon. Its maintained runtime shaders are under
`demo/addons/gd_cubism/res/shader`; they include the current mask mapping, alpha
handling and mask-edge fixes. Legacy API compatibility does not make historical
shader uniforms interchangeable with the current implementation.

The [Antora playbook](../docs-site/antora-playbook.yml) fetches upstream branches
0.6–0.9 and the upstream UI; it does not build the port's Markdown guides or
publish the port. Generated archive output belongs in `.local-build/upstream-docs`,
separate from the maintained `docs` directory. Original notices remain preserved.

The output path is relative to the playbook, following [Antora's output-directory rules](https://docs.antora.org/antora/3.1/playbook/output-dir/).
