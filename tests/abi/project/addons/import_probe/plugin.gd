# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
@tool
extends EditorPlugin

var importer: EditorImportPlugin
var generic_importer: EditorImportPlugin
var exporter: EditorExportPlugin

func _enter_tree() -> void:
	importer = preload("res://addons/import_probe/importer.gd").new()
	add_import_plugin(importer, true)
	generic_importer = preload("res://addons/import_probe/generic_importer.gd").new()
	add_import_plugin(generic_importer)
	exporter = preload("res://addons/import_probe/exporter.gd").new()
	add_export_plugin(exporter)

func _exit_tree() -> void:
	remove_import_plugin(importer)
	remove_import_plugin(generic_importer)
	remove_export_plugin(exporter)
	importer = null
	generic_importer = null
	exporter = null
