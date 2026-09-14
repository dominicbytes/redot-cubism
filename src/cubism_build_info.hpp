// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Redot Cubism contributors
#ifndef CUBISM_BUILD_INFO_HPP
#define CUBISM_BUILD_INFO_HPP

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

class CubismBuildInfo : public godot::RefCounted {
	GDCLASS(CubismBuildInfo, godot::RefCounted);

protected:
	static void _bind_methods();

public:
	static godot::Dictionary get_versions();
	static godot::Dictionary get_debug_statistics();
};

#endif
