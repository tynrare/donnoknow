extends SceneTree

const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")
const GenService := preload("res://scripts/generator/service.gd")

func _init() -> void:
	var m := GenService.load_manifest("res://assets/tiles/adve/manifest.json")
	var a := GenAtlasAnalyze.analyze_atlas(m)
	var sa: Dictionary = a.sig_adjacency
	var s27 := "228d575d"
	var s468 := "76759d09"
	print("atlas sig27 north:", sa.get(s27, {}).get("north", {}))
	print("atlas sig468 south:", sa.get(s468, {}).get("south", {}))
	var descs: Dictionary = a.tile_descs
	# find atlas physical pairs between member gids
	var m27: Array = a.signatures.get(s27, [])
	var m468: Array = a.signatures.get(s468, [])
	var cols: int = int(m.columns)
	for ga in m27:
		for gb in m468:
			var da: Dictionary = descs[str(ga)]
			var db: Dictionary = descs[str(gb)]
			var la: int = int(da.local)
			var lb: int = int(db.local)
			if la - cols == lb and GenAtlasAnalyze.opposing_edges_match(da.edges, db.edges, "north"):
				print("atlas N: gid", ga, "above", gb, "tiles_equal", GenAtlasAnalyze.tiles_equal(da, db))
			if la + cols == lb and GenAtlasAnalyze.opposing_edges_match(da.edges, db.edges, "south"):
				print("atlas S: gid", ga, "above", gb)
	quit()
