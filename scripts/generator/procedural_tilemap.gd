@tool
extends TileMapLayer

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")

const GENERATED_NAME := "Generated"

@export var manifest_path: String = "res://assets/tiles/adve/manifest.json"
@export var rules_path: String = "res://resources/generator/adve.rules.json"
@export var map_seed: int = 0
@export var bounds: Rect2i = Rect2i(0, 0, 54, 35)


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


func _analyze_rules() -> void:
	var manifest: Dictionary = GenService.load_manifest(manifest_path)
	if manifest.is_empty():
		push_error("ProceduralTilemap: missing manifest %s" % manifest_path)
		return
	var rules: Dictionary = GenService.analyze_manifest(manifest)
	var path: String = rules_path if not rules_path.is_empty() else str(manifest.get("rules", ""))
	var err: Error = GenRules.save(path, rules)
	if err != OK:
		push_error("ProceduralTilemap: failed to save rules: %s" % error_string(err))
		return
	var stats: Dictionary = rules.get("stats", {})
	print(
		"ProceduralTilemap: analyzed %d cells, %d unique tiles → %s" % [
			int(stats.get("cells", 0)),
			int(stats.get("unique_tiles", 0)),
			path,
		]
	)


func _generate_map() -> void:
	var manifest: Dictionary = GenService.load_manifest(manifest_path)
	if manifest.is_empty():
		push_error("ProceduralTilemap: missing manifest %s" % manifest_path)
		return
	var rules: Dictionary = GenRules.load(rules_path)
	if rules.is_empty():
		push_error("ProceduralTilemap: missing rules %s (use Analyze Rules first)" % rules_path)
		return

	var w: int = bounds.size.x
	var h: int = bounds.size.y
	if w <= 0 or h <= 0:
		push_error("ProceduralTilemap: invalid bounds %s" % bounds)
		return

	var gids: PackedInt32Array = GenService.gids_from_layer(self, manifest, w, h, bounds.position)
	var constraints: Dictionary = GenConstraints.from_gids(w, h, gids)
	var result: Dictionary = GenService.generate(manifest, rules, constraints, map_seed)
	if not bool(result.get("ok", false)):
		push_error("ProceduralTilemap: generate failed: %s" % str(result.get("error", "?")))
		return

	var generated: TileMapLayer = _ensure_generated()
	GenService.clear_bounds(generated, bounds)
	GenService.apply_merge(generated, manifest, result.gids, constraints, bounds)
	generated.update_internals()
	print(
		"ProceduralTilemap: generated %dx%d seed=%d attempts=%d" % [
			w,
			h,
			int(result.get("seed", 0)),
			int(result.get("attempts", 0)),
		]
	)


func _clear_map() -> void:
	var generated := get_node_or_null(GENERATED_NAME) as TileMapLayer
	if generated == null:
		return
	GenService.clear_bounds(generated, bounds)
	generated.update_internals()
	print("ProceduralTilemap: cleared Generated in %s" % bounds)


@export_tool_button("Analyze Rules", "Callable")
var _analyze_action: Callable:
	get:
		return Callable(self, "_analyze_rules")


@export_tool_button("Generate", "Callable")
var _generate_action: Callable:
	get:
		return Callable(self, "_generate_map")


@export_tool_button("Clear", "Callable")
var _clear_action: Callable:
	get:
		return Callable(self, "_clear_map")
