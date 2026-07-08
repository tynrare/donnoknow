extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	if manifest.is_empty():
		push_error("Missing manifest")
		quit(1)
		return

	var rules := GenRules.load(manifest.get("rules", ""))
	var map_size := GenService.map_size(manifest)
	var constraints := GenConstraints.empty(map_size.x, map_size.y)
	var report := GenService.validate_setup(manifest, rules, constraints)
	print(GenService.format_report(report))
	quit(0 if report.get("ok", false) else 1)
