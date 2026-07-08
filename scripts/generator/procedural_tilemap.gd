# agent: composer-2.5 | 2026-07-07 | repeat_penalty option | h3i4j5
@tool
extends TileMapLayer

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")

const GENERATED_NAME := "Generated"

@export var manifest_path: String = "res://assets/tiles/adve/manifest.json"
@export var rules_path: String = "res://resources/generator/adve.rules.json"
@export var map_seed: int = 0
@export var max_restarts: int = 8
@export var steps_per_frame: int = 2
@export var bounds: Rect2i = Rect2i(0, 0, 54, 35)
@export var strict_patterns: bool = false
@export var use_patterns: bool = true
@export var backtrack_depth: int = 8
@export var repeat_penalty: float = 1.0
@export var tile_bias: Dictionary = {}
@export var chunk_size: int = 8

var _job: GenWfcJob = null
var _manifest: Dictionary = {}
var _constraints: Dictionary = {}
var _rules: Dictionary = {}
var _gen_width: int = 0
var _gen_height: int = 0
var _gen_options: Dictionary = {}


func _gen_options_dict() -> Dictionary:
	return {
		"strict_patterns": strict_patterns,
		"use_patterns": use_patterns,
		"backtrack_depth": backtrack_depth,
		"max_restarts": max_restarts,
		"repeat_penalty": repeat_penalty,
		"tile_bias": tile_bias,
		"chunk_size": chunk_size,
	}


func _seed_fixed_on_generated(
	generated: TileMapLayer,
	manifest: Dictionary,
	constraints: Dictionary,
	width: int,
	height: int,
) -> void:
	var source_id: int = manifest.get("source_id", 0)
	for y in height:
		for x in width:
			var i: int = y * width + x
			if constraints.modes[i] != GenConstraints.Mode.FIXED:
				continue
			var gid: int = constraints.fixed_gids[i]
			var atlas: Vector2i = GenService.gid_to_atlas(manifest, gid)
			if atlas.x < 0:
				continue
			generated.set_cell(bounds.position + Vector2i(x, y), source_id, atlas)


func _ensure_generated() -> TileMapLayer:
	var generated := get_node_or_null(GENERATED_NAME) as TileMapLayer
	if generated != null:
		return generated

	generated = TileMapLayer.new()
	generated.name = GENERATED_NAME
	generated.tile_set = tile_set
	generated.z_index = z_index - 1
	add_child(generated)
	_set_editable_owner(generated)
	return generated


func _set_editable_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var root := get_tree().edited_scene_root
	if root and node.owner != root:
		node.owner = root


func _validate_setup() -> void:
	var manifest: Dictionary = GenService.load_manifest(manifest_path)
	if manifest.is_empty():
		push_error("ProceduralTilemap: missing manifest %s" % manifest_path)
		return
	var rules: Dictionary = GenRules.load(rules_path)
	var map_size: Vector2i = GenService.map_size(manifest)
	var w: int = map_size.x if map_size.x > 0 else bounds.size.x
	var h: int = map_size.y if map_size.y > 0 else bounds.size.y
	var gids: PackedInt32Array = GenService.gids_from_layer(self, manifest, w, h, bounds.position)
	var constraints: Dictionary = GenConstraints.from_gids(w, h, gids)
	var report: Dictionary = GenService.validate_setup(manifest, rules, constraints)
	print("ProceduralTilemap validate:\n%s" % GenService.format_report(report))
	if not report.get("ok", false):
		push_error("ProceduralTilemap: setup has errors (see Output)")


func _analyze_rules() -> void:
	var manifest: Dictionary = GenService.load_manifest(manifest_path)
	if manifest.is_empty():
		push_error("ProceduralTilemap: missing manifest %s" % manifest_path)
		return
	var pre := GenService.validate_setup(manifest)
	for warn in pre.get("warnings", []):
		print("ProceduralTilemap analyze warn: %s" % warn)
	if not pre.get("ok", false):
		push_error("ProceduralTilemap: %s" % GenService.validate_manifest(manifest))
		return
	var cs: int = 8 if chunk_size == null else chunk_size
	var rules: Dictionary = GenService.analyze_manifest(manifest, cs)
	var path: String = rules_path if not rules_path.is_empty() else str(manifest.get("rules", ""))
	var err: Error = GenRules.save(path, rules)
	if err != OK:
		push_error("ProceduralTilemap: failed to save rules: %s" % error_string(err))
		return
	var stats: Dictionary = rules.get("stats", {})
	var grid: Dictionary = rules.get("grid", {})
	var sources: Dictionary = rules.get("sources", {})
	print(
		"ProceduralTilemap: analyzed %d cells, %d tiles, %d chunks, grid=%dx%d map=%dx%d sources=%s → %s" % [
			int(stats.get("cells", 0)),
			int(stats.get("unique_tiles", 0)),
			int(stats.get("chunks", 0)),
			int(grid.get("columns", 0)),
			int(grid.get("rows", 0)),
			int(grid.get("map_width", 0)),
			int(grid.get("map_height", 0)),
			sources,
			path,
		]
	)


func _generate_map() -> void:
	if _job != null:
		push_warning("ProceduralTilemap: generation already running")
		return

	var manifest: Dictionary = GenService.load_manifest(manifest_path)
	if manifest.is_empty():
		push_error("ProceduralTilemap: missing manifest %s" % manifest_path)
		return
	var rules: Dictionary = GenRules.load(rules_path)
	if rules.is_empty():
		push_error("ProceduralTilemap: missing rules %s (use Analyze Rules first)" % rules_path)
		return

	var map_size: Vector2i = GenService.map_size(manifest)
	var w: int = map_size.x if map_size.x > 0 else bounds.size.x
	var h: int = map_size.y if map_size.y > 0 else bounds.size.y
	if w <= 0 or h <= 0:
		push_error("ProceduralTilemap: invalid bounds %s" % bounds)
		return
	if map_size.x > 0 and map_size.y > 0:
		bounds = Rect2i(bounds.position.x, bounds.position.y, w, h)

	var paint_gids: PackedInt32Array = GenService.gids_from_layer(self, manifest, w, h, bounds.position)
	var generated: TileMapLayer = _ensure_generated()
	var seed_gids: PackedInt32Array = GenService.gids_from_layer(generated, manifest, w, h, bounds.position)
	var constraints: Dictionary = GenConstraints.from_paint_and_seed(w, h, paint_gids, seed_gids)
	var seed_count := 0
	for i in seed_gids.size():
		if seed_gids[i] > 0 and constraints.modes[i] != GenConstraints.Mode.FIXED:
			seed_count += 1
	var setup := GenService.validate_setup(manifest, rules, constraints)
	for warn in setup.get("warnings", []):
		print("ProceduralTilemap warn: %s" % warn)
	if not setup.get("ok", false):
		push_error("ProceduralTilemap: %s" % GenService.format_report(setup))
		return

	var restarts: int = 32 if max_restarts == null else max_restarts
	var options: Dictionary = _gen_options_dict()

	GenService.clear_bounds(generated, bounds)
	_seed_fixed_on_generated(generated, manifest, constraints, w, h)
	generated.update_internals()

	_manifest = manifest
	_constraints = constraints
	_rules = rules
	_gen_width = w
	_gen_height = h
	_gen_options = options

	_job = GenService.create_job(manifest, rules, constraints, map_seed, restarts, options)
	if _job.finished:
		push_error("ProceduralTilemap: failed to start job")
		_job = null
		return

	set_process(true)
	var mode := "continue" if seed_count > 0 else "new"
	print(
		"ProceduralTilemap: generating %dx%d wfc (%s, %d seeded, %d fixed)…"
		% [w, h, mode, seed_count, _count_fixed(constraints)]
	)


func _count_fixed(constraints: Dictionary) -> int:
	var n := 0
	for i in constraints.modes.size():
		if constraints.modes[i] == GenConstraints.Mode.FIXED:
			n += 1
	return n


func _stop_generation() -> void:
	if _job == null:
		return
	_job.cancel()
	var generated := get_node_or_null(GENERATED_NAME) as TileMapLayer
	if generated != null:
		generated.update_internals()
	_finish_job({"finished": true, "cancelled": true})
	print("ProceduralTilemap: stopped (partial kept)")


func _finish_job(step: Dictionary) -> void:
	var w: int = _gen_width if _gen_width > 0 else bounds.size.x
	var h: int = _gen_height if _gen_height > 0 else bounds.size.y
	var generated: TileMapLayer = _ensure_generated()

	var result: Dictionary = step
	if _job != null:
		result = GenService.finalize_job(
			_job, _rules, _constraints, map_seed, _manifest, _gen_options
		)

	var filled: int = int(result.get("filled", 0))
	if filled > 0 or step.get("cancelled", false) or step.get("ok", false):
		_paint_result(generated, result)
		_log_result(result, w, h)
	elif int(result.get("total", 0)) == 0:
		_log_result(result, w, h)
	else:
		print(
			"ProceduralTilemap: stopped early (%s), %d/%d filled"
			% [str(result.get("error", step.get("error", "?"))), filled, int(result.get("total", 0))]
		)

	_job = null
	_manifest = {}
	_constraints = {}
	_rules = {}
	_gen_options = {}
	set_process(false)


func _paint_result(generated: TileMapLayer, result: Dictionary) -> void:
	var gids: PackedInt32Array = result.get("gids", PackedInt32Array())
	var w: int = _gen_width if _gen_width > 0 else bounds.size.x
	for i in gids.size():
		if _constraints.modes[i] == GenConstraints.Mode.FIXED:
			continue
		if _constraints.modes[i] == GenConstraints.Mode.FORBID:
			continue
		if gids[i] <= 0:
			continue
		GenService.paint_cell(generated, _manifest, bounds, w, i, gids[i], _constraints)
	generated.update_internals()


func _paint_step_cell(generated: TileMapLayer, idx: int, gid: int) -> void:
	if gid <= 0:
		return
	GenService.paint_cell(
		generated, _manifest, bounds, _gen_width, idx, gid, _constraints
	)


func _erase_step_cell(generated: TileMapLayer, idx: int) -> void:
	if _constraints.modes[idx] == GenConstraints.Mode.FIXED:
		return
	if _constraints.modes[idx] == GenConstraints.Mode.FORBID:
		return
	var cell := bounds.position + Vector2i(idx % _gen_width, idx / _gen_width)
	generated.erase_cell(cell)


func _log_result(result: Dictionary, w: int, h: int) -> void:
	print(
		"ProceduralTilemap: %dx%d method=%s filled=%d/%d seed=%d attempts=%d backtracks=%d" % [
			w,
			h,
			str(result.get("method", "?")),
			int(result.get("filled", 0)),
			int(result.get("total", 0)),
			int(result.get("seed", 0)),
			int(result.get("attempts", 0)),
			int(result.get("backtracks", 0)),
		]
	)


func _process(_delta: float) -> void:
	if _job == null:
		set_process(false)
		return

	var generated: TileMapLayer = _ensure_generated()
	var steps: int = 8 if steps_per_frame == null else maxi(steps_per_frame, 1)
	var dirty := false

	for _i in steps:
		var step: Dictionary = _job.step()
		if step.get("restarted", false) and _job != null and not _job.cancelled:
			GenService.clear_bounds(generated, bounds)
			_seed_fixed_on_generated(
				generated, _manifest, _constraints, _gen_width, _gen_height
			)
			dirty = true
		elif step.get("finished", false):
			if dirty:
				generated.update_internals()
			_finish_job(step)
			return
		elif step.get("backtracked", false) and step.has("idx"):
			_erase_step_cell(generated, int(step.idx))
			dirty = true
		elif step.has("idx") and step.has("gid"):
			_paint_step_cell(generated, int(step.idx), int(step.gid))
			dirty = true

	if dirty:
		generated.update_internals()


func _clear_map() -> void:
	_stop_generation()
	var generated := get_node_or_null(GENERATED_NAME) as TileMapLayer
	if generated == null:
		return
	GenService.clear_bounds(generated, bounds)
	generated.update_internals()
	print("ProceduralTilemap: cleared Generated in %s" % bounds)


@export_tool_button("Validate Setup", "Callable")
var _validate_action: Callable:
	get:
		return Callable(self, "_validate_setup")


@export_tool_button("Analyze Rules", "Callable")
var _analyze_action: Callable:
	get:
		return Callable(self, "_analyze_rules")


@export_tool_button("Generate", "Callable")
var _generate_action: Callable:
	get:
		return Callable(self, "_generate_map")


@export_tool_button("Stop", "Callable")
var _stop_action: Callable:
	get:
		return Callable(self, "_stop_generation")


@export_tool_button("Clear", "Callable")
var _clear_action: Callable:
	get:
		return Callable(self, "_clear_map")
