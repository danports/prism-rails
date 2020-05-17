config = {
	switchId = 0,
	router = "railrouter://",
	location = {
		line = "Line",
		position = 0,
		-- Define continuesTo instead if switch continues to a different line.
		direction = -1
	},
	divergesTo = {
		location = {
			line = "Line",
			position = 0,
			direction = 1
		}
		-- Optional: Define distance and tags.
	},
	switch = {side = "back"},
	slowTrack = {side = "right"}
}