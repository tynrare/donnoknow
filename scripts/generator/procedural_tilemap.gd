# agent: composer-2.5 | 2026-07-07 | repeat_penalty option | h3i4j5
@tool
extends TileMapLayer

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")

const GENERATED_NAME := "Generated"

enum GenPhase { IDLE, PREP, JOB_INIT, RUNNING }

const FLUSH_INTERVAL_MS := 120

@export var manifest_path: String = "res://assets/tiles/adve/manifest.json"
@export var rules_path: String = "res://resources/generator/adve.rules.json"
@export var map_seed: int = 0
@export var max_restarts: int = 8
@export var steps_per_frame: int = 4
@export var bounds: Rect2i = Rect2i(0, 0, 54, 35)
@export var context_halo: int = 1
@export var use_patterns: bool = true
@export var pattern_propagate: bool = false
@export var backtrack_depth: int = 8
@export var backtrack_incidents: int = 64
@export var backtrack_cells: int = 128
@export var repeat_penalty: float = 1.0
@export var tile_bias: Dictionary = {}
@export var chunk_size: int = 8

const BOUNDS_HANDLE_RADIUS := 2.0

var _job = null
var _manifest: Dictionary = {}
var _constraints: Dictionary = {}
var _rules: Dictionary = {}
var _gen_width: int = 0
var _gen_height: int = 0
var _gen_halo: int = 0
var _gen_origin: Vector2i = Vector2i.ZERO
var _gen_options: Dictionary = {}
var _gen_phase: int = GenPhase.IDLE
var _replace_inner: bool = false
var _pending_flush: bool = false
var _flush_scheduled: bool = false
var _last_flush_ms: int = 0
var _collapsed_steps: int = 0


func get_bounds_local_rect() -> Rect2:
	var ts := _bounds_tile_size()
	var half := ts * 0.5
	var tl := map_to_local(bounds.position) - half
	return Rect2(tl, Vector2(bounds.size) * ts)


func _bounds_tile_size() -> Vector2:
	if tile_set:
		return Vector2(tile_set.tile_size)
	return Vector2(8, 8)


func canvas_pos_to_bounds_tile(canvas_pos: Vector2) -> Vector2i:
	return local_to_map(to_local(canvas_pos))


func queue_bounds_redraw() -> void:
	queue_redraw()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	if not _is_selected_in_editor():
		return

	var local_rect := get_bounds_local_rect()
	draw_rect(local_rect, Color(0.2, 0.85, 1.0, 0.12), true)
	draw_rect(local_rect, Color(0.2, 0.85, 1.0, 0.95), false, 1.0)

	var handles: Array[Vector2] = [
		local_rect.position,
		local_rect.position + Vector2(local_rect.size.x, 0.0),
		local_rect.position + local_rect.size,
		local_rect.position + Vector2(0.0, local_rect.size.y),
		local_rect.position + Vector2(local_rect.size.x * 0.5, 0.0),
		local_rect.position + Vector2(local_rect.size.x, local_rect.size.y * 0.5),
		local_rect.position + Vector2(local_rect.size.x * 0.5, local_rect.size.y),
		local_rect.position + Vector2(0.0, local_rect.size.y * 0.5),
		local_rect.get_center(),
	]
	for i in handles.size():
		var hp: Vector2 = handles[i]
		var fill := Color(1.0, 0.65, 0.1, 0.95) if i == 8 else Color(0.2, 0.85, 1.0, 0.95)
		draw_rect(
			Rect2(hp - Vector2.ONE * BOUNDS_HANDLE_RADIUS, Vector2.ONE * BOUNDS_HANDLE_RADIUS * 2.0),
			fill,
			true,
		)
		draw_rect(
			Rect2(hp - Vector2.ONE * BOUNDS_HANDLE_RADIUS, Vector2.ONE * BOUNDS_HANDLE_RADIUS * 2.0),
			Color(0.1, 0.1, 0.1, 0.9),
			false,
			1.0,
		)


func _is_selected_in_editor() -> bool:
	var selected: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	return selected.size() == 1 and selected[0] == self


func _gen_options_dict() -> Dictionary:
	return {
		"use_patterns": use_patterns,
		"pattern_propagate": pattern_propagate,
		"backtrack_depth": backtrack_depth,
		"backtrack_incidents": backtrack_incidents,
		"backtrack_cells": backtrack_cells,
		"max_restarts": max_restarts,
		"repeat_penalty": repeat_penalty,
		"tile_bias": tile_bias,
		"chunk_size": chunk_size,
	}


func _gen_paint_rect() -> Rect2i:
	return Rect2i(_gen_origin, Vector2i(_gen_width, _gen_height))


func _is_interior_idx(idx: int) -> bool:
	if _gen_halo <= 0:
		return true
	var lx: int = idx % _gen_width
	var ly: int = idx / _gen_width
	return (
		lx >= _gen_halo
		and ly >= _gen_halo
		and lx < _gen_halo + bounds.size.x
		and ly < _gen_halo + bounds.size.y
	)


func _generation_size(_manifest: Dictionary) -> Vector2i:
	var w: int = bounds.size.x
	var h: int = bounds.size.y
	if w > 0 and h > 0:
		return Vector2i(w, h)
	var map_size: Vector2i = GenService.map_size(_manifest)
	return map_size


func _seed_fixed_on_generated(
	generated: TileMapLayer,
	manifest: Dictionary,
	constraints: Dictionary,
	width: int,
	height: int,
) -> void:
	var source_id: int = manifest.get("source_id", 0)
	var paint_rect := _gen_paint_rect()
	for y in height:
		for x in width:
			var i: int = y * width + x
			if not _is_interior_idx(i):
				continue
			if constraints.modes[i] != GenConstraints.Mode.FIXED:
				continue
			var gid: int = constraints.fixed_gids[i]
			var atlas: Vector2i = GenService.gid_to_atlas(manifest, gid)
			if atlas.x < 0:
				continue
			generated.set_cell(
				paint_rect.position + Vector2i(x, y), source_id, atlas
			)


func _sync_generated_from_constraints(
	generated: TileMapLayer,
	manifest: Dictionary,
	constraints: Dictionary,
	width: int,
	height: int,
) -> void:
	_seed_fixed_on_generated(generated, manifest, constraints, width, height)
	var paint_rect := _gen_paint_rect()
	var seeds: PackedInt32Array = constraints.get("seed_gids", PackedInt32Array())
	for y in height:
		for x in width:
			var i: int = y * width + x
			if not _is_interior_idx(i):
				continue
			if constraints.modes[i] == GenConstraints.Mode.FIXED:
				continue
			if constraints.modes[i] == GenConstraints.Mode.FORBID:
				continue
			if i >= seeds.size() or seeds[i] <= 0:
				continue
			GenService.paint_cell(
				generated, manifest, paint_rect, width, i, seeds[i], constraints
			)


func _reset_generated_for_attempt(
	generated: TileMapLayer,
	manifest: Dictionary,
	constraints: Dictionary,
	width: int,
	height: int,
) -> void:
	GenService.clear_bounds(generated, bounds)
	_sync_generated_from_constraints(generated, manifest, constraints, width, height)


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
	var size: Vector2i = _generation_size(manifest)
	var w: int = size.x
	var h: int = size.y
	if w <= 0 or h <= 0:
		push_error("ProceduralTilemap: invalid generation bounds %s" % bounds)
		return
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


# agent: composer-2.5 | 2026-07-10 | train paint over generated | b238de
func _train_rules() -> void:
	var manifest: Dictionary = GenService.load_manifest(manifest_path)
	if manifest.is_empty():
		push_error("ProceduralTilemap: missing manifest %s" % manifest_path)
		return
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		push_error("ProceduralTilemap: invalid bounds %s" % bounds)
		return

	var w: int = bounds.size.x
	var h: int = bounds.size.y
	var generated := get_node_or_null(GENERATED_NAME) as TileMapLayer
	var gen_gids := PackedInt32Array()
	gen_gids.resize(w * h)
	gen_gids.fill(0)
	if generated != null:
		gen_gids = GenService.gids_from_layer(generated, manifest, w, h, bounds.position)
	var paint_gids: PackedInt32Array = GenService.gids_from_layer(
		self, manifest, w, h, bounds.position
	)
	var composite: PackedInt32Array = GenService.composite_gids(gen_gids, paint_gids)
	var filled := 0
	for gid in composite:
		if gid > 0:
			filled += 1
	if filled == 0:
		push_warning("ProceduralTilemap: no tiles in %s" % bounds)
		return

	var rules_path_resolved: String = (
		rules_path if not rules_path.is_empty() else str(manifest.get("rules", ""))
	)
	manifest = GenService.ensure_train_scene(manifest, rules_path_resolved, tile_set, bounds.size)
	var scene_path: String = GenService.resolve_train_scene(manifest, rules_path_resolved)
	if scene_path.is_empty() or not FileAccess.file_exists(scene_path):
		push_error("ProceduralTilemap: failed to create train scene")
		return

	var alloc: Dictionary = GenService.alloc_train_dest(manifest, bounds.size)
	manifest = alloc.manifest
	var dest: Rect2i = alloc.dest

	var root: Node2D = GenService.open_train_root(scene_path)
	if root == null:
		push_error("ProceduralTilemap: failed to open train scene %s" % scene_path)
		return
	var train_layer := root.get_node_or_null(GenService.TRAIN_LAYER_NAME) as TileMapLayer
	if train_layer == null:
		root.free()
		push_error("ProceduralTilemap: train scene missing %s layer" % GenService.TRAIN_LAYER_NAME)
		return

	GenService.apply_gids_region(train_layer, manifest, composite, w, dest.position)
	train_layer.update_internals()
	var chunk_gids: PackedInt32Array = composite
	var scene_err: Error = GenService.save_train_root(root, scene_path)
	root.free()
	if scene_err != OK:
		push_error("ProceduralTilemap: failed to save train scene: %s" % error_string(scene_err))
		return

	var manifest_err: Error = GenService.save_manifest(manifest_path, manifest)
	if manifest_err != OK:
		push_error("ProceduralTilemap: failed to save manifest: %s" % error_string(manifest_err))
		return

	var rules: Dictionary = GenRules.load(rules_path_resolved)
	var cs: int = 8 if chunk_size == null else chunk_size
	var updated: Dictionary = (
		GenRules.train_from_region(rules, chunk_gids, w, h, manifest, cs)
		if not rules.is_empty()
		else GenRules.train_from_region({}, chunk_gids, w, h, manifest, cs)
	)
	var err: Error = GenRules.save(rules_path_resolved, updated)
	if err != OK:
		push_error("ProceduralTilemap: failed to save rules: %s" % error_string(err))
		return
	var stats: Dictionary = updated.get("stats", {})
	print(
		"ProceduralTilemap: trained %d cells %s → chunk %s in %s, %d tiles → %s" % [
			filled,
			bounds,
			dest,
			scene_path,
			int(stats.get("unique_tiles", 0)),
			rules_path_resolved,
		]
	)


func _generate_map() -> void:
	_start_wfc_job(false)


func _patch_map() -> void:
	_start_wfc_job(true)


func _start_wfc_job(replace_inner: bool) -> void:
	if _gen_phase != GenPhase.IDLE or _job != null:
		push_warning("ProceduralTilemap: generation already running")
		return
	if not FileAccess.file_exists(manifest_path):
		push_error("ProceduralTilemap: missing manifest %s" % manifest_path)
		return
	if not FileAccess.file_exists(rules_path):
		push_error("ProceduralTilemap: missing rules %s (use Analyze Rules first)" % rules_path)
		return
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		push_error("ProceduralTilemap: invalid generation bounds %s" % bounds)
		return

	_replace_inner = replace_inner
	_collapsed_steps = 0
	_gen_phase = GenPhase.PREP
	set_process(true)
	print("ProceduralTilemap: preparing %s…" % bounds)


func _prep_generation() -> bool:
	var manifest: Dictionary = GenService.load_manifest(manifest_path)
	if manifest.is_empty():
		push_error("ProceduralTilemap: missing manifest %s" % manifest_path)
		return false
	var rules: Dictionary = GenRules.load(rules_path)
	if rules.is_empty():
		push_error("ProceduralTilemap: missing rules %s (use Analyze Rules first)" % rules_path)
		return false

	var size: Vector2i = _generation_size(manifest)
	var inner_w: int = size.x
	var inner_h: int = size.y
	if inner_w <= 0 or inner_h <= 0:
		push_error("ProceduralTilemap: invalid generation bounds %s" % bounds)
		return false

	var halo: int = maxi(context_halo, 0)
	var grid_w: int = inner_w + halo * 2
	var grid_h: int = inner_h + halo * 2
	var grid_origin: Vector2i = bounds.position - Vector2i(halo, halo)

	var paint_gids: PackedInt32Array = GenService.gids_from_layer(
		self, manifest, grid_w, grid_h, grid_origin
	)
	var generated: TileMapLayer = _ensure_generated()
	var context_gids: PackedInt32Array = GenService.gids_from_layer(
		generated, manifest, grid_w, grid_h, grid_origin
	)
	var constraints: Dictionary = GenConstraints.from_paint_seed_and_halo(
		grid_w,
		grid_h,
		halo,
		inner_w,
		inner_h,
		paint_gids,
		context_gids,
		_replace_inner,
	)
	var seed_count := 0
	var mutate_count := 0
	var context_count := 0
	for y in grid_h:
		for x in grid_w:
			var i: int = y * grid_w + x
			var in_inner: bool = (
				halo <= 0
				or (
					x >= halo
					and y >= halo
					and x < halo + inner_w
					and y < halo + inner_h
				)
			)
			if not in_inner:
				if (
					i < context_gids.size()
					and context_gids[i] > 0
					and constraints.modes[i] == GenConstraints.Mode.FIXED
				):
					context_count += 1
				continue
			if constraints.modes[i] == GenConstraints.Mode.FIXED:
				continue
			if i < context_gids.size() and context_gids[i] > 0:
				if _replace_inner:
					mutate_count += 1
				else:
					seed_count += 1
	var setup := GenService.validate_setup(manifest, rules, constraints)
	for warn in setup.get("warnings", []):
		print("ProceduralTilemap warn: %s" % warn)
	if not setup.get("ok", false):
		push_error("ProceduralTilemap: %s" % GenService.format_report(setup))
		return false

	var restarts: int = 32 if max_restarts == null else max_restarts
	var options: Dictionary = _gen_options_dict()
	options["max_restarts"] = restarts

	_manifest = manifest
	_constraints = constraints
	_rules = rules
	_gen_width = grid_w
	_gen_height = grid_h
	_gen_halo = halo
	_gen_origin = grid_origin
	_gen_options = options

	_sync_generated_from_constraints(generated, manifest, constraints, grid_w, grid_h)
	_flush_generated(false)

	if _replace_inner:
		var ctx_note := "" if context_count <= 0 else ", %d outside context" % context_count
		print(
			"ProceduralTilemap: patching %s (%d mutable, %d fixed%s)…"
			% [bounds, mutate_count, _count_fixed(constraints), ctx_note]
		)
	else:
		var mode := "continue" if seed_count > 0 else "new"
		var ctx_note := "" if context_count <= 0 else ", %d outside context" % context_count
		print(
			"ProceduralTilemap: generating %s wfc (%s, %d seeded, %d fixed%s)…"
			% [bounds, mode, seed_count, _count_fixed(constraints), ctx_note]
		)
	return true


func _spawn_job() -> void:
	var t0 := Time.get_ticks_msec()
	var restarts: int = int(_gen_options.get("max_restarts", max_restarts))
	_job = GenService.create_job(
		_manifest, _rules, _constraints, map_seed, restarts, _gen_options
	)
	var ms := Time.get_ticks_msec() - t0
	print("ProceduralTilemap: job init %d ms" % ms)
	if _job == null:
		push_error("ProceduralTilemap: failed to create job")
		_reset_generation_state()
		return
	if _job.finished or not _job.ready:
		push_error("ProceduralTilemap: failed to start job")
		_reset_generation_state()
		return
	_gen_phase = GenPhase.RUNNING


func _run_wfc_steps() -> void:
	if _job == null:
		_reset_generation_state()
		return

	var generated: TileMapLayer = _ensure_generated()
	var steps: int = 4 if steps_per_frame == null else maxi(steps_per_frame, 1)
	var painted := false

	for _i in steps:
		var step: Dictionary = _job.step()
		if step.get("finished", false):
			if painted:
				_flush_generated(true)
			_finish_job(step)
			return
		if step.has("idx") and step.has("gid"):
			_paint_step_cell(generated, int(step.idx), int(step.gid))
			painted = true
			_collapsed_steps += 1

	if painted:
		_flush_generated(Engine.is_editor_hint())
	if _collapsed_steps > 0 and _collapsed_steps % 400 == 0:
		print("ProceduralTilemap: collapsing… %d cells" % _collapsed_steps)


func _reset_generation_state() -> void:
	_job = null
	_manifest = {}
	_constraints = {}
	_rules = {}
	_gen_width = 0
	_gen_height = 0
	_gen_halo = 0
	_gen_origin = Vector2i.ZERO
	_gen_options = {}
	_gen_phase = GenPhase.IDLE
	_replace_inner = false
	_pending_flush = false
	_flush_scheduled = false
	_collapsed_steps = 0
	set_process(false)


func _count_fixed(constraints: Dictionary) -> int:
	var n := 0
	for i in constraints.modes.size():
		if constraints.modes[i] == GenConstraints.Mode.FIXED:
			n += 1
	return n


func _stop_generation() -> void:
	if _gen_phase == GenPhase.PREP or _gen_phase == GenPhase.JOB_INIT:
		_reset_generation_state()
		print("ProceduralTilemap: stopped before job started")
		return
	if _job == null:
		return
	_job.cancel()
	_flush_generated(true)
	_finish_job({"finished": true, "cancelled": true})
	print("ProceduralTilemap: stopped (partial kept)")


func _finish_job(step: Dictionary) -> void:
	var w: int = bounds.size.x
	var h: int = bounds.size.y
	var generated: TileMapLayer = _ensure_generated()

	var result: Dictionary = step
	if _job != null:
		result = GenService.finalize_job(
			_job, _rules, _constraints, map_seed, _manifest, _gen_options
		)

	var filled: int = int(result.get("filled", 0))
	if step.get("cancelled", false) or step.get("finished", false):
		_paint_result(generated, result)
		_log_result(result, w, h)
	elif int(result.get("total", 0)) == 0:
		_log_result(result, w, h)
	else:
		print(
			"ProceduralTilemap: stopped early (%s), %d/%d filled"
			% [str(result.get("error", step.get("error", "?"))), filled, int(result.get("total", 0))]
		)

	_reset_generation_state()


func _paint_result(generated: TileMapLayer, result: Dictionary) -> void:
	var gids: PackedInt32Array = result.get("gids", PackedInt32Array())
	var paint_rect := _gen_paint_rect()
	for i in gids.size():
		if not _is_interior_idx(i):
			continue
		if _constraints.modes[i] == GenConstraints.Mode.FIXED:
			continue
		if _constraints.modes[i] == GenConstraints.Mode.FORBID:
			continue
		if gids[i] <= 0:
			continue
		GenService.paint_cell(
			generated, _manifest, paint_rect, _gen_width, i, gids[i], _constraints
		)
		_pending_flush = true
	_flush_generated(true)


func _paint_step_cell(generated: TileMapLayer, idx: int, gid: int) -> void:
	if gid <= 0:
		return
	if not _is_interior_idx(idx):
		return
	GenService.paint_cell(
		generated, _manifest, _gen_paint_rect(), _gen_width, idx, gid, _constraints
	)
	_pending_flush = true


func _flush_generated(force: bool) -> void:
	if not _pending_flush:
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_flush_ms < FLUSH_INTERVAL_MS:
		return
	if force:
		_apply_generated_flush()
		return
	if _flush_scheduled:
		return
	_flush_scheduled = true
	call_deferred("_apply_generated_flush")


func _apply_generated_flush() -> void:
	_flush_scheduled = false
	if not _pending_flush:
		return
	var generated := get_node_or_null(GENERATED_NAME) as TileMapLayer
	if generated != null:
		generated.update_internals()
	_pending_flush = false
	_last_flush_ms = Time.get_ticks_msec()


func _erase_step_cell(generated: TileMapLayer, idx: int) -> void:
	if not _is_interior_idx(idx):
		return
	if _constraints.modes[idx] == GenConstraints.Mode.FIXED:
		return
	if _constraints.modes[idx] == GenConstraints.Mode.FORBID:
		return
	var cell := _gen_origin + Vector2i(idx % _gen_width, idx / _gen_width)
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
	match _gen_phase:
		GenPhase.PREP:
			if not _prep_generation():
				_reset_generation_state()
				return
			_gen_phase = GenPhase.JOB_INIT
			return
		GenPhase.JOB_INIT:
			_spawn_job()
			return
		GenPhase.RUNNING:
			_run_wfc_steps()
		_:
			set_process(false)


func _clear_map() -> void:
	_stop_generation()
	var generated := get_node_or_null(GENERATED_NAME) as TileMapLayer
	if generated == null:
		return
	GenService.clear_bounds(generated, bounds)
	generated.call_deferred("update_internals")
	queue_bounds_redraw()
	print("ProceduralTilemap: cleared Generated in %s" % bounds)


func _clear_all_map() -> void:
	_stop_generation()
	var generated := get_node_or_null(GENERATED_NAME) as TileMapLayer
	if generated == null:
		return
	generated.clear()
	generated.update_internals()
	queue_bounds_redraw()
	print("ProceduralTilemap: cleared all Generated tiles")


@export_tool_button("Validate Setup", "Callable")
var _validate_action: Callable:
	get:
		return Callable(self, "_validate_setup")


@export_tool_button("Analyze Rules", "Callable")
var _analyze_action: Callable:
	get:
		return Callable(self, "_analyze_rules")


@export_tool_button("Train", "Callable")
var _train_action: Callable:
	get:
		return Callable(self, "_train_rules")


@export_tool_button("Generate", "Callable")
var _generate_action: Callable:
	get:
		return Callable(self, "_generate_map")


@export_tool_button("Patch", "Callable")
var _patch_action: Callable:
	get:
		return Callable(self, "_patch_map")


@export_tool_button("Stop", "Callable")
var _stop_action: Callable:
	get:
		return Callable(self, "_stop_generation")


@export_tool_button("Clear", "Callable")
var _clear_action: Callable:
	get:
		return Callable(self, "_clear_map")


@export_tool_button("Clear All", "Callable")
var _clear_all_action: Callable:
	get:
		return Callable(self, "_clear_all_map")
