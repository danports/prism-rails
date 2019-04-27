config = {
	stationId = 0,
	stationName = "[Station Name]",
	router = "railrouter://",
	features = {
		passenger = {
			cartsIn = {
				detector = "", 
				location = {
					line = "[Station Arriving Line]", 
					position = 0,
					direction = 1
				}
			},
			cartsOut = {
				detector = "", 
				dispenser = {side = "back"}, 
				location = {
					line = "[Station Departing Line]", 
					position = 0,
					direction = -1
				}
			}
		}
	}
}