extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const GenDebugLog := preload("res://scripts/generator/debug_log.gd")


func _init() -> void:
	var run_id := "fill-audit"
	if OS.get_cmdline_user_args().size() > 0:
		run_id = str(OS.get_cmdline_user_args()[0])

	var manifest := GenService.load_manifest("res://assets/tiles/adve/manifest.json")
	var rules := GenRules.load(manifest.get("rules", ""))
	var cases := [
		{"name": "20x10_open", "w": 20, "h": 10, "fx": -1, "fy": -1, "fg": 0},
		{"name": "20x10_fixed27", "w": 20, "h": 10, "fx": 10, "fy": 5, "fg": 27},
		{"name": "54x35_open", "w": 54, "h": 35, "fx": -1, "fy": -1, "fg": 0},
		{"name": "54x35_fixed27", "w": 54, "h": 35, "fx": 15, "fy": 5, "fg": 27},
	]
	for cse in cases:
		_run_case(manifest, rules, cse, run_id)
	quit(0)


func _run_case(manifest: Dictionary, rules: Dictionary, cse: Dictionary, run_id: String) -> void:
	var w: int = cse.w
	var h: int = cse.h
	var constraints := GenConstraints.empty(w, h)
	if cse.fg > 0:
		GenConstraints.set_fixed(constraints, cse.fx, cse.fy, cse.fg)

	var options := GenService.default_options()
	var t0 := Time.get_ticks_msec()
	var job := GenWfcJob.new(rules, constraints, manifest, 42, int(options.get("max_restarts", 2)), options)
	var steps := 0
	var restarts := 0
	while not job.finished and steps < w * h * 6:
		var step := job.step()
		if step.get("restarted", false):
			restarts += 1
		if step.get("finished", false):
			break
		steps += 1

	var result := GenService.finalize_job(job, rules, constraints, 42, manifest, options)
	var ms := Time.get_ticks_msec() - t0
	GenDebugLog.write(
		"FILL",
		"debug_fill_audit.gd",
		"case_done",
		{
			"case": cse.name,
			"ms": ms,
			"steps": steps,
			"restarts": restarts,
			"filled": int(result.get("filled", 0)),
			"total": int(result.get("total", 0)),
			"method": str(result.get("method", "")),
			"attempts": int(result.get("attempts", 0)),
			"backtracks": int(result.get("backtracks", 0)),
			"error": str(result.get("error", "")),
		},
		run_id,
	)
	print(
		"%s filled=%d/%d ms=%d steps=%d attempts=%d backtracks=%d method=%s err=%s"
		% [
			cse.name,
			int(result.get("filled", 0)),
			int(result.get("total", 0)),
			ms,
			steps,
			int(result.get("attempts", 0)),
			int(result.get("backtracks", 0)),
			result.get("method", "?"),
			result.get("error", ""),
		]
	)
