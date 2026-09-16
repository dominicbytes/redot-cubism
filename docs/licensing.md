# Licensing and distribution

The user authorized publishing this derived source to dominicbytes/redot-cubism.
Preserve the upstream MIT notices. Live2D's Framework, proprietary Core, models,
screenshots, and application publication have separate terms. Do not infer a
binary-publication exemption from the source license.

Acquire the Native SDK manually from Live2D under the applicable terms, and set
`CUBISM_SDK_ROOT`. Keep models under an external `CUBISM_TEST_MODEL_ROOT` or the
ignored `.private-fixtures` directory. Record fixture origin/permission privately.

Public jobs run without Core or model fixtures. A full addon library can contain
statically linked Core code even without a separate Core library. Binary release
requires the publication review in Section 4 of the canonical plan. This task's
source-fork authorization does not establish that review.

Run `python tools/check_restricted_files.py` before committing and
`python tools/check_restricted_files.py --history HEAD` before pushing.
Archive checks use `python tools/check_release_archive.py ARCHIVE`.
An explicitly approved native artifact requires an exact path/SHA-256 approval
file supplied to the scanner. Approval files are evidence of a recorded decision,
not a mechanism that grants rights. Never allow private models in public packages.
