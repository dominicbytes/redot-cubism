// SPDX-License-Identifier: MIT
#include "cubism_texture_import.hpp"
#include "cubism_manifest_parser.hpp"
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/portable_compressed_texture2d.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/resource_saver.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <map>
#include <string>

using namespace godot;
namespace {
// Main-thread importer only. Keep hashes, never texture objects or image buffers.
// The bounded cache avoids recompressing unchanged pixels for every dependent model.
std::map<std::string, std::string> generated_hashes;
String digest(const PackedByteArray &bytes) {
    Ref<HashingContext> hash;
    hash.instantiate();
    hash->start(HashingContext::HASH_SHA256);
    if (!bytes.is_empty()) hash->update(bytes);
    return hash->finish().hex_encode();
}
Error texture_error(const String &path, const String &message, Error error) {
    UtilityFunctions::push_error("Cubism texture import failed: ", path, ": ", message);
    return error;
}
}

Error provision_cubism_textures(const Ref<CubismModelResource> &model) {
    TypedArray<Texture2D> textures;
    std::map<String, Ref<Texture2D>> shared;
    const PackedStringArray sources = model->get_texture_paths();
    const Dictionary fingerprints = model->get_dependency_fingerprints();
    for (int i = 0; i < sources.size(); ++i) {
        const String source = sources[i];
        const auto found = shared.find(source);
        if (found != shared.end()) { textures.push_back(found->second); continue; }
        // The factory already checked PNG dimensions and aggregate input limits.
        // Verify these exact bytes still match that validation before decoding.
        if (CubismManifestParser::validate_project_file(source)["status"] != String("file")) {
            return texture_error(source, "Source is no longer a contained file.", ERR_FILE_BAD_PATH);
        }
        const Ref<FileAccess> input = FileAccess::open(source, FileAccess::READ);
        if (input.is_null() || input->get_length() > 64ULL * 1024 * 1024) {
            return texture_error(source, "Cannot read PNG within the 64 MiB input limit.", ERR_FILE_CANT_READ);
        }
        const uint64_t size = input->get_length();
        const PackedByteArray bytes = input->get_buffer(size);
        if (uint64_t(bytes.size()) != size || digest(bytes) != String(fingerprints.get(source, ""))) {
            return texture_error(source, "PNG changed during import; retry the import.", ERR_FILE_CORRUPT);
        }
        auto *settings = ProjectSettings::get_singleton();
        const String encoding = String(fingerprints[source]) + String(":") +
            String::num_int64(bool(settings->get_setting("rendering/textures/lossless_compression/force_png", false))) + String(":") +
            String::num(double(settings->get_setting("rendering/textures/webp_compression/lossless_compression_factor", 25.0)));
        const std::string cache_key(encoding.utf8().get_data());
        const auto cached = generated_hashes.find(cache_key);
        if (cached != generated_hashes.end()) {
            const String hash(cached->second.c_str());
            const String destination = String("res://cubism_generated/textures/") + hash + String(".res");
            const String state = CubismManifestParser::validate_project_file(destination)["status"];
            if (state != "file" && state != "missing") {
                return texture_error(destination, "Generated destination is not a contained file path.", ERR_FILE_BAD_PATH);
            }
            if (state == "file") {
                if (FileAccess::get_sha256(destination) != hash) {
                    return texture_error(destination, "Generated texture has changed. Move it aside and reimport the model.", ERR_FILE_CORRUPT);
                }
                const Ref<Texture2D> imported = ResourceLoader::get_singleton()->load(destination, "PortableCompressedTexture2D");
                if (imported.is_null()) return texture_error(destination, "Cannot load generated texture.", ERR_FILE_CANT_READ);
                textures.push_back(imported);
                shared.emplace(source, imported);
                continue;
            }
        }
        Ref<Image> image;
        image.instantiate();
        if (image->load_png_from_buffer(bytes) != OK || image->generate_mipmaps() != OK) {
            return texture_error(source, "Cannot decode PNG and generate mipmaps.", ERR_FILE_CORRUPT);
        }
        Ref<PortableCompressedTexture2D> texture;
        texture.instantiate();
        // ResourceSaver otherwise generates a random internal ID, making identical
        // texture payloads serialize differently on every import.
        texture->set_scene_unique_id("CubismTexture");
        texture->set_keep_compressed_buffer(true);
        texture->create_from_image(image, PortableCompressedTexture2D::COMPRESSION_MODE_LOSSLESS);
        if (texture->get_width() != image->get_width() || texture->get_height() != image->get_height()) {
            return texture_error(source, "Cannot create lossless texture.", ERR_CANT_CREATE);
        }
        // Serialize only the texture we just created. The unpredictable temporary
        // filename is owned/deleted by FileAccess, including on error paths.
        const Ref<FileAccess> temporary = FileAccess::create_temp(FileAccess::READ_WRITE, "cubism-texture", "res");
        if (temporary.is_null()) return texture_error(source, "Cannot create temporary texture output.", ERR_CANT_CREATE);
        const String temporary_path = temporary->get_path_absolute();
        temporary->close();
        const Error saved = ResourceSaver::get_singleton()->save(texture, temporary_path);
        if (saved != OK) return texture_error(source, "Cannot serialize lossless texture.", saved);
        const PackedByteArray serialized = FileAccess::get_file_as_bytes(temporary_path);
        if (serialized.is_empty()) return texture_error(source, "Serialized texture is empty.", ERR_FILE_CANT_READ);
        const String hash = digest(serialized);
        const String destination = String("res://cubism_generated/textures/") + hash + String(".res");
        const String state = CubismManifestParser::validate_project_file(destination)["status"];
        if (state != "file" && state != "missing") {
            return texture_error(destination, "Generated destination is not a contained file path.", ERR_FILE_BAD_PATH);
        }
        if (state == "file") {
            // Do not deserialize arbitrary/preseeded resource contents or overwrite
            // a different file. Only our freshly serialized bytes are acceptable.
            if (FileAccess::get_sha256(destination) != hash) {
                return texture_error(destination, "Generated texture has changed. Move it aside and reimport the model.", ERR_FILE_CORRUPT);
            }
        } else {
            if (DirAccess::make_dir_recursive_absolute(destination.get_base_dir()) != OK) {
                return texture_error(destination, "Cannot create generated texture directory.", ERR_CANT_CREATE);
            }
            const Ref<FileAccess> output = FileAccess::open(destination, FileAccess::WRITE);
            if (output.is_null()) return texture_error(destination, "Cannot write generated texture.", ERR_FILE_CANT_WRITE);
            output->store_buffer(serialized);
            output->flush();
            if (output->get_error() != OK) return texture_error(destination, "Generated texture write failed.", ERR_FILE_CANT_WRITE);
        }
        const Ref<Texture2D> imported = ResourceLoader::get_singleton()->load(destination, "PortableCompressedTexture2D");
        if (imported.is_null()) return texture_error(destination, "Cannot load generated texture.", ERR_FILE_CANT_READ);
        textures.push_back(imported);
        shared.emplace(source, imported);
        if (generated_hashes.size() >= 128) generated_hashes.erase(generated_hashes.begin());
        generated_hashes[cache_key] = std::string(hash.utf8().get_data());
    }
    model->set_textures(textures);
    return OK;
}
