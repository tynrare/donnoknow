extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(manifest.get("rules", ""))

	# Full map: fixed GID 27 at (15,5) must start generation (editor paint cell).
	var full := GenService.map_size(manifest)
	var full_c := GenConstraints.empty(full.x, full.y)
	GenConstraints.set_fixed(full_c, 15, 5, 27)
	var full_job := GenWfcJob.new(rules, full_c, manifest, 42, 4, GenService.default_options())
	if not full_job.ready:
		push_error("FAIL full %dx%d: job not ready with fixed GID 27 at (15,5)" % [full.x, full.y])
		quit(1)
		return
	print("PASS full %dx%d ready with fixed GID 27 at (15,5)" % [full.x, full.y])

	# Small map: complete generation with same fixed tile.
	var w := 20
	var h := 10
	var constraints := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(constraints, 10, 5, 27)
	var job := GenWfcJob.new(rules, constraints, manifest, 42, 16, GenService.default_options())
	var steps := 0
	while not job.finished and steps < w * h * 8:
		var step := job.step()
		if step.get("finished", false):
			if step.get("ok", false):
				print("PASS fixed GID 27 generate %dx%d filled=%d" % [w, h, int(step.get("filled", 0))])
				quit()
				return
			push_error("FAIL %dx%d: %s" % [w, h, step.get("error", "?")])
			quit(1)
			return
		steps += 1

	push_error("FAIL %dx%d: timeout" % [w, h])
	quit(1)
