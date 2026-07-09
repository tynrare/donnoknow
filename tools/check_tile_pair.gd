extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")

const GIDS := [27, 468, 29, 5]


func _init() -> void:
	var manifest := GenService.load_manifest("res://assets/tiles/adve/manifest.json")
	var rules := GenRules.load("res://resources/generator/adve.rules.json")
	var atlas := GenAtlasAnalyze.analyze_atlas(manifest)
	var descs: Dictionary = atlas.get("tile_descs", {})

	for gid in [GID_A, GID_B]:
		var dd: Dictionary = descs.get(str(gid), {})
		var local: int = int(dd.get("local", -1))
		var cols: int = int(manifest.get("columns", 24))
		print("=== GID %d ===" % gid)
		print("  sig: %s" % GenAtlasAnalyze.sig_for_gid(rules, gid))
		print("  atlas: (%d, %d)" % [local % cols, local / cols])
		print("  cells: %s" % str(dd.get("cells", [])))
		print("  edges: %s" % str(dd.get("edges", {})))

	var du: Dictionary = descs[str(GID_A)]
	var db: Dictionary = descs[str(GID_B)]
	print("\n27 north : %s" % du.edges.get("north", ""))
	print("468 south: %s" % db.edges.get("south", ""))
	print("opposing match (27 above 468): %s" % GenAtlasAnalyze.opposing_edges_match(
		du.edges, db.edges, "north"
	))
	print("cells equal: %s" % GenAtlasAnalyze.cells_equal(du.cells, db.cells))
	print("rules 27 north->468: %s" % GenRules.adj_options(rules, GID_A, "north").get("468", 0))
	print("rules 468 south->27: %s" % GenRules.adj_options(rules, GID_B, "south").get("27", 0))

	var rep27: int = GenRules.representative_gid(rules, GID_A)
	var rep468: int = GenRules.representative_gid(rules, GID_B)
	print("\nrep 27=%d rep 468=%d" % [rep27, rep468])
	print("rep 27 north->468: %s" % GenRules.adj_options(rules, rep27, "north").get(str(GID_B), 0))
	quit()
