extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const RULES_PATH := "res://resources/generator/adve.rules.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(RULES_PATH)
	var atlas := GenAtlasAnalyze.analyze_atlas(manifest)
	var descs: Dictionary = atlas.get("tile_descs", {})
	var groups: Array = manifest.get("analyze", {}).get("signature_groups", [])
	if groups.is_empty():
		push_error("No analyze.signature_groups in manifest")
		quit(1)
		return

	var ok := true
	var exclusive: bool = bool(manifest.get("analyze", {}).get("signature_groups_exclusive", false))
	for group in groups:
		if group is not Array:
			continue
		var gids: Array = []
		for g in group:
			gids.append(int(g))
		if gids.is_empty():
			continue
		var sigs: Dictionary = {}
		for gid in gids:
			var sig: String = GenAtlasAnalyze.sig_for_gid(rules, gid)
			sigs[sig] = true
		var sig_list: Array = sigs.keys()
		if sig_list.size() != 1:
			ok = false
			print("FAIL group %s -> %d signatures: %s" % [str(gids), sig_list.size(), sig_list])
			for gid in gids:
				print("  GID %d sig=%s" % [gid, GenAtlasAnalyze.sig_for_gid(rules, gid)])
			continue
		var sig: String = str(sig_list[0])
		var members: Array = rules.get("signatures", {}).get(sig, [])
		var outsiders: Array = []
		for member in members:
			if not gids.has(int(member)):
				outsiders.append(int(member))
		if exclusive and not outsiders.is_empty():
			ok = false
			print("FAIL group %s sig=%s has outsiders %s" % [str(gids), sig, str(outsiders)])
		else:
			var extra := " outsiders=%s" % str(outsiders) if not outsiders.is_empty() else ""
			print("PASS group %s sig=%s members=%s%s" % [str(gids), sig, str(members), extra])
		_check_full_tile_members(descs, gids)

	if ok:
		print("PASS all signature groups")
		quit(0)
	else:
		push_error("FAIL signature group validation")
		quit(1)


func _check_full_tile_members(descs: Dictionary, gids: Array) -> void:
	if gids.is_empty():
		return
	var rep: Array = descs.get(str(gids[0]), {}).get("cells", [])
	if rep.is_empty():
		return
	for gid in gids:
		var cells: Array = descs.get(str(gid), {}).get("cells", [])
		if not GenAtlasAnalyze.cells_equal(cells, rep):
			push_error(
				"FAIL group %s: gid %d differs in full 2x2 tile (edge-only alias rejected)"
				% [str(gids), gid]
			)
			quit(1)
