@tool
class_name OcclusionBaker
extends Node

@export_tool_button("Bake occlusion") var occlusion_bake_button: Callable = bake_occlusion

@export var custom_baking_area_enable: bool = false
@export var custom_baking_area: Rect2i = Rect2i(Vector2i.ZERO, Vector2i.ONE * 24)

@export var occlusion_matrix: PackedFloat32Array = []

func _ready() -> void:
	add_to_group(&"_occlusion_source")

func get_baking_area() -> Rect2i:
	return custom_baking_area if custom_baking_area_enable else get_parent().get_used_rect()

func bake_occlusion():
	var parent = get_parent()
	if parent is not TileMapLayer: 
		printerr("Ocllusion baking: Failed. OcclusionBaker should be child of TileMapLayer.")
		return
	
	var map: TileMapLayer = parent
	var baking_area: Rect2i = get_baking_area()
	
	occlusion_matrix.resize(baking_area.size.x * baking_area.size.y)
	occlusion_matrix.fill(0)

	for point in map.get_used_cells():
		if not baking_area.has_point(point): continue
		var occlusion: float = map.get_cell_tile_data(point).get_custom_data("Light occlusion")
		occlusion_matrix[point.x + point.y * baking_area.size.x] = occlusion
	
	print("Occlusion baking: Success.")
