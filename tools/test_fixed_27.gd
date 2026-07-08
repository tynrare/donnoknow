extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(manifest.get("rules", ""))

	var full := GenService.map_size(manifest)
	var full_c := GenConstraints.empty(full.x, full.y)
	GenConstraints.set_fixed(full_c, 15, 5, 27)
	var full_job := GenWfcJob.new(rules, full_c, manifest, 42, 4, GenService.default_options())
	if not full_job.ready:
		push_error("FAIL full %dx%d: job not ready with fixed GID 27 at (15,5)" % [full.x, full.y])
		quit(1)
		return
	print("PASS full %dx%d ready with fixed GID 27 at (15,5)" % [full.x, full.y])
	quit(0)
