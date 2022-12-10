package.path = package.path .. ";/modules/?;/modules/?.lua;/modules/?/init.lua"
local log = require("log")
local events = require("events")
local net = require("net")
local dns = require("dns")
local serializer = require("serializer")
local railnetwork = require("railnetwork")
local autoupdater = require("autoupdater")
local railrouter = {}

function railrouter.getStationComputerId(station, feature)
	local station = stations[station]
	if station == nil then
		return nil
	end
	local featureConfig = station.features[feature]
	if featureConfig == nil then
		return nil
	end
	return featureConfig.computerId
end

function railrouter.notifyNewRequest(request)
	print(string.format("Sending new %s request to station %i", request.class, request.source))
	local computerId = railrouter.getStationComputerId(request.source, request.class)
	if computerId == nil then
		log.err(string.format("Sending request to station %i but %s computer ID not found; discarding request", request.source, request.class))
		return
	end
	net.sendMessage(computerId, "newRequest", request)
end

function railrouter.mergeTables(a, b)
	for key, value in pairs(b) do
		if a[key] == nil or type(a[key]) ~= "table" or type(value) ~= "table" then
			a[key] = value
		else
			railrouter.mergeTables(a[key], value)
		end
	end
end

function railrouter.updateStation(station)
	log.info(string.format("Updating station %i", station.stationId))
	if stations[station.stationId] == nil then
		stations[station.stationId] = {}
	end
	railrouter.mergeTables(stations[station.stationId], station)
	railrouter.addStationToNetwork(station)
	railrouter.stationsChanged()
end

function railrouter.stationsChanged()
	serializer.writeToFile("stations", stations)

	for id in pairs(stations) do
		local computerId = railrouter.getStationComputerId(id, "passenger")
		if computerId ~= nil then
			log.info(string.format("Sending station update to %i at station %i", computerId, id))
			net.sendMessage(computerId, "stationUpdate", stations)
		end
	end
end

function railrouter.sendStationList(_, sender)
	log.info(string.format("Sending station list to %i", sender))
	net.sendMessage(sender, "stationUpdate", stations)
end

function railrouter.removeStation(station)
	log.info(string.format("Removing station %i", station.stationId))
	stations[station.stationId] = nil
	network:removeNode(railrouter.getStationNode(station.stationId, false))
	network:removeNode(railrouter.getStationNode(station.stationId, true))
	railrouter.stationsChanged()
end

function railrouter.validateTrip(trip)
	if trip.origin and trip.destination then
		local routes = network:findRoutes(trip)
		if next(routes) then
			trip.routes = routes
			return true
		end
        return nil, string.format("No routes exist between origin %s and destination %s; did you misconfigure a switch or station?", railnetwork.formatLocation(trip.origin), railnetwork.formatLocation(trip.destination))
	end
	-- We can only check whether the destination is valid.
	return network:findClosestNode(trip.destination)
end

function railrouter.checkTrip(trip)
	log.info(string.format("New trip: %s at %s departing for %s", trip.type, railnetwork.formatLocation(trip.origin), railnetwork.formatLocation(trip.destination)))

	local result, tripError = railrouter.validateTrip(trip)
	if result then
		net.sendMessage(trip.computerId, "allowDeparture", trip)
	else
		log.warn(string.format("Rejecting trip request: %s", tripError))
		trip.rejectionReason = tripError
		net.sendMessage(trip.computerId, "rejectDeparture", trip)
	end
end

function railrouter.registerTrip(trip)
	log.info(string.format("Departed: %s at %s in %s departing for %s", trip.type, railnetwork.formatLocation(trip.origin), trip.minecartName, railnetwork.formatLocation(trip.destination)))

	trips[trip.minecartName] = trip
	serializer.writeToFile("trips", trips)
end

function railrouter.minecartDetected(detection)
	log.info(string.format("Minecart detected: %s at %s", detection.minecartName, railnetwork.formatLocation(detection.location)))

	local trip = trips[detection.minecartName]
	if trip == nil then
		log.warn(string.format("No trip active for %s; ignoring detection", detection.minecartName))
		return
	end

	if railnetwork.locationsMatch(trip.destination, detection.location) then
		log.info(string.format("Trip to %s completed for %s", railnetwork.formatLocation(trip.destination), detection.minecartName))
		trips[detection.minecartName] = nil
		serializer.writeToFile("trips", trips)
		return
	end

	trip.lastKnownLocation = detection.location
	serializer.writeToFile("trips", trips)

	if detection.switchId == nil then
		-- There's nothing to do here if this location is not a switch.
		return
	end

	local switch = switches[detection.switchId]
	if switch == nil or switch.computerId == nil then
		log.warn(string.format("Ignoring detection: Detection at switch %i, which was not found", detection.switchId))
		return
	end

	local path, pathError = network:findRoute({origin = detection.location, destination = trip.destination, tags = trip.tags})
	if not path then
		log.warn(string.format("Ignoring detection: %s", pathError))
		return
	end

	local edge = path.edges[1]
	if edge == nil then
		log.warn(string.format("Ignoring detection: Path to destination %s is empty", railnetwork.formatLocation(trip.destination)))
		return
	end

	local switchState = edge.edge.switchState or false
	log.info(string.format("Setting switch %i to %s", detection.switchId, tostring(switchState)))
	net.sendMessage(switch.computerId, "setSwitch", {state = switchState})
end

function railrouter.switchOnline(switch)
	log.info(string.format("Switch %i online", switch.id))
	switches[switch.id] = switch
	serializer.writeToFile("switches", switches)
	railrouter.addSwitchToNetwork(switch)
end

function railrouter.switchOffline(switch)
	log.info(string.format("Switch %i offline", switch.id))
	switches[switch.id] = nil
	serializer.writeToFile("switches", switches)
	network:removeNode(railrouter.getSwitchNode(switch.id))
end

function railrouter.getStationNode(id, departing)
	local nodeType = "arrive"
	if departing then
		nodeType = "depart"
	end
	return string.format("S%i-%s", id, nodeType)
end

function railrouter.getSwitchNode(id)
	return string.format("T%i", id)
end

function railrouter.getSwitchConnection(location, switchState)
	if location then
		return {
			location = location.location or location, -- For backwards compatibility with older switches
			switchState = switchState,
			distance = location.distance,
			tags = location.tags,
		}
	end
end

function railrouter.addSwitchToNetwork(switch)
	if switch.continuesTo and switch.location.direction then
		error(string.format("Switch %i defines both continuesTo and location.direction; drop one of these to resolve the conflict", switch.id))
	end
	if not switch.divergesTo then
		error(string.format("Switch %i does not define divergesTo", switch.id))
	end
	network:addNode(railrouter.getSwitchNode(switch.id), {
		location = switch.location,
		connections = {railrouter.getSwitchConnection(switch.divergesTo, true), railrouter.getSwitchConnection(switch.continuesTo, false)},
	})
end

function railrouter.addStationToNetwork(station)
	if not station.features.passenger then
		return
	end
	if station.features.passenger.cartsIn then
		network:addNode(railrouter.getStationNode(station.stationId, false), {location = station.features.passenger.cartsIn.location})
	end
	if station.features.passenger.cartsOut then
		network:addNode(railrouter.getStationNode(station.stationId, true), {location = station.features.passenger.cartsOut.location})
	end
end

function railrouter.buildRailNetwork()
	network = railnetwork.new()
	for _, switch in pairs(switches) do
		railrouter.addSwitchToNetwork(switch)
	end
	for _, station in pairs(stations) do
		railrouter.addStationToNetwork(station)
	end
	for id, line in pairs(lines) do
		network:addLine(id, line)
	end
end

function railrouter.onStartup()
	trips = serializer.readFromFile("trips")
	switches = serializer.readFromFile("switches")
	stations = serializer.readFromFile("stations")
	lines = serializer.readFromFile("lines")
	railnetwork.buildRailNetwork()
	net.registerMessageHandler("newRequest", railnetwork.notifyNewRequest)
	net.registerMessageHandler("stationOnline", railnetwork.updateStation)
	net.registerMessageHandler("stationOffline", railnetwork.removeStation)
	net.registerMessageHandler("newTrip", railnetwork.checkTrip)
	net.registerMessageHandler("tripDeparted", railnetwork.registerTrip)
	net.registerMessageHandler("minecartDetected", minecartDetected)
	net.registerMessageHandler("switchOnline", railnetwork.switchOnline)
	net.registerMessageHandler("switchOffline", railnetwork.switchOffline)
	net.registerRawMessageHandler("getStations", railnetwork.sendStationList)
	autoupdater.initialize()

	dofile("config")
	log.info(string.format("RailRouterOS: Listening on %s...", net.openModem(config.modem)))
	dns.register("railrouter")

	events.runMessageLoop()
end

return railrouter

