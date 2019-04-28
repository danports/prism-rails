config = {
	switchId = 0,
	router = "railrouter://",
	location = {
		line = "Line",
		position = 0,
		direction = -1 -- Define continuesTo instead if switch continues to a different line.
	},
	divergesTo = {
		line = "Line",
		position = 0,
		direction = 1
	},
	switch = {side = "back"},
	slowTrack = {side = "right"}
}