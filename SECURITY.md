# Security

Treat model manifests and referenced paths as untrusted. Do not load arbitrary
downloaded models in a privileged editor session. The importer rejects
project escapes and script-bearing asset references before resource loading.
These controls are implemented and exercised by importer checks. That coverage
does not replace a dedicated security review or full release qualification.

For a suspected vulnerability, use GitHub private vulnerability reporting when
enabled, or contact the repository owner privately before disclosing a working
exploit. Do not attach proprietary SDKs, models, credentials, or private paths to
public issues. Include the source revision, platform and smallest synthetic repro.
