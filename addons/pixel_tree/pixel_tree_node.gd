@tool
extends Node2D
class_name PixelTree

enum TreePreset {
	OAK,
	SAKURA,
	PALM,
	OAK_WINTER,
	BIRCH,
}

const GROW_STEP_SIZE := 0.007
const DEFAULT_RANDOM_SEED := 1337
const GENERATION_STEP_LIMIT := 16384

var _canvas_size: Vector2i = Vector2i(128, 128)
var _tree_preset: TreePreset = TreePreset.OAK
var _preview_scale := 4.0
var _seed := DEFAULT_RANDOM_SEED
var _trunk_angle_spread := 0.3
var _generate_now := false

@export var canvas_size: Vector2i = Vector2i(128, 128) :
	set(value):
		_canvas_size = Vector2i(maxi(value.x, 16), maxi(value.y, 16))
		_queue_regenerate()
	get:
		return _canvas_size

@export var tree_preset: TreePreset = TreePreset.OAK :
	set(value):
		_tree_preset = value
		_queue_regenerate()
	get:
		return _tree_preset

@export_range(0.25, 8.0, 0.05) var preview_scale := 4.0 :
	set(value):
		_preview_scale = maxf(value, 0.25)
		queue_redraw()
	get:
		return _preview_scale

@export var auto_regenerate := true
@export var randomize_on_each_regenerate := false
@export var bake_falling_particles := false
@export var seed := DEFAULT_RANDOM_SEED :
	set(value):
		_seed = value
		if not randomize_on_each_regenerate:
			_queue_regenerate()
	get:
		return _seed

@export_range(0.0, 1.0, 0.01) var trunk_angle_spread := 0.3 :
	set(value):
		_trunk_angle_spread = maxf(value, 0.0)
		_queue_regenerate()
	get:
		return _trunk_angle_spread

@export var generate_now := false :
	set(value):
		if value:
			_generate_now = false
			regenerate()
		else:
			_generate_now = false
	get:
		return _generate_now

var _image: Image
var _texture: ImageTexture
var _draw_offset := Vector2.ZERO
var _particles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _working_origin := Vector2.ZERO
var _root_position := Vector2.ZERO
var _used_min := Vector2i.ZERO
var _used_max := Vector2i.ZERO
var _has_used_pixels := false


func _ready() -> void:
	if Engine.is_editor_hint() or auto_regenerate:
		regenerate()


func _notification(what: int) -> void:
	if what == NOTIFICATION_POSTINITIALIZE and (Engine.is_editor_hint() or auto_regenerate):
		regenerate()


func regenerate() -> void:
	if randomize_on_each_regenerate:
		_rng.randomize()
	else:
		_rng.seed = _seed

	var preset := _get_preset_data(_tree_preset)
	var working_padding := _get_working_padding()
	var working_size := _canvas_size + Vector2i.ONE * working_padding * 2
	_working_origin = Vector2(working_padding, working_padding)
	_image = Image.create(working_size.x, working_size.y, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))
	_draw_offset = Vector2.ZERO
	_particles.clear()
	_has_used_pixels = false
	_used_min = Vector2i(working_size.x, working_size.y)
	_used_max = Vector2i.ZERO

	var planters: Array[Dictionary] = []
	var root_angle := _randf_range(-PI * 0.5 - _trunk_angle_spread, -PI * 0.5 + _trunk_angle_spread)
	_root_position = _working_origin + Vector2(_canvas_size.x * 0.5, _canvas_size.y - 1)
	planters.append(_make_planter(_root_position, root_angle, preset))

	var step_count := 0
	while not planters.is_empty() and step_count < GENERATION_STEP_LIMIT:
		step_count += 1
		var next_generation: Array[Dictionary] = []
		for planter in planters:
			_update_planter(planter, preset, next_generation)
		planters = next_generation

	if bake_falling_particles:
		_simulate_particles()
	_finalize_image()
	_texture = ImageTexture.create_from_image(_image)
	queue_redraw()
	notify_property_list_changed()


func get_tree_image() -> Image:
	return _image


func get_tree_texture() -> Texture2D:
	return _texture


func _draw() -> void:
	if _texture:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _preview_scale)
		draw_texture(_texture, _draw_offset)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif Engine.is_editor_hint():
		draw_rect(Rect2(Vector2.ZERO, Vector2(_canvas_size) * _preview_scale), Color(0.12, 0.12, 0.12, 0.4), true)


func _queue_regenerate() -> void:
	if Engine.is_editor_hint() or auto_regenerate:
		call_deferred("regenerate")


func _make_planter(start_pos: Vector2, angle: float, preset: Dictionary) -> Dictionary:
	var lifetime: float = preset["lt"] * _randf_range(0.5, 1.5)
	var min_split: float = preset["mn_sp_t"]
	var max_split := preset.get("mx_sp_t", min_split + 0.1)
	return {
		"position": start_pos,
		"angle": angle,
		"age": 0.0,
		"gen": 1,
		"lt": lifetime,
		"split_time": lifetime * _randf_range(min_split, max_split),
		"thk": preset["thk"],
		"gt": preset["gt_initial"],
		"color": _randomize_color(preset["color_base"], 7.0),
	}


func _update_planter(planter: Dictionary, preset: Dictionary, next_generation: Array[Dictionary]) -> void:
	var angle: float = planter["angle"]
	angle += _randf_range(-preset["warping"], preset["warping"]) * GROW_STEP_SIZE
	angle = _rotate_angle(angle, -PI * 0.5, planter["gt"] * GROW_STEP_SIZE)

	var position: Vector2 = planter["position"]
	position.x += cos(angle) * 100.0 * GROW_STEP_SIZE
	position.y += sin(angle) * 100.0 * GROW_STEP_SIZE

	_draw_block(position, planter["thk"], planter["color"])

	planter["position"] = position
	planter["angle"] = angle
	planter["age"] = planter["age"] + GROW_STEP_SIZE

	if planter["age"] > planter["split_time"]:
		_split_planter(planter, preset, next_generation, 0, int(preset["s_mid_mx"]))
		var min_split: float = preset["mn_sp_t"]
		var max_split := preset.get("mx_sp_t", min_split * 2.0)
		planter["split_time"] = planter["split_time"] + _randf_range(min_split, max_split)

	if planter["age"] > planter["lt"]:
		_split_planter(planter, preset, next_generation, 1, int(preset["s_end_mx"]))
		_draw_pixel(position, planter["color"])
		if planter["gen"] > preset["lf_gen"] and _randf() > 0.8:
			_particles.append(_make_particle(position, angle, planter["color"]))
	else:
		next_generation.append(planter)


func _split_planter(planter: Dictionary, preset: Dictionary, next_generation: Array[Dictionary], min_count: int, max_count: int) -> void:
	var branch_count := _randi_range(min_count, max_count)
	var angle_delta: float = preset["ang_dif"]

	if planter["gen"] >= preset["lf_gen"] + preset.get("lf_steps", 0):
		branch_count = 0
	if branch_count == 1:
		angle_delta = 0.1
	if planter["gen"] == preset["lf_gen"]:
		angle_delta = 3.0
		branch_count = int(preset["lf_amount"])

	for _i in range(branch_count):
		var child_angle := _rotate_angle(
			planter["angle"] + _randf_range(-angle_delta, angle_delta),
			-PI * 0.5,
			0.3
		)
		var child := _make_planter(planter["position"], child_angle, preset)
		var generation_step := _randi_range(1, 1 + int(preset.get("skip_gen_max", 1)))
		child["thk"] = maxi(1, int(planter["thk"]) - 1)
		child["gen"] = planter["gen"] + generation_step
		child["lt"] = float(child["lt"]) / child["gen"]
		child["gt"] = planter["gt"] - generation_step * preset["gt_per_gen"]
		if planter["gen"] >= preset["lf_gen"]:
			child["color"] = _randomize_color(preset["color_leaves"], 20.0)
			child["lt"] = child["lt"] * preset["lf_length"]
			child["thk"] = maxi(1, int(preset["lf_thickness"]) - (child["gen"] - preset["lf_gen"]))
			child["gt"] = preset["lf_gravity"]
		next_generation.append(child)


func _make_particle(position: Vector2, angle: float, color: Color) -> Dictionary:
	return {
		"position": position,
		"velocity": Vector2(cos(angle), sin(angle)) * 85.0,
		"age": 0.0,
		"drag": 2.0,
		"lifetime": 20.0,
		"gravity": 50.0,
		"color": color,
	}


func _simulate_particles() -> void:
	var delta_time := 0.016
	for _step in range(300):
		if _particles.is_empty():
			return
		var survivors: Array[Dictionary] = []
		for particle in _particles:
			var velocity: Vector2 = particle["velocity"]
			velocity *= (1.0 - particle["drag"] * delta_time)
			if particle["position"].y >= _canvas_size.y - 1:
				velocity.y = 0.0
			else:
				velocity.x += _randf_range(-100.0, 100.0) * delta_time
				if particle["position"].y < _canvas_size.y - 20:
					velocity.y += _randf_range(-100.0, 100.0) * delta_time
				velocity.y += particle["gravity"] * delta_time
				velocity.y -= absf(velocity.x) / 150.0
			var position: Vector2 = particle["position"] + velocity * delta_time
			position.x = clampf(position.x, 0.0, _canvas_size.x - 1.0)
			position.y = clampf(position.y, 0.0, _canvas_size.y - 1.0)
			_draw_pixel(position, particle["color"])
			particle["position"] = position
			particle["velocity"] = velocity
			particle["age"] = particle["age"] + delta_time
			if particle["age"] <= particle["lifetime"]:
				survivors.append(particle)
		_particles = survivors


func _draw_block(position: Vector2, size: int, color: Color) -> void:
	var half_size := floori(size / 2.0)
	var origin := Vector2i(int(round(position.x)) - half_size, int(round(position.y)) - half_size)
	for x in range(size):
		for y in range(size):
			_set_pixel(origin + Vector2i(x, y), color)


func _draw_pixel(position: Vector2, color: Color) -> void:
	_set_pixel(Vector2i(int(round(position.x)), int(round(position.y))), color)


func _set_pixel(pixel: Vector2i, color: Color) -> void:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= _image.get_width() or pixel.y >= _image.get_height():
		return
	if not _has_used_pixels:
		_used_min = pixel
		_used_max = pixel
		_has_used_pixels = true
	else:
		_used_min.x = mini(_used_min.x, pixel.x)
		_used_min.y = mini(_used_min.y, pixel.y)
		_used_max.x = maxi(_used_max.x, pixel.x)
		_used_max.y = maxi(_used_max.y, pixel.y)
	_image.set_pixel(pixel.x, pixel.y, color)


func _get_working_padding() -> int:
	return maxi(maxi(_canvas_size.x, _canvas_size.y), 64) * 2


func _finalize_image() -> void:
	if not _has_used_pixels:
		_image = Image.create(_canvas_size.x, _canvas_size.y, false, Image.FORMAT_RGBA8)
		_image.fill(Color(0, 0, 0, 0))
		_draw_offset = Vector2.ZERO
		return

	var crop_origin := _used_min
	var crop_size := (_used_max - _used_min) + Vector2i.ONE
	_image = _image.get_region(Rect2i(crop_origin, crop_size))
	_draw_offset = Vector2(crop_origin) - _root_position


func _get_preset_data(preset: TreePreset) -> Dictionary:
	match preset:
		TreePreset.SAKURA:
			return {
				"name": "Sakura",
				"lt": 0.5,
				"mn_sp_t": 0.8,
				"thk": 6,
				"gt_initial": 3.0,
				"warping": 40.0,
				"lf_gen": 12,
				"gt_per_gen": 1.0,
				"ang_dif": 1.0,
				"lf_amount": 5,
				"lf_length": 0.8,
				"lf_gravity": 0.0,
				"lf_thickness": 4,
				"s_end_mx": 2,
				"s_mid_mx": 2,
				"lf_steps": 1,
				"color_base": Color8(50, 30, 30),
				"color_leaves": Color8(220, 140, 150),
			}
		TreePreset.PALM:
			return {
				"name": "Palm",
				"lt": 1.1,
				"mn_sp_t": 2.0,
				"thk": 3,
				"gt_initial": -0.5,
				"warping": 3.0,
				"lf_gen": 1,
				"gt_per_gen": 0.5,
				"ang_dif": 0.0,
				"lf_amount": 10,
				"lf_length": 0.3,
				"lf_gravity": -7.0,
				"lf_thickness": 4,
				"s_end_mx": 1,
				"s_mid_mx": 1,
				"skip_gen_max": 0,
				"lf_steps": 3,
				"color_base": Color8(60, 30, 25),
				"color_leaves": Color8(80, 130, 30),
			}
		TreePreset.OAK_WINTER:
			return {
				"name": "Oak Winter",
				"lt": 0.7,
				"mn_sp_t": 0.3,
				"thk": 4,
				"gt_initial": 0.3,
				"warping": 20.0,
				"lf_gen": 5,
				"gt_per_gen": 0.1,
				"ang_dif": 1.4,
				"lf_amount": 1,
				"lf_length": 0.5,
				"lf_gravity": 0.0,
				"lf_thickness": 4,
				"s_end_mx": 4,
				"s_mid_mx": 3,
				"skip_gen_max": 1,
				"lf_steps": 2,
				"color_base": Color8(80, 110, 125),
				"color_leaves": Color8(185, 190, 200),
			}
		TreePreset.BIRCH:
			return {
				"name": "Birch",
				"lt": 0.7,
				"mn_sp_t": 0.6,
				"thk": 3,
				"gt_initial": 0.5,
				"warping": 3.0,
				"lf_gen": 6,
				"gt_per_gen": 0.35,
				"ang_dif": 0.9,
				"lf_amount": 3,
				"lf_length": 2.0,
				"lf_gravity": -30.0,
				"lf_thickness": 2,
				"s_end_mx": 4,
				"s_mid_mx": 6,
				"skip_gen_max": 0,
				"lf_steps": 0,
				"color_base": Color8(180, 170, 160),
				"color_leaves": Color8(90, 120, 40),
			}
		_:
			return {
				"name": "Oak",
				"lt": 0.7,
				"mn_sp_t": 0.3,
				"thk": 4,
				"gt_initial": 0.3,
				"warping": 5.0,
				"lf_gen": 4,
				"gt_per_gen": 0.35,
				"ang_dif": 1.3,
				"lf_amount": 4,
				"lf_length": 0.3,
				"lf_gravity": 0.0,
				"lf_thickness": 4,
				"s_end_mx": 5,
				"s_mid_mx": 4,
				"skip_gen_max": 0,
				"lf_steps": 2,
				"color_base": Color8(55, 45, 35),
				"color_leaves": Color8(60, 110, 40),
			}


func _randomize_color(base_color: Color, amount: float) -> Color:
	return Color8(
		_clamp_color_channel(base_color.r8 + int(round(_randf_range(-amount, amount)))),
		_clamp_color_channel(base_color.g8 + int(round(_randf_range(-amount, amount)))),
		_clamp_color_channel(base_color.b8 + int(round(_randf_range(-amount, amount)))),
		base_color.a8
	)


func _clamp_color_channel(value: int) -> int:
	return clampi(value, 0, 255)


func _rotate_angle(from_angle: float, to_angle: float, amount: float) -> float:
	amount = clampf(amount, -1.0, 1.0)
	var net_angle := fposmod(from_angle - to_angle + TAU, TAU)
	var delta := min(absf(net_angle - TAU), net_angle, absf(amount))
	var sign := 1.0 if (net_angle - PI) >= 0.0 else -1.0
	if amount < 0.0:
		sign *= -1.0
	from_angle += sign * delta + TAU
	return fposmod(from_angle, TAU)


func _randf() -> float:
	return _rng.randf()


func _randf_range(min_value: float, max_value: float) -> float:
	return _rng.randf_range(min_value, max_value)


func _randi_range(min_value: int, max_value: int) -> int:
	return _rng.randi_range(min_value, max_value)
