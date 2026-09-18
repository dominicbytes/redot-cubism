# ADR-001: external native addon

Accepted 2026-09-07. Retain GDCubism's C++ GDExtension integration and migrate its
binding to pinned redot-cpp. Preserve the existing classes and installation paths
through the mechanical port. No minimal reproduction currently requires an engine
change. A new importer/controller follows only after native load/model gates pass.
