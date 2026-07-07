extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	if manifest.is_empty():
		push_error("Missing manifest. Run tools/import_adve_tiles.gd first.")
		quit(1)
		return

	var rules := GenService.analyze_manifest(manifest)
	var err := GenService.save_rules(manifest, rules)
	if err != OK:
		push_error("Save failed: %s" % error_string(err))
		quit(1)
		return

	var stats: Dictionary = rules.stats
	print(
		"Saved %s | cells=%d unique_tiles=%d" % [
			manifest.rules,
			stats.get("cells", 0),
			stats.get("unique_tiles", 0),
		]
	)
	quit()
