# Licensing and distribution

The derived source is published in
[dominicbytes/redot-cubism](https://github.com/dominicbytes/redot-cubism). Preserve
the upstream MIT notices. Live2D's Framework, proprietary Core, models,
screenshots, and application publication have separate terms. Do not infer a
binary-publication exemption from the source license.

Acquire the Native SDK manually from Live2D under the applicable terms, and set
`CUBISM_SDK_ROOT`. Keep models under an external `CUBISM_TEST_MODEL_ROOT` or the
ignored `.private-fixtures` directory. Record fixture origin/permission privately.

Public jobs run without Core or model fixtures. A full addon library can contain
statically linked Core code even without a separate Core library. Binary release
requires review of the applicable terms and the exact package contents. Public
Windows/Linux external-Core previews exclude Core and SDK/model assets; their
availability does not establish rights for a different package or application.
See [current status](current-status.md) for distribution and qualification limits.

Run `python tools/check_restricted_files.py` before committing and
`python tools/check_restricted_files.py --history HEAD` before pushing.
Archive checks use `python tools/check_release_archive.py ARCHIVE`.
An explicitly approved native artifact requires an exact path/SHA-256 approval
file supplied to the scanner. Approval files are evidence of a recorded decision,
not a mechanism that grants rights. Never allow private models in public packages.
