extends SceneTree

const DEADLINE_MS := 60_000

const TESTS := [
	"tools/validate_setup.gd",
	"tools/test_propagate.gd",
	"tools/test_editor_propagate.gd",
	"tools/test_fixed_27.gd",
	"tools/smoke_gen.gd",
]


func _init() -> void:
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	var project := ProjectSettings.globalize_path("res://")

	for script_path in TESTS:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL: test suite exceeded 60s before %s" % script_path)
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

	print("PASS all tests within 60s budget")
	quit(0)
