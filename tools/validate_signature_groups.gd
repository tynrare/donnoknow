extends SceneTree

const GenService := preload("res://scripts/generator/service.gd")
const GenRules := preload("res://scripts/generator/rules.gd")
const GenAtlasAnalyze := preload("res://scripts/generator/atlas_analyze.gd")

const MANIFEST_PATH := "res://assets/tiles/adve/manifest.json"
const RULES_PATH := "res://resources/generator/adve.rules.json"


func _init() -> void:
	var manifest := GenService.load_manifest(MANIFEST_PATH)
	var rules := GenRules.load(RULES_PATH)
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

	if ok:
		print("PASS all signature groups")
		quit(0)
	else:
		push_error("FAIL signature group validation")
		quit(1)
