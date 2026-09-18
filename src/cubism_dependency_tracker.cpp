// SPDX-License-Identifier: MIT
#include "cubism_dependency_tracker.hpp"
#include "cubism_manifest_parser.hpp"
#include "cubism_model_importer.hpp"
#include "cubism_model_resource.hpp"
#include "cubism_import_options.hpp"
#include <godot_cpp/classes/editor_interface.hpp>
#include <godot_cpp/classes/editor_file_system.hpp>
#include <godot_cpp/classes/editor_file_system_directory.hpp>
#include <godot_cpp/classes/config_file.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

void CubismDependencyTracker::_bind_methods() {
    ClassDB::bind_method(D_METHOD("request_scan"), &CubismDependencyTracker::request_scan);
    ClassDB::bind_method(D_METHOD("get_status"), &CubismDependencyTracker::get_status);
}

void CubismDependencyTracker::_enter_tree() {
    auto *fs = EditorInterface::get_singleton()->get_resource_filesystem();
    fs->connect("filesystem_changed", callable_mp(this, &CubismDependencyTracker::request_scan));
    fs->connect("sources_changed", callable_mp(this, &CubismDependencyTracker::sources_changed));
    fs->connect("resources_reimporting", callable_mp(this, &CubismDependencyTracker::before_import));
    fs->connect("resources_reimported", callable_mp(this, &CubismDependencyTracker::after_import));
    set_process(true);
}
void CubismDependencyTracker::_exit_tree() {
    set_process(false);
    auto *fs = EditorInterface::get_singleton()->get_resource_filesystem();
    fs->disconnect("filesystem_changed", callable_mp(this, &CubismDependencyTracker::request_scan));
    fs->disconnect("sources_changed", callable_mp(this, &CubismDependencyTracker::sources_changed));
    fs->disconnect("resources_reimporting", callable_mp(this, &CubismDependencyTracker::before_import));
    fs->disconnect("resources_reimported", callable_mp(this, &CubismDependencyTracker::after_import));
    file.unref();
    hasher.unref();
}
void CubismDependencyTracker::request_scan() { requested = true; }
void CubismDependencyTracker::sources_changed(bool) { request_scan(); }
void CubismDependencyTracker::_notification(int what) {
    if (what == NOTIFICATION_APPLICATION_FOCUS_IN) request_scan();
}
void CubismDependencyTracker::before_import(const PackedStringArray &) { importing = true; }
void CubismDependencyTracker::after_import(const PackedStringArray &resources) {
    importing = false;
    for (int i = 0; i < resources.size(); ++i) {
        const auto found = reverse_index.find(resources[i]);
        if (found != reverse_index.end() && !resources[i].ends_with(".model3.json")) {
            for (const String &path : found->second) {
                const auto entry = entries.find(path);
                if (entry != entries.end()) entry->second.force = true;
            }
        }
    }
    requested = true;
}
void CubismDependencyTracker::track(const String &source, const String &destination, const Dictionary &options) {
    Entry &entry = entries[destination];
    entry.source = source;
    entry.destination = destination;
    entry.options = options.duplicate();
    requested = true;
}
void CubismDependencyTracker::collect(EditorFileSystemDirectory *directory) {
    if (!directory) return;
    for (int i = 0; i < directory->get_subdir_count(); ++i) collect(directory->get_subdir(i));
    for (int i = 0; i < directory->get_file_count(); ++i) {
        const String destination = directory->get_file_path(i);
        const bool automatic = destination.ends_with(".model3.json");
        if (!automatic && directory->get_file_type(i) != StringName("CubismModelResource")) continue;
        if (CubismManifestParser::validate_project_file(destination)["status"] != String("file")) continue;
        Dictionary automatic_options;
        if (automatic) {
            // Loading an unimported manifest here can cause ResourceLoader to
            // create an engine import as a side effect. Only track engine-owned
            // metadata that already selects this importer, and recover missing
            // generated output through the engine before attempting a load.
            const String sidecar = destination + String(".import");
            if (CubismManifestParser::validate_project_file(sidecar)["status"] != String("file")) continue;
            const Ref<FileAccess> metadata = FileAccess::open(sidecar, FileAccess::READ);
            if (metadata.is_null() || metadata->get_length() > 4 * 1024 * 1024) continue;
            Ref<ConfigFile> config;
            config.instantiate();
            if (config->parse(metadata->get_as_text(), false) != OK || config->get_value("remap", "importer", "") != String("redot.cubism.model")) continue;
            automatic_options = cubism_import_defaults();
            if (config->has_section("params")) {
                const PackedStringArray keys = config->get_section_keys("params");
                for (int j = 0; j < keys.size(); ++j) automatic_options[keys[j]] = config->get_value("params", keys[j]);
            }
            const String generated = config->get_value("remap", "path", "");
            if (!directory->get_file_import_is_valid(i) || generated.is_empty() ||
                    CubismManifestParser::validate_project_file(generated)["status"] != String("file")) {
                Entry &entry = entries[destination];
                entry.source = destination;
                entry.destination = destination;
                entry.options = automatic_options;
                entry.persisted = true;
                entry.seen = true;
                if (!entry.output_missing) {
                    entry.expected = String();
                    if (entry.status == "reimport-requested") entry.status = "failed";
                    else entry.last_attempt = String();
                    entry.output_missing = true;
                }
                continue;
            }
        }
        const Ref<CubismModelResource> resource = ResourceLoader::get_singleton()->load(destination, "CubismModelResource", ResourceLoader::CACHE_MODE_IGNORE);
        if (resource.is_null() || resource->get_import_fingerprint().is_empty()) continue;
        Entry &entry = entries[destination];
        entry.destination = destination;
        entry.source = resource->get_source_model_path();
        entry.expected = resource->get_import_fingerprint();
        entry.persisted = true;
        entry.seen = true;
        entry.output_missing = false;
        const Dictionary options = automatic ? automatic_options : resource->get_import_options().duplicate();
        const Dictionary hashes = resource->get_dependency_fingerprints().duplicate();
        entry.options = options;
        entry.fingerprints = hashes;
    }
}
void CubismDependencyTracker::begin_cycle() {
    requested = false;
    elapsed = 0;
    for (auto &pair : entries) pair.second.seen = false;
    collect(EditorInterface::get_singleton()->get_resource_filesystem()->get_filesystem());
    pending.clear();
    reverse_index.clear();
    for (auto item = entries.begin(); item != entries.end();) {
        if (item->second.persisted && !item->second.seen) item = entries.erase(item);
        else ++item;
    }
    for (const auto &pair : entries) {
        pending.push_back(pair.first);
        reverse_index[pair.second.source].insert(pair.first);
        const Array keys = pair.second.fingerprints.keys();
        for (int i = 0; i < keys.size(); ++i) reverse_index[String(keys[i])].insert(pair.first);
    }
    cursor = 0;
    running = !pending.empty();
}
void CubismDependencyTracker::begin_entry() {
    active = pending[cursor];
    Entry &entry = entries[active];
    Dictionary known;
    const Array previous = entry.fingerprints.keys();
    for (int i = 0; i < previous.size(); ++i) known[previous[i]] = true;
    known[entry.source] = true;
    // Parsing the current source retains newly declared missing files after failure.
    const Dictionary text = CubismManifestParser::read_project_json(entry.source);
    if (text["status"] == String("file")) {
        const Dictionary checked = validate_cubism_import_options(entry.options);
        const Dictionary parsed = parse_cubism_import_manifest(text["text"], entry.source, checked["options"]);
        if (bool(parsed["ok"])) {
            const PackedStringArray dependencies = parsed["dependencies"];
            for (int i = 0; i < dependencies.size(); ++i) {
                const String path = dependencies[i];
                known[path] = true;
                if (path.ends_with(".png") || path.ends_with(".wav") || path.ends_with(".ogg")) known[path + String(".import")] = true;
            }
        }
    }
    paths.clear();
    const Array keys = known.keys();
    for (int i = 0; i < keys.size(); ++i) {
        const String path = keys[i];
        paths.push_back(path);
        reverse_index[path].insert(active);
    }
    paths.sort();
    observed.clear();
    total_bytes = 0;
    path_cursor = 0;
}
void CubismDependencyTracker::hash_step() {
    const String path = paths[path_cursor];
    if (file.is_null()) {
        const Dictionary state = CubismManifestParser::validate_project_file(path);
        if (state["status"] != String("file")) {
            observed[path] = state["status"];
            ++path_cursor;
            return;
        }
        file = FileAccess::open(path, FileAccess::READ);
        if (file.is_null()) { observed[path] = "error"; ++path_cursor; return; }
        file_size = file->get_length();
        if (file_size > 64ULL * 1024 * 1024 || total_bytes + file_size > 512ULL * 1024 * 1024) {
            observed[path] = "oversized";
            file.unref();
            ++path_cursor;
            return;
        }
        total_bytes += file_size;
        hasher.instantiate();
        hasher->start(HashingContext::HASH_SHA256);
    }
    const uint64_t remaining = file_size - file->get_position();
    const uint64_t count = remaining < 1024 * 1024 ? remaining : 1024 * 1024;
    const PackedByteArray bytes = file->get_buffer(count);
    if (uint64_t(bytes.size()) != count || file->get_length() != file_size) {
        observed[path] = "changed-during-read";
        file.unref();
        hasher.unref();
        ++path_cursor;
        return;
    }
    if (!bytes.is_empty()) hasher->update(bytes);
    if (file->get_position() == file_size) {
        observed[path] = hasher->finish().hex_encode();
        file.unref();
        hasher.unref();
        ++path_cursor;
    }
}
void CubismDependencyTracker::finish_entry() {
    Entry &entry = entries[active];
    const String current = CubismModelImporter::fingerprint(observed, entry.options);
    if (entry.force || (current != entry.expected && current != entry.last_attempt)) {
        entry.force = false;
        entry.last_attempt = current;
        ++entry.attempts;
        auto *fs = EditorInterface::get_singleton()->get_resource_filesystem();
        // Raw content can change without an engine filesystem notification.
        // Refresh engine-owned texture/audio imports before saving their resource
        // references; changing only the model's fingerprint would hide stale data.
        PackedStringArray imported_dependencies;
        for (int i = 0; i < paths.size(); ++i) {
            const String &path = paths[i];
            if (!path.ends_with(".png") && !path.ends_with(".wav") && !path.ends_with(".ogg")) continue;
            const String hash = observed.get(path, "");
            if (hash.length() != 64) continue;
            const String sidecar = path + String(".import");
            if (observed.get(path, "") != entry.fingerprints.get(path, "") ||
                    observed.get(sidecar, "") != entry.fingerprints.get(sidecar, "")) {
                imported_dependencies.push_back(path);
            }
        }
        if (!imported_dependencies.is_empty()) fs->reimport_files(imported_dependencies);
        // The reimport signal above has been handled for this entry. Other models
        // sharing those resources retain their own pending invalidation.
        entry.force = false;
        if (entry.destination.ends_with(".model3.json")) {
            PackedStringArray sources;
            sources.push_back(entry.source);
            fs->reimport_files(sources);
            entry.status = "reimport-requested";
        } else {
            const Error error = CubismModelImporter::import_model_with_options(entry.source, entry.destination, entry.options);
            entry.status = error == OK ? "current" : "failed";
            if (error == OK) fs->update_file(entry.destination);
        }
    } else if (current == entry.expected) {
        entry.status = "current";
    }
    active = String();
    ++cursor;
    if (cursor == pending.size()) {
        running = false;
        elapsed = 0;
    }
}
void CubismDependencyTracker::_process(double delta) {
    auto *fs = EditorInterface::get_singleton()->get_resource_filesystem();
    if (processing || importing || fs->is_scanning()) return;
    // EditorProgress can pump another frame before the engine emits its import
    // signals. Keep nested frames from advancing this queue a second time.
    processing = true;
    elapsed += delta;
    if (!running) {
        if (requested || elapsed >= 2.0) begin_cycle();
    } else {
        if (active.is_empty()) begin_entry();
        if (path_cursor < paths.size()) hash_step();
        else finish_entry();
    }
    processing = false;
}
Dictionary CubismDependencyTracker::get_status() const {
    Dictionary result;
    result["busy"] = running || requested || importing || processing;
    Array models;
    for (const auto &pair : entries) {
        Dictionary item;
        item["resource"] = pair.first;
        item["source"] = pair.second.source;
        item["status"] = pair.second.status;
        item["attempts"] = pair.second.attempts;
        models.push_back(item);
    }
    result["models"] = models;
    return result;
}
