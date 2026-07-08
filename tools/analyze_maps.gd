extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	if manifest.is_empty():
		push_error("Missing manifest. Run tools/import_adve_tiles.gd first.")
		quit(1)
		return

	var rules := GenService.analyze_manifest(manifest, 8)
	var err := GenService.save_rules(manifest, rules)
	if err != OK:
		push_error("Save failed: %s" % error_string(err))
		quit(1)
		return

	var stats: Dictionary = rules.stats
	var grid: Dictionary = rules.get("grid", {})
	var sources: Dictionary = rules.get("sources", {})
	print(
		"Saved %s | cells=%d unique_tiles=%d patterns=%d contexts=%d chunks=%d classes=%d grid=%dx%d map=%dx%d sources=%s v=%d" % [
			manifest.rules,
			stats.get("cells", 0),
			stats.get("unique_tiles", 0),
			stats.get("patterns_3x3", 0),
			stats.get("context_keys", 0),
			stats.get("chunks", 0),
			stats.get("tile_classes", 0),
			grid.get("columns", 0),
			grid.get("rows", 0),
			grid.get("map_width", 0),
			grid.get("map_height", 0),
			sources,
			int(rules.get("version", 0)),
		]
	)
	quit()
