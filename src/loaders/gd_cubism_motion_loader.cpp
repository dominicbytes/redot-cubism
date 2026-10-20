// SPDX-License-Identifier: MIT
#include <loaders/gd_cubism_motion_loader.hpp>

#include <cubism_manifest_parser.hpp>
#include <cubism_descriptors.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <cmath>

Variant GDCubismMotionLoader::_load(const String& p_path, const String& p_original_path, bool p_use_sub_threads, int32_t p_cache_mode) const {
    const Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::READ);
    if (file.is_null()) return Error::ERR_FILE_CANT_OPEN;
    const uint64_t length = file->get_length();
    if (length == 0 || length > 4ULL * 1024 * 1024) return Error::ERR_FILE_CORRUPT;
    const PackedByteArray bytes = file->get_buffer(length);
    if (uint64_t(bytes.size()) != length || file->get_length() != length) return Error::ERR_FILE_CORRUPT;
    String buffer;
    if (buffer.parse_utf8(reinterpret_cast<const char *>(bytes.ptr()), bytes.size()) != OK) return Error::ERR_PARSE_ERROR;
    // Source identity is not used by Animation conversion; allow virtual and
    // external paths while sharing the production schema/segment validation.
    const Dictionary validation = CubismManifestParser::parse_motion(buffer, "Animation", 0, "res://animation.motion3.json");
    if (!bool(validation.get("ok", false))) return Error::ERR_PARSE_ERROR;
    const Ref<CubismMotionDescriptor> descriptor = validation["motion"];
    Dictionary motion = descriptor->get_metadata();
    Dictionary meta = motion["Meta"];

    Ref<Animation> anim;
    anim.instantiate();

    bool loop = meta.get("Loop", false);
    anim->set_loop_mode(
        loop
        ? Animation::LOOP_LINEAR
        : Animation::LOOP_NONE);
    const double fps = meta["Fps"];
    const double step = 1.0 / fps;
    if (!std::isfinite(step) || !std::isfinite(real_t(step)) || real_t(step) <= 0) return Error::ERR_PARSE_ERROR;
    anim->set_step(step);

    // parse motion curves
    Array curves = motion["Curves"];
    for (uint32_t c_idx = 0; c_idx < curves.size(); c_idx++) {
        Dictionary curve = curves[c_idx];

        // TODO only support parameter type curves for now
        if (curve["Target"] != "Parameter") {
            continue;
        }

        String property = curve["Id"];
        Array segments = curve["Segments"];

        int32_t track = anim->add_track(Animation::TYPE_BEZIER);
        anim->track_set_path(track, NodePath(".:" + property));
        anim->track_set_interpolation_loop_wrap(track, true);

        // first key is always the starting time and value
        anim->bezier_track_insert_key(track, segments[0], segments[1]);

        // parsing techniques adapted from Unity Importer
        // https://github.com/Live2D/CubismUnityComponents/blob/08815c83738ecdd8fe689f4222280540ff8ea9c8/Assets/Live2D/Cubism/Framework/Json/CubismMotion3Json.cs#L401
        for (uint32_t s_idx = 2, last_key = anim->track_get_key_count(track) - 1; s_idx < segments.size();) {

            int32_t type = segments[s_idx];
            real_t p0_t = segments[s_idx - 2];
            real_t p0_v = segments[s_idx - 1];

            if (type == 0) {
                // LINEAR
                real_t p1_t = segments[s_idx + 1];
                real_t p1_v = segments[s_idx + 2];

                // tangents
                Vector2 out_t = Vector2(p1_t - p0_t, p1_v - p0_v) / 3.0f;
                Vector2 in_t = -out_t;

                anim->bezier_track_set_key_out_handle(track, last_key, out_t);

                last_key = anim->bezier_track_insert_key(
                    track,
                    p1_t, p1_v,
                    in_t,
                    Vector2(0, 0));

                s_idx += 3;
            }
            else if (type == 1) {
                // CUBIC BEZIER
                real_t p1_t = segments[s_idx + 1];
                real_t p1_v = segments[s_idx + 2];
                real_t p2_t = segments[s_idx + 3];
                real_t p2_v = segments[s_idx + 4];
                real_t p3_t = segments[s_idx + 5];
                real_t p3_v = segments[s_idx + 6];

                const bool restricted = meta.get("AreBeziersRestricted", false);
                // Animation clamps handle X to the endpoint's side. Unrestricted
                // SDK root selection outside this interval can be discontinuous,
                // which continuous sampled keys cannot preserve within tolerance.
                ERR_FAIL_COND_V_MSG(!restricted && (p1_t < p0_t || p1_t > p3_t || p2_t < p0_t || p2_t > p3_t),
                    Error::ERR_PARSE_ERROR,
                    "Cannot convert unrestricted Bezier for parameter '" + property + "' at segment offset " + String::num_int64(s_idx) +
                    ": control times outside the segment interval cannot be preserved by Animation. Use native Cubism motion playback.");
                Vector2 out_t = Vector2(restricted ? (p3_t - p0_t) / 3.0f : p1_t - p0_t, p1_v - p0_v);
                Vector2 in_t = Vector2(restricted ? (p0_t - p3_t) / 3.0f : p2_t - p3_t, p2_v - p3_v);

                anim->bezier_track_set_key_out_handle(track, last_key, out_t);

                last_key = anim->bezier_track_insert_key(
                    track, p3_t, p3_v,
                    in_t,
                    Vector2(0, 0));

                s_idx += 7;
            }
            else if (type == 2) {
                // Stepped
                real_t p1_t = segments[s_idx + 1];
                real_t p1_v = segments[s_idx + 2];

                last_key = anim->bezier_track_insert_key(
                    track, p1_t, p1_v,
                    Vector2(0, INFINITY));
                s_idx += 3;
            }
            else if (type == 3) {
                // Inverse Stepped
                real_t p1_t = segments[s_idx + 1];
                real_t p1_v = segments[s_idx + 2];

                Vector2 out_t = Vector2(p1_t - p0_t, p1_v - p0_v);

                anim->bezier_track_set_key_out_handle(track, last_key, out_t);

                anim->bezier_track_insert_key(
                    track, p0_t + 0.01f, p1_v,
                    out_t,
                    Vector2(0, 0));

                last_key = anim->bezier_track_insert_key(
                    track, p1_t, p1_v,
                    Vector2(0, 0),
                    Vector2(0, 0));

                s_idx += 3;
            }
        }
    }

    double duration = meta.get("Duration", 1.0);
    anim->set_length(duration);
    anim->set_path(p_path);

    return anim;
}