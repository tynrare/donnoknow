extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const GenDebugLog := preload("res://scripts/generator/debug_log.gd")


func _init() -> void:
	var name := "54x35_fixed27"
	var w := 54
	var h := 35
	if OS.get_cmdline_user_args().size() >= 3:
		name = str(OS.get_cmdline_user_args()[0])
		w = int(OS.get_cmdline_user_args()[1])
		h = int(OS.get_cmdline_user_args()[2])

	var manifest := GenService.load_manifest("res://assets/tiles/adve/manifest.json")
	var rules := GenRules.load(manifest.get("rules", ""))
	var constraints := GenConstraints.empty(w, h)
	if name.ends_with("fixed27"):
		GenConstraints.set_fixed(constraints, 15 if w >= 54 else 10, 5, 27)

	var options := GenService.default_options()
	var t0 := Time.get_ticks_msec()
	var job := GenWfcJob.new(rules, constraints, manifest, 42, int(options.get("max_restarts", 8)), options)
	var steps := 0
	while not job.finished and steps < w * h * 6:
		var step := job.step()
		if step.get("finished", false):
			break
		steps += 1

	var result := GenService.finalize_job(job, rules, constraints, 42, manifest, options)
	var ms := Time.get_ticks_msec() - t0
	var filled := int(result.get("filled", 0))
	var total := int(result.get("total", 0))
	GenDebugLog.write(
		"FILL",
		"debug_one_fill.gd",
		"case_done",
		{"case": name, "ms": ms, "steps": steps, "filled": filled, "total": total, "method": str(result.get("method", ""))},
		"post-fix",
	)
	print("%s filled=%d/%d (%.1f%%) ms=%d steps=%d" % [name, filled, total, 100.0 * filled / maxf(1.0, float(total)), ms, steps])
	quit(0 if filled >= int(total * 0.8) else 1)
