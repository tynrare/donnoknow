extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")


func _init() -> void:
	var manifest := GenService.load_manifest("res://assets/tiles/adve/manifest.json")
	var rules := GenRules.load(manifest.get("rules", ""))
	var w := 20
	var h := 10
	var constraints := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(constraints, 10, 5, 27)

	var job := GenWfcJob.new(rules, constraints, manifest, 42, GenService.default_options())
	var paints := 0
	var steps := 0
	while not job.finished and steps < 400:
		var step := job.step()
		steps += 1
		if step.get("finished", false):
			break
		if step.has("idx") and step.has("gid") and int(step.gid) > 0:
			paints += 1

	if paints <= 0:
		push_error("FAIL live paint: no tiles painted")
		quit(1)
		return
	print("PASS live paint paints=%d steps=%d" % [paints, steps])
	quit(0)
