extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const GenWfc := preload("res://scripts/generator/wfc.gd")


func _init() -> void:
	var manifest := GenService.load_manifest("res://assets/tiles/adve/manifest.json")
	var rules := GenRules.load(manifest.get("rules", ""))
	var w := 56
	var h := 37
	var constraints := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(constraints, 15 + 1, 5 + 1, 27)

	var seeds := PackedInt32Array()
	seeds.resize(w * h)
	seeds.fill(0)
	for y in h:
		for x in w:
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				continue
			seeds[y * w + x] = 1 + ((x + y) % 40)

	var c := GenConstraints.from_paint_seed_and_halo(w, h, 1, 54, 35, seeds, seeds, false)
	var t0 := Time.get_ticks_msec()
	var job := GenWfcJob.new(rules, c, manifest, 42, 4, GenService.default_options())
	var ms := Time.get_ticks_msec() - t0
	print("job init dense seeds ms=%d ready=%s" % [ms, job.ready])
	quit(0 if ms < 5000 else 1)
