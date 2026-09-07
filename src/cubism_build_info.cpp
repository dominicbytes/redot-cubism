// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Redot Cubism contributors
#include "cubism_build_info.hpp"
#include "cubism_build_info.gen.h"

#include <CubismFramework.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void CubismBuildInfo::_bind_methods() {
	ClassDB::bind_static_method("CubismBuildInfo", D_METHOD("get_versions"), &CubismBuildInfo::get_versions);
}

Dictionary CubismBuildInfo::get_versions() {
	Dictionary versions = JSON::parse_string(CUBISM_BUILD_INFO_JSON);
	versions["runtime_redot"] = Engine::get_singleton()->get_version_info();
	versions["runtime_core_packed"] = (int64_t)Live2D::Cubism::Core::csmGetVersion();
	versions["latest_moc_version"] = (int64_t)Live2D::Cubism::Core::csmGetLatestMocVersion();
	return versions;
}
