extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const Core := preload("res://scripts/generator/wfc_core.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const RULES_PATH := "res://resources/generator/adve.rules.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(RULES_PATH)
	var c := GenConstraints.empty(3, 3)
	# 468 above (north), 27 center, generate around
	GenConstraints.set_fixed(c, 1, 0, 468)
	GenConstraints.set_fixed(c, 1, 1, 27)

	var job := GenWfcJob.new(rules, c, manifest, 42, GenService.default_options())
	if not job.ready:
		push_error("FAIL job not ready")
		quit(1)

	var bad := Core.count_bad_adjacency(job.out, 3, 3, job.ctx)
	var north_gid: int = job.out[1] if job.out.size() > 1 else 0
	print("init out:", job.out)
	print("cell (1,0) gid:", job.out[0], " (1,1) gid:", job.out[4])
	print("bad_adj after init:", bad)
	print("468 south->27 north mutual:",
		Core._mutual_compat(job.ctx, 468, 0, 27) if false else "n/a")
	quit(0 if bad == 0 else 1)
