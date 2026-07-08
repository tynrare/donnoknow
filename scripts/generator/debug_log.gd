extends RefCounted

const LOG_PATH := "/home/x/code/donnoknow/.cursor/debug-a37e36.log"
const SESSION := "a37e36"

static var enabled := false


static func write(
	hypothesis_id: String,
	location: String,
	message: String,
	data: Dictionary = {},
	run_id: String = "run",
) -> void:
	if not enabled:
		return
	#region agent log
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(
		JSON.stringify(
			{
				"sessionId": SESSION,
				"runId": run_id,
				"hypothesisId": hypothesis_id,
				"location": location,
				"message": message,
				"data": data,
				"timestamp": Time.get_ticks_msec(),
			}
		)
	)
	f.close()
	#endregion
