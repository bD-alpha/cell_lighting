class_name LightManager
extends Node2D

const LIGHT_MESH_MATERIAL = preload("uid://d17vy75toqc1")

@export var cell_size: int = 8
@export var mesh_size: int = 24
@export var smooth: bool = false:
	set(value):
		smooth = value
		for mesh_instance in mesh_instances:
			RenderingServer.canvas_item_set_default_texture_filter(mesh_instances[mesh_instance], RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR if smooth else RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
@export_enum("Diamond:0", "Octagon:1") var light_pattern: int = 0:
	set(value):
		light_pattern = value
		_full_update_required = true
@export_group("Mode", "mode_")
@export_enum("Normal:0", "Dither:1") var mode: int = 0 

var light_matrix: PackedVector3Array = []
var occlusion_matrix: PackedFloat32Array = []

var _dimensions: Rect2i

var light_images: Dictionary[Vector2i, Image] = {}
var light_textures: Dictionary[Vector2i, ImageTexture] = {}
var mesh_instances: Dictionary[Vector2i, RID] = {}
var mesh: QuadMesh

var _meshes_dirty_old: Array[Vector2i] = []
var _full_update_required: bool = false

func _ready() -> void:
	z_index = 1

func initialize(dimensions: Rect2i) -> void:
	light_matrix.resize(dimensions.size.x * dimensions.size.y)
	occlusion_matrix.resize(dimensions.size.x * dimensions.size.y)
	_dimensions = dimensions
	
	mesh = QuadMesh.new()
	mesh.orientation = PlaneMesh.FACE_Z
	mesh.size = Vector2(cell_size * mesh_size, cell_size * mesh_size)
	
	var mesh_shader = RenderingServer.shader_create()
	RenderingServer.shader_set_code(mesh_shader, """
		shader_type canvas_item;
		render_mode blend_%s;
		uniform sampler2D bayer: repeat_enable, filter_nearest;
		void vertex() {
			// Called for every vertex the material is visible on.
		}
		void fragment() {
			float bayer_sample = texture(bayer, UV / TEXTURE_PIXEL_SIZE / 2.0).r;
			vec3 color = texture(TEXTURE, UV).rgb;
			//if(bayer_sample > length(color) ) COLOR.rgb = vec3(0.0);
			//COLOR.rgb = vec3(bayer_sample);
			COLOR.rgb = texture(TEXTURE, UV).rgb;
			COLOR.a = 1.0;
		}
		""" % ["mul"]
	)
	
	var mesh_material = RenderingServer.material_create()
	RenderingServer.material_set_shader(mesh_material, mesh_shader)
	
	for mesh_y in int((dimensions.size.y - 1) /  mesh_size) + 1:
		for mesh_x in int((dimensions.size.x - 1) / mesh_size) + 1:
			var mesh_position: Vector2i = Vector2i(mesh_x, mesh_y)
			
			var image = Image.create_empty(mesh_size, mesh_size, false, Image.FORMAT_RGB8)
			light_images[mesh_position] = image
			
			var texture = ImageTexture.create_from_image(image)
			light_textures[mesh_position] = texture
			
			
			var mesh_instance = RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(mesh_instance, get_canvas_item())
			RenderingServer.canvas_item_set_material(mesh_instance, mesh_material)
			RenderingServer.canvas_item_add_mesh(mesh_instance, mesh.get_rid(), Transform2D.IDENTITY, Color.WHITE, texture.get_rid())
			RenderingServer.canvas_item_set_transform(mesh_instance, Transform2D().translated(((Vector2(mesh_position) + Vector2.ONE * 0.5) * mesh_size + Vector2(_dimensions.position)) * cell_size))
			RenderingServer.canvas_item_set_default_texture_filter(mesh_instance, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR if smooth else RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
			mesh_instances[mesh_position] = mesh_instance
		

	for node in get_tree().get_nodes_in_group(&"_occlusion_source"):
		var occlusion_baker: OcclusionBaker = node as OcclusionBaker
		var occlusion_area: Rect2i = occlusion_baker.get_baking_area()
		for y in occlusion_area.size.y:
			for x in occlusion_area.size.x:
				var local: Vector2i = Vector2i(x, y)
				var global: Vector2i = (occlusion_baker.get_parent().global_position / cell_size).floor()
				var full: Vector2i = local + global - _dimensions.position
				if not _dimensions.has_point(full): continue
				
				occlusion_matrix[full.x + full.y * _dimensions.size.x] = occlusion_baker.occlusion_matrix[local.x + local.y * occlusion_area.size.x]

func get_light(point: Vector2i) -> Vector3:
	point = point.clamp(_dimensions.position, _dimensions.end - Vector2i.ONE)
	point += _dimensions.position
	return light_matrix[point.x + point.y * _dimensions.size.x]

func _get_light_local(point: Vector2i) -> Vector3:
	point = point.clamp(Vector2i.ZERO, _dimensions.size - Vector2i.ONE)
	return light_matrix[point.x + point.y * _dimensions.size.x]

func _get_occlusion_local(point: Vector2i) -> float:
	point = point.clamp(Vector2i.ZERO, _dimensions.size - Vector2i.ONE)
	return occlusion_matrix[point.x + point.y * _dimensions.size.x]

func _update_light_mesh(mesh_position: Vector2i) -> void:
	var i = 0
	for y in mesh_size: 
		for x in mesh_size:
			var global: Vector2i = Vector2i(x + mesh_position.x * mesh_size, y + mesh_position.y * mesh_size)
			if not _dimensions.has_point(global + _dimensions.position): continue
			var light: Vector3 = light_matrix[global.x + global.y * _dimensions.size.x]
			light_images[mesh_position].set_pixel(x, mesh_size - 1 - y, Color(light.x, light.y, light.z))
			
	light_textures[mesh_position].update(light_images[mesh_position])

func update():
	var meshes_dirty: Array[Vector2i] = []
	var dirs: Dictionary[Vector2i, float] = {
		Vector2i.UP: 1, 
		Vector2i.LEFT: 1, 
		Vector2i.DOWN: 1, 
		Vector2i.RIGHT: 1
	}
	
	if light_pattern == 1: 
		dirs = dirs.merged(
			{
				Vector2i(-1, -1): 1.414213,
				Vector2i( 1, -1): 1.414213,
				Vector2i(-1,  1): 1.414213,
				Vector2i( 1,  1): 1.414213
			}
		)
	
	light_matrix.fill(Vector3.ZERO)
	
	var world_size = get_viewport_rect().size / get_viewport().get_camera_2d().zoom
	var top_left = get_viewport().get_camera_2d().get_screen_center_position() - world_size * 0.5
	var view_rect = Rect2(top_left, world_size)
	
	
	for node in get_tree().get_nodes_in_group(&"_cell_lights"):
		var time = Time.get_ticks_usec()
		var light: CellLight = node as CellLight
		if _full_update_required: light.dirty = true
		if not view_rect.grow(cell_size * light.intensity).has_point(light.global_position): continue
		
		var light_color: Vector3 = Vector3(light.color.r, light.color.g, light.color.b)
		var light_source_pos: Vector2 = light.global_position / cell_size - Vector2.ONE * 0.5
		var light_grid_pos: Vector2i = Vector2i(light_source_pos.floor()).clamp(_dimensions.position, _dimensions.end - Vector2i.ONE) - _dimensions.position
		
		if light.dirty:
			light.light_matrix.clear()
			light.dirty = false
			
			var light_queue: Array[Vector2i] = []
			
			light.light_matrix[light_grid_pos] = light.intensity
			light_matrix[light_grid_pos.x + light_grid_pos.y * _dimensions.size.x] += light_color
			light_queue.append(light_grid_pos)
			
			while light_queue.size() > 0:
				var light_position: Vector2i = light_queue.pop_front()
				var light_intensity: float = light.light_matrix[light_position]
				
				for dir in dirs:
					var neighbor_position = light_position + dir
					if not _dimensions.has_point(neighbor_position + _dimensions.position): continue
					
					var occlusion = _get_occlusion_local(neighbor_position)
					var propagated_intensity = (light_intensity  / (1 + occlusion) - dirs[dir])
					
					if propagated_intensity <= 0: continue
					
					if neighbor_position not in light.light_matrix: 
						light_matrix[neighbor_position.x + neighbor_position.y * _dimensions.size.x] += light_color * propagated_intensity / light.intensity
					
					elif light.light_matrix[neighbor_position] * 1.75 < propagated_intensity:
						light_matrix[neighbor_position.x + neighbor_position.y * _dimensions.size.x] += light_color * (propagated_intensity - light.light_matrix[neighbor_position]) / light.intensity
						
					else: continue
						
					var mesh_coord = (neighbor_position) / mesh_size
					if mesh_coord not in meshes_dirty:
						meshes_dirty.append(mesh_coord)
					light.light_matrix[neighbor_position] = propagated_intensity
					light_queue.append(neighbor_position)
		else:
			for cell in light.light_matrix:
				if (cell / mesh_size) not in meshes_dirty + _meshes_dirty_old: continue
				light_matrix[cell.x + cell.y * _dimensions.size.x] += light_color * light.light_matrix[cell] / light.intensity
		
	for mesh_pos in _meshes_dirty_old:
		if mesh_pos in meshes_dirty: continue
		_update_light_mesh(mesh_pos)
		
	for mesh_pos in meshes_dirty:
		_update_light_mesh(mesh_pos)
		
	_meshes_dirty_old.clear()
	_meshes_dirty_old.append_array(meshes_dirty)
	
	if _full_update_required: _full_update_required = false
