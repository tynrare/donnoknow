extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	if manifest.is_empty():
		push_error("Missing manifest")
		quit(1)
		return

	var err: String = GenService.validate_manifest(manifest)
	if not err.is_empty():
		push_error(err)
		quit(1)
		return

	# atlas (2,1) with 24 columns → local 26 → GID 27
	var atlas := Vector2i(2, 1)
	var local: int = GenService.atlas_to_local(manifest, atlas)
	var gid: int = GenService.local_to_gid(manifest, local)
	var back: Vector2i = GenService.gid_to_atlas(manifest, gid)
	if local != 26 or gid != 27 or back != atlas:
		push_error(
			"GID roundtrip failed atlas=%s local=%d gid=%d back=%s cols=%d"
			% [atlas, local, gid, back, GenService.columns(manifest)]
		)
		quit(1)
		return
	print("PASS gid roundtrip atlas=%s → gid=%d (cols=%d)" % [atlas, gid, GenService.columns(manifest)])

	var rules := GenRules.load(manifest.get("rules", ""))
	if rules.is_empty():
		push_error("Missing rules")
		quit(1)
		return

	err = GenService.validate_rules_grid(manifest, rules)
	if not err.is_empty():
		push_error(err)
		quit(1)
		return

	var grid: Dictionary = rules.get("grid", {})
	if int(grid.get("columns", 0)) != 24:
		push_error("rules grid.columns=%s expected 24" % grid.get("columns", 0))
		quit(1)
		return

	var width := 20
	var height := 10
	for i in OS.get_cmdline_user_args().size():
		var a: String = OS.get_cmdline_user_args()[i]
		if a == "--width" and i + 1 < OS.get_cmdline_user_args().size():
			width = OS.get_cmdline_user_args()[i + 1].to_int()
		elif a == "--height" and i + 1 < OS.get_cmdline_user_args().size():
			height = OS.get_cmdline_user_args()[i + 1].to_int()

	var constraints := GenConstraints.empty(width, height)
	var options: Dictionary = GenService.default_options()
	options.gen_method = "wfc"

	var t0 := Time.get_ticks_msec()
	var job := GenWfcJob.new(rules, constraints, manifest, 42, 8, options)
	var steps := 0
	while not job.finished and steps < width * height * 4:
		job.step()
		steps += 1

	var result := GenService.finalize_job(job, rules, constraints, 42, manifest, options)
	var ms := Time.get_ticks_msec() - t0

	if result.get("gids", PackedInt32Array()).size() != width * height:
		push_error("Bad gids size")
		quit(1)
		return

	if int(result.get("filled", 0)) <= 0:
		push_error("No tiles filled")
		quit(1)
		return

	print(
		"PASS smoke %dx%d method=%s filled=%d/%d steps=%d ms=%d" % [
			width,
			height,
			result.get("method", "?"),
			int(result.get("filled", 0)),
			int(result.get("total", 0)),
			steps,
			ms,
		]
	)
	quit()
