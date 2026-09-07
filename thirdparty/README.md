# Local dependencies

The mechanical port keeps the binding path `godot-cpp` to reduce migration noise;
its URL and commit now select the pinned Redot binding for PR 2B.
The `godot_cpp` includes and `godot` namespace remain intentional.

Provision Cubism Native SDK 5-r.5 from the authorized official download outside source. Set `CUBISM_SDK_ROOT`
and, if needed, `CUBISM_FRAMEWORK_ROOT`. Framework must match the pinned public
commit. Build scripts never download the SDK or select an implicit custom Framework.
No Core headers/libraries, SDK archive, or real model belongs in Git.
