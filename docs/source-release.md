# Preparing a source release

The manual **Prepare audited source release** workflow accepts a full reviewed
40-character source commit. Use only sanitized history: local development
history containing the private workbook must never be pushed. The workflow
checks out that exact commit, runs the public Python tests and restricted-file
checks, and invokes `tools/package_addon.py --source-only`. Packaging audits all
reachable history, verifies every archived file against Git, and records the
dependency revisions and file hashes. A final archive scan runs before upload.

The uploaded artifact contains only `source.tar.gz` and its manifest. SDK, Core,
models, compiled addon libraries, private reports, and local work history are not
inputs to this job. Its token has read-only repository permissions and it neither
creates a GitHub release nor publishes binaries.

Run this workflow after the candidate is reviewed and available in the source
repository. It remains a source-packaging result: its manifest deliberately
records `release_qualified: false`. Windows/Linux qualification, licensed CI,
dedicated performance acceptance, required status checks, final documentation,
and applicable publication decisions must be resolved before calling the port
complete. See [licensing](licensing.md) and the canonical plan.

For the same local gate, use a new output path outside the checkout:

```sh
python tools/package_addon.py --source-only --ref FULL_REVIEWED_COMMIT_SHA --output /private/output/source.tar.gz
python tools/check_release_archive.py /private/output/source.tar.gz
```

Source publication to `dominicbytes/redot-cubism` is authorized by the user once
the required checks pass. No binary, SDK/model, screenshot, or private-evidence
publication is included in this source-only workflow.
