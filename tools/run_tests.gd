extends SceneTree

const DEADLINE_MS := 420_000

const TESTS := [
	"tools/validate_setup.gd",
	"tools/test_propagate.gd",
	"tools/test_editor_propagate.gd",
	"tools/test_fixed_27.gd",
	"tools/test_10x10_fixed27.gd",
	"tools/test_map_validate.gd",
	"tools/test_halo_continue.gd",
	"tools/test_fixed_ring.gd",
	"tools/test_backtrack_seams.gd",
	"tools/smoke_gen.gd",
]


func _init() -> void:
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	var project := ProjectSettings.globalize_path("res://")

	for script_path in TESTS:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL: test suite exceeded %ds before %s" % [DEADLINE_MS / 1000, script_path])
			quit(1)
			return

		var t0 := Time.get_ticks_msec()
		var exit_code := OS.execute(
			OS.get_executable_path(),
			["--headless", "--path", project, "-s", script_path],
			[],
			true,
			false
		)
		var ms := Time.get_ticks_msec() - t0
		if exit_code != 0:
			push_error("FAIL: %s exit=%d ms=%d" % [script_path, exit_code, ms])
			quit(1)
			return
		print("PASS %s ms=%d" % [script_path, ms])

	print("PASS all tests within %ds budget" % (DEADLINE_MS / 1000))
	quit(0)
