@tool
extends EditorPlugin

func _enable_plugin() -> void:
	pass

func _disable_plugin() -> void:
	pass

func _enter_tree() -> void:
	add_custom_type("LightManager", "Node2D", preload("uid://bd8rsvqxnmtr6"), null)
	add_custom_type("CellLight", "Node2D", preload("uid://cd8oaa1ldfvoc"), null)
	add_custom_type("OcclusionBaker", "Node", preload("uid://d3vvh6uegtth7"), null)

func _exit_tree() -> void:
	remove_custom_type("LightManager")
	remove_custom_type("CellLight")
	remove_custom_type("OcclusionBaker")
