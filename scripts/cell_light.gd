class_name CellLight
extends Node2D

func _ready() -> void:
	add_to_group(&"_cell_lights", true)

@export_color_no_alpha var color: Color = Color.WHITE
@export var intensity: float = 1.0

var dirty: bool = true
var light_matrix: Dictionary[Vector2i, float] = {}
