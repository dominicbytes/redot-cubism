// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Redot Cubism contributors
#include <godot_cpp/classes/editor_plugin.hpp>
#include <godot_cpp/classes/editor_plugin_registration.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

class CubismAbiResource : public Resource {
	GDCLASS(CubismAbiResource, Resource)

	String source;

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("get_source"), &CubismAbiResource::get_source);
		ClassDB::bind_method(D_METHOD("set_source", "source"), &CubismAbiResource::set_source);
		ADD_PROPERTY(PropertyInfo(Variant::STRING, "source"), "set_source", "get_source");
	}

public:
	String get_source() const { return source; }
	void set_source(const String &p_source) { source = p_source; }
};

class CubismAbiNode : public Node2D {
	GDCLASS(CubismAbiNode, Node2D)

	int64_t ticks = 0;
	int64_t entries = 0;

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("get_ticks"), &CubismAbiNode::get_ticks);
		ClassDB::bind_method(D_METHOD("get_entries"), &CubismAbiNode::get_entries);
	}
	void _notification(int p_what) {
		switch (p_what) {
			case NOTIFICATION_ENTER_TREE:
				entries++;
				set_process_internal(true);
				break;
			case NOTIFICATION_INTERNAL_PROCESS:
				ticks++;
				break;
			case NOTIFICATION_EXIT_TREE:
				set_process_internal(false);
				break;
		}
	}

public:
	int64_t get_ticks() const { return ticks; }
	int64_t get_entries() const { return entries; }
};

class CubismAbiEditorPlugin : public EditorPlugin {
	GDCLASS(CubismAbiEditorPlugin, EditorPlugin)

protected:
	static void _bind_methods() {}
	void _notification(int p_what) {
		if (p_what == NOTIFICATION_ENTER_TREE) {
			UtilityFunctions::print("CUBISM_ABI_EDITOR_ENTER");
		} else if (p_what == NOTIFICATION_EXIT_TREE) {
			UtilityFunctions::print("CUBISM_ABI_EDITOR_EXIT");
		}
	}
};

static void initialize(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_CLASS(CubismAbiResource);
		GDREGISTER_CLASS(CubismAbiNode);
	} else if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		GDREGISTER_CLASS(CubismAbiEditorPlugin);
		EditorPlugins::add_by_type<CubismAbiEditorPlugin>();
	}
}

static void terminate(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		EditorPlugins::remove_by_type<CubismAbiEditorPlugin>();
	}
}

extern "C" GDExtensionBool GDE_EXPORT redot_cubism_abi_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init(p_get_proc_address, p_library, r_initialization);
	init.register_initializer(initialize);
	init.register_terminator(terminate);
	init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}
