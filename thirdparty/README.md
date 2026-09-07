# Local dependencies

The mechanical port keeps the binding path `godot-cpp` to reduce migration noise;
its URL and commit will be replaced with the pinned Redot binding during PR 2A.
The `godot_cpp` includes and `godot` namespace remain intentional.

Provision Cubism Native SDK 5-r.5 manually outside source. Set `CUBISM_SDK_ROOT`
and, if needed, `CUBISM_FRAMEWORK_ROOT`. Framework must match the pinned public
commit. No SDK auto-download or implicit custom-Framework override is permitted.
No Core headers/libraries, SDK archive, or real model belongs in Git.
