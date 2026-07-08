extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const GenDebugLog := preload("res://scripts/generator/debug_log.gd")

const DEADLINE_MS := 120_000


func _init() -> void:
	var seed := 7
	if OS.get_cmdline_user_args().size() > 0:
		seed = int(OS.get_cmdline_user_args()[0])

	var manifest := GenService.load_manifest("res://assets/tiles/adve/manifest.json")
	var rules := GenRules.load(manifest.get("rules", ""))
	var w := 54
	var h := 35
	var constraints := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(constraints, 15, 5, 27)

	var options := GenService.default_options()
	options.use_patterns = true
	options.max_restarts = 8

	var job := GenWfcJob.new(rules, constraints, manifest, seed, 8, options)
	var steps := 0
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while not job.finished and Time.get_ticks_msec() < deadline:
		job.step()
		steps += 1

	var result := GenService.finalize_job(job, rules, constraints, seed, manifest, options)
	var filled := int(result.get("filled", 0))
	GenDebugLog.write(
		"FILL",
		"repro_seed7.gd",
		"done",
		{
			"seed": seed,
			"filled": filled,
			"total": int(result.get("total", 0)),
			"steps": steps,
			"attempts": int(result.get("attempts", 0)),
			"reason": str(result.get("error", "")),
		},
		"seed7",
	)
	print(
		"seed=%d filled=%d/%d steps=%d attempts=%d reason=%s"
		% [seed, filled, int(result.get("total", 0)), steps, int(result.get("attempts", 0)), result.get("error", "")]
	)
	quit(0 if filled > 10 else 1)
