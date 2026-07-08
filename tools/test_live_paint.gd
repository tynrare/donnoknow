extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const GenDebugLog := preload("res://scripts/generator/debug_log.gd")


func _init() -> void:
	var manifest := GenService.load_manifest("res://assets/tiles/adve/manifest.json")
	var rules := GenRules.load(manifest.get("rules", ""))
	var w := 20
	var h := 10
	var constraints := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(constraints, 10, 5, 27)

	var job := GenWfcJob.new(
		rules, constraints, manifest, 42, 8, GenService.default_options()
	)
	var paints := 0
	var erases := 0
	var steps := 0
	while not job.finished and steps < 400:
		var step := job.step()
		steps += 1
		if step.get("finished", false):
			break
		if step.get("backtracked", false) and step.has("idx"):
			erases += 1
		elif step.has("idx") and step.has("gid") and int(step.gid) > 0:
			paints += 1

	GenDebugLog.write(
		"H7",
		"test_live_paint.gd",
		"step_paint_counts",
		{"paints": paints, "erases": erases, "steps": steps},
		"live-paint",
	)
	if paints < 10:
		push_error("FAIL: expected live paint steps, got paints=%d" % paints)
		quit(1)
		return
	print("PASS live paint events paints=%d erases=%d steps=%d" % [paints, erases, steps])
	quit(0)
