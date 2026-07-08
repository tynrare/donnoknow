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
	var full_job := GenWfcJob.new(rules, full_c, manifest, 42, GenService.default_options())
	if not full_job.ready:
		push_error("FAIL full %dx%d: job not ready with fixed GID 27 at (15,5)" % [full.x, full.y])
		quit(1)
		return
	print("PASS full %dx%d ready with fixed GID 27 at (15,5)" % [full.x, full.y])

	var halo := 1
	var gw := full.x + halo * 2
	var gh := full.y + halo * 2
	var n := gw * gh
	var paint := PackedInt32Array()
	paint.resize(n)
	paint.fill(0)
	var context := PackedInt32Array()
	context.resize(n)
	context.fill(0)
	paint[(halo + 15) * gw + (halo + 5)] = 27
	paint[(halo + 20) * gw + (halo + 10)] = 27
	for y in gh:
		for x in gw:
			var i := y * gw + x
			var in_inner := (
				x >= halo
				and y >= halo
				and x < halo + full.x
				and y < halo + full.y
			)
			if not in_inner:
				context[i] = int(manifest.get("background_gid", 1))
	var halo_c := GenConstraints.from_paint_seed_and_halo(
		gw, gh, halo, full.x, full.y, paint, context, false
	)
	var halo_job := GenWfcJob.new(rules, halo_c, manifest, 42, GenService.default_options())
	if not halo_job.ready:
		push_error("FAIL two paint + halo context: job not ready")
		quit(1)
		return
	print("PASS two paint + halo context job ready")
	quit(0)
