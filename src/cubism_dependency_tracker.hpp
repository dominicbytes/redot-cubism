// SPDX-License-Identifier: MIT
#ifndef CUBISM_DEPENDENCY_TRACKER_HPP
#define CUBISM_DEPENDENCY_TRACKER_HPP
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <map>
#include <set>
#include <vector>

using namespace godot;
namespace godot { class EditorFileSystemDirectory; }

class CubismDependencyTracker : public Node {
    GDCLASS(CubismDependencyTracker, Node);
    struct Entry {
        String source, destination, expected, last_attempt;
        Dictionary options, fingerprints;
        String status = "pending";
        int attempts = 0;
        bool force = false;
        bool persisted = false;
        bool output_missing = false;
        bool seen = false;
    };
    std::map<String, Entry> entries;
    std::map<String, std::set<String>> reverse_index;
    std::vector<String> pending;
    size_t cursor = 0;
    String active;
    PackedStringArray paths;
    int path_cursor = 0;
    Dictionary observed;
    Ref<FileAccess> file;
    Ref<HashingContext> hasher;
    uint64_t file_size = 0;
    uint64_t total_bytes = 0;
    double elapsed = 0;
    bool requested = true;
    bool importing = false;
    bool running = false;
    bool processing = false;
    void collect(EditorFileSystemDirectory *directory);
    void begin_cycle();
    void begin_entry();
    void hash_step();
    void finish_entry();
    void before_import(const PackedStringArray &resources);
    void after_import(const PackedStringArray &resources);
    void sources_changed(bool changed);
protected:
    static void _bind_methods();
    void _notification(int what);
public:
    void _enter_tree() override;
    void _exit_tree() override;
    void _process(double delta) override;
    void request_scan();
    void track(const String &source, const String &destination, const Dictionary &options = Dictionary());
    Dictionary get_status() const;
};
#endif
