config = {
	router = "railrouter://",
	-- Omit stationId and stationName for pocket stations.
	stationId = 0,
	stationName = "[Station Name]",
	features = {
		passenger = {
			cartsIn = {
				-- Omit this section for pocket stations.
				detector = "", 
				location = {
					line = "[Station Arriving Line]", 
					position = 0,
					direction = 1
				}
			},
			cartsOut = {
				-- Omit these and set minecartName instead for pocket stations.
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