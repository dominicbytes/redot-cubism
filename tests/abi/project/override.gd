# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
extends CubismAbiNode

var ready_calls: int = 0

func _ready() -> void:
	ready_calls += 1
	set_process(false)

func _process(_delta: float) -> void:
	pass
