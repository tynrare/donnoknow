extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")
const GenWfcJob := preload("res://scripts/generator/wfc_job.gd")
const GenConstraints := preload("res://scripts/generator/constraints.gd")
const Core := preload("res://scripts/generator/wfc_core.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const RULES_PATH := "res://resources/generator/adve.rules.json"

const VERTICAL_GROUP := [54, 78, 102]


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(RULES_PATH)
	var atlas := GenAtlasAnalyze.analyze_atlas(manifest)
	var descs: Dictionary = atlas.get("tile_descs", {})

	_check_signature_group(rules)
	_check_atlas_vertical_edges(descs)
	_check_rules_vertical_adjacency(rules)
	_check_wfc_vertical_column(manifest, rules)

	print("PASS vertical edge group %s" % str(VERTICAL_GROUP))
	quit(0)


func _check_signature_group(rules: Dictionary) -> void:
	var sigs: Dictionary = {}
	for gid in VERTICAL_GROUP:
		var sig: String = GenAtlasAnalyze.sig_for_gid(rules, gid)
		if sig.is_empty():
			push_error("FAIL gid %d has no signature" % gid)
			quit(1)
		sigs[sig] = true
	if sigs.size() != 1:
		push_error("FAIL vertical group split across signatures: %s" % str(sigs.keys()))
		quit(1)


func _check_atlas_vertical_edges(descs: Dictionary) -> void:
	for i in VERTICAL_GROUP.size() - 1:
		var upper: int = VERTICAL_GROUP[i]
		var lower: int = VERTICAL_GROUP[i + 1]
		var du: Dictionary = descs.get(str(upper), {})
		var dl: Dictionary = descs.get(str(lower), {})
		if du.is_empty() or dl.is_empty():
			push_error("FAIL missing tile_descs for %d or %d" % [upper, lower])
			quit(1)
		var south: String = str(du.edges.get("south", ""))
		var north: String = str(dl.edges.get("north", ""))
		if south != north:
			push_error(
				"FAIL atlas vertical edge %d south %s != %d north %s"
				% [upper, south, lower, north]
			)
			quit(1)
		print("  atlas %d south == %d north (%s)" % [upper, lower, south])


func _check_rules_vertical_adjacency(rules: Dictionary) -> void:
	for i in VERTICAL_GROUP.size() - 1:
		var upper: int = VERTICAL_GROUP[i]
		var lower: int = VERTICAL_GROUP[i + 1]
		var south_ok: int = int(GenRules.adj_options(rules, upper, "south").get(str(lower), 0))
		var north_ok: int = int(GenRules.adj_options(rules, lower, "north").get(str(upper), 0))
		if south_ok <= 0 or north_ok <= 0:
			push_error(
				"FAIL rules adjacency %d above %d south=%d north=%d"
				% [upper, lower, south_ok, north_ok]
			)
			quit(1)
			return
		print("  rules %d south <-> %d north OK" % [upper, lower])

	var sig: String = GenAtlasAnalyze.sig_for_gid(rules, VERTICAL_GROUP[0])
	var self_south: int = int(
		rules.get("sig_adjacency", {}).get(sig, {}).get("south", {}).get(sig, 0)
	)
	if self_south < 2:
		push_error("FAIL sig %s missing self south adjacency for vertical stack" % sig)
		quit(1)


func _check_wfc_vertical_column(manifest: Dictionary, rules: Dictionary) -> void:
	var w := 1
	var h := 3
	var c := GenConstraints.empty(w, h)
	GenConstraints.set_fixed(c, 0, 0, VERTICAL_GROUP[0])
	GenConstraints.set_fixed(c, 0, 1, VERTICAL_GROUP[1])
	GenConstraints.set_fixed(c, 0, 2, VERTICAL_GROUP[2])

	var job := GenWfcJob.new(rules, c, manifest, 42, GenService.default_options())
	if not job.ready:
		push_error("FAIL vertical column job not ready")
		quit(1)

	var bad := Core.count_bad_adjacency(job.out, w, h, job.ctx)
	if bad > 0:
		push_error("FAIL vertical column bad_adj=%d out=%s" % [bad, str(job.out)])
		quit(1)
	print("  wfc 1x3 fixed column bad_adj=0")
