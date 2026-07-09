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

	for gid in GIDS:
		var dd: Dictionary = descs.get(str(gid), {})
		var local: int = int(dd.get("local", -1))
		var cols: int = int(manifest.get("columns", 24))
		print("=== GID %d ===" % gid)
		print("  sig: %s" % GenAtlasAnalyze.sig_for_gid(rules, gid))
		print("  atlas: (%d, %d)" % [local % cols, local / cols])
		print("  cells: %s" % str(dd.get("cells", [])))
		print("  edges: %s" % str(dd.get("edges", {})))

	for pair in [[27, 468], [29, 5]]:
		var ga: int = pair[0]
		var gb: int = pair[1]
		var du: Dictionary = descs[str(ga)]
		var db: Dictionary = descs[str(gb)]
		print("\n--- %d north of %d ---" % [gb, ga])
		print("%d north : %s" % [ga, du.edges.get("north", "")])
		print("%d south: %s" % [gb, db.edges.get("south", "")])
		print("edge match: %s  tiles equal: %s" % [
			GenAtlasAnalyze.opposing_edges_match(du.edges, db.edges, "north"),
			GenAtlasAnalyze.tiles_equal(du, db),
		])
	quit()
