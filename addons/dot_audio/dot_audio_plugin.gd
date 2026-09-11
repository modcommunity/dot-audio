@tool
extends EditorPlugin

## Editor entry point for dot-audio. Registers inspector types only.
##
## No autoloads: a listen server and its client in one process are two managers with two
## listeners and two mixers, and a global would make them one.

const _ICON := "res://addons/dot_audio/icon_placeholder.svg"

const _TYPES := [
	[
		"DotAudioManager",
		"Node",
		"res://addons/dot_audio/runtime/dot_audio_manager.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
