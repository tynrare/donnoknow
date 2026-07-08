extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const GenDebugLog := preload("res://scripts/generator/debug_log.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"


func _init() -> void:
	var run_id := "bench"
	if OS.get_cmdline_user_args().size() > 0:
		run_id = str(OS.get_cmdline_user_args()[0])

	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(manifest.get("rules", ""))
	var w := 20
	var h := 10
	var constraints := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(constraints, 10, 5, 27)

	var options := GenService.default_options()
	var t0 := Time.get_ticks_msec()
	var job := GenWfcJob.new(rules, constraints, manifest, 42, options.get("max_restarts", 2), options)
	var steps := 0
	var restarts := 0
	while not job.finished and steps < w * h * 4:
		var step := job.step()
		if step.get("restarted", false):
			restarts += 1
		if step.get("finished", false):
			break
		steps += 1

	var result := GenService.finalize_job(job, rules, constraints, 42, manifest, options)
	var ms := Time.get_ticks_msec() - t0
	GenDebugLog.write(
		"SUM",
		"debug_gen_benchmark.gd",
		"benchmark_done",
		{
			"ms": ms,
			"steps": steps,
			"restarts": restarts,
			"attempts": int(result.get("attempts", 0)),
			"backtracks": int(result.get("backtracks", 0)),
			"filled": int(result.get("filled", 0)),
			"total": int(result.get("total", 0)),
			"method": str(result.get("method", "")),
			"ok": bool(result.get("ok", false)),
			"use_patterns": bool(options.get("use_patterns", false)),
		},
		run_id,
	)
	print(
		"BENCH run=%s ms=%d steps=%d filled=%d/%d method=%s attempts=%d backtracks=%d"
		% [
			run_id,
			ms,
			steps,
			int(result.get("filled", 0)),
			int(result.get("total", 0)),
			result.get("method", "?"),
			int(result.get("attempts", 0)),
			int(result.get("backtracks", 0)),
		]
	)
	quit(0)
