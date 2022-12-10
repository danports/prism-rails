package.path = package.path .. ";/modules/?;/modules/?.lua;/modules/?/init.lua"
local events = require("events")
local net = require("net")
local serializer = require("serializer")
local wire = require("wire")
local minecartevents = require("minecartevents")
local input = require("input")
local graph = require("graph")
local railnetwork = require("railnetwork")
local autostartup = require("autostartup")
local autoupdater = require("autoupdater")
local railstation = {}

function railstation.requestDeparture(destination)
	local trip = {
		type = "passenger",
		computerId = os.computerID(),
		origin = config.features.passenger.cartsOut.location,
		destination = destination
	}
	
	print(string.format("Requesting %s departure to %s...", trip.type, railnetwork.formatLocation(destination)))
	net.sendMessage(config.router, "newTrip", trip)
end

function railstation.rejectDeparture(trip)
	print(string.format("Departure rejected: %s", trip.rejectionReason))
	railstation.delayedWriteHeader()
end

function railstation.formatTags(tags)
	local parts = {}
	for tag, enabled in pairs(tags) do
		local part = tag
		if not enabled then
			part = "NOT " .. part
		end
		table.insert(parts, part)
	end
	if next(parts) then
		return table.concat(parts, ", ")
	end
	return "normal"
end

function railstation.formatRouteTags(tags)
	local parts = {}
	for _, tags in ipairs(tags) do
		table.insert(parts, railstation.formatTags(tags))
	end
	return table.concat(parts, "; ")
end

function railstation.selectDepartureRoute(trip)
	if not trip.routes then
		railstation.handleDeparture(trip)
		return
	end
	local routeOptions = {}
	for tags, route in pairs(trip.routes) do
		table.insert(routeOptions, tags)
	end
	if #routeOptions == 1 then
		local key, route = next(trip.routes)
		print(string.format("Only one route to %s (%s); preparing departure: %s", 
			railnetwork.formatLocation(trip.destination), railstation.formatRouteTags(routeOptions[1]), graph.formatPath(route)))
		trip.routes = nil
		railstation.handleDeparture(trip)
		return
	end
	local selected = input.menu({
		prompt = "Select your route:",
		items = routeOptions,
		formatter = railstation.formatRouteTags
	})
	if not selected then
		return
	end
	print(string.format("Preparing departure: %s", graph.formatPath(trip.routes[selected])))
	trip.routes = nil
	trip.tags = selected[1]
	railstation.handleDeparture(trip)
end

function railstation.handleDeparture(trip)
	if trip.type ~= "passenger" then
		print(string.format("ERROR: Unrecognized departure type %s; ignoring", trip.type))
		return
	end

	if config.features.passenger.cartsOut.minecartName then
		trip.minecartName = config.features.passenger.cartsOut.minecartName
		net.sendMessage(config.router, "tripDeparted", trip)	
		print(string.format("Please place your %s cart on the rails and take off now. Travel safely and have a great day!", trip.minecartName))
		railstation.delayedWriteHeader()
		return
	end

	if config.features.passenger.cartsOut.dispenser == nil then
		print("Please place your cart on the rails and take off now. Travel safely and have a great day!")
	else
		print("Dispensing cart...")
		wire.setOutput(config.features.passenger.cartsOut.dispenser, true)
		events.setTimer(1, function()
			wire.setOutput(config.features.passenger.cartsOut.dispenser, false)
		end)
		print("Please board your cart now. Travel safely and have a great day!")
	end
	pendingTrip = trip
end

function railstation.writeHeader()
	term.clear()
	term.setCursorPos(1, 1)
	print(string.format("RailStationOS: Listening on %s...", config.modem))
	print()
	if config.stationId ~= nil then
		print(string.format("Welcome to %s (station %i)!", config.stationName, config.stationId))
	end
	print("Press D to depart.")
	print("Press L to dispense liquid.")
end

function railstation.getStationInput(prompt, filter)
	while true do
		print("Enter " .. prompt .. " or 0 to cancel:")
		for i = 1, #stations do
			if filter(i) then
				local locationFlag = ""
				if (i == config.stationId) then
					locationFlag = " [YOU ARE HERE]"
				end
				print(string.format("%i = %s%s", i, stations[i].stationName, locationFlag))
			end
		end
		local destination = tonumber(read())

		if destination == nil then
			print("Please enter a number.")
		elseif destination == 0 then
			return nil
		elseif stations[destination] == nil or not filter(destination) then
			print("Please enter a valid destination.")
		else
			return destination
		end
	end
end

function railstation.getNumericInput(prompt)
	-- TODO: Use input.request instead here.
	while true do
		print("Enter " .. prompt .. " or 0 to cancel:")
		local value = tonumber(read())

		if value == nil or value < 0 then
			print("Please enter a non-negative number.")
		elseif value == 0 then
			return nil
		else
			return value
		end
	end
end

function railstation.handleDepartureRequest()
	for _, station in ipairs(stations) do
		print(string.format("%i = %s", station.stationId, station.stationName))
	end
    local destination = input.request({
        prompt = "Destination station or location (e.g. main@500):",
		validator = function(text)
			local stationId = tonumber(text)
			if stationId ~= nil then
				local station = stations[stationId]
				if station then
					return station.features.passenger.cartsIn.location
				else
					return nil, string.format("Station %i does not exist.", stationId)
				end
			end
			return railnetwork.parseLocation(text)
		end,
        invalidPrompt = "Invalid destination."
    })
	if destination == nil then
		railstation.writeHeader()
		return
	end

	railstation.requestDeparture(destination)
end

function railstation.handleLavaRequest()
	local origin = railstation.getStationInput("the station to dispense the lava from",
		function(station)
			return stations[station].features.lava ~= nil and
				stations[station].features.lava.cartsOut ~= nil
		end)
	if origin == nil then
		railstation.writeHeader()
		return
	end

	local destination = railstation.getStationInput("the station to deliver the lava to",
		function(station)
			if station == origin then
				return false
			else
				return stations[station].features.lava ~= nil and
					stations[station].features.lava.cartsIn ~= nil
			end
		end)
	if destination == nil then
		railstation.writeHeader()
		return
	end

	local count = railstation.getNumericInput("the number of tank carts to deliver")
	if count == nil then
		railstation.writeHeader()
		return
	end

	local request = {
		class = "lava",
		source = origin,
		destination = destination,
		requestType = "lava",
		count = count
	}
	net.sendMessage(config.router, "newRequest", request)

	print("Lava request sent. Have a great day!")
	railstation.delayedWriteHeader()
end

function railstation.delayedWriteHeader()
	events.setTimer(5, railstation.writeHeader)
end

function railstation.handleStationUpdate(data)
	stations = data
	serializer.writeToFile("stations", stations)
	print("Station list updated.")
end

function railstation.minecartDetected(eventName, detector, minecartType, minecartName)
	if detector == config.features.passenger.cartsIn.detector then
		print(string.format("New arrival: %s", minecartName))
		local msg = {
			location = config.features.passenger.cartsIn.location,
			minecartName = minecartName,
			minecartType = minecartType
		}
		net.sendMessage(config.router, "minecartDetected", msg)
		return
	end
	if detector == config.features.passenger.cartsOut.detector then
		if pendingTrip == nil then
			print("ERROR: Outgoing minecart detected but no trip is pending; ignoring detection")
			return
		end
		print(string.format("%s departing!", minecartName))
		wire.setOutput(config.features.passenger.cartsOut.dispenser, false)

		pendingTrip.minecartName = minecartName
		pendingTrip.minecartType = minecartType
		net.sendMessage(config.router, "tripDeparted", pendingTrip)
		pendingTrip = nil

		railstation.delayedWriteHeader()
	end
end

function railstation.onStartup()
	autoupdater.initialize()
	net.registerMessageHandler("allowDeparture", railstation.selectDepartureRoute)
	net.registerMessageHandler("rejectDeparture", railstation.rejectDeparture)
	net.registerMessageHandler("stationUpdate", railstation.handleStationUpdate)
	minecartevents.registerMinecartHandler(minecartDetected)
	events.registerHandler("char", function(evt, pressed)
		if pressed == "d" then
			railstation.handleDepartureRequest()
		end
		if pressed == "l" then
			railstation.handleLavaRequest()
		end
		if pressed == "u" then
			autoupdater.updatePackages(true)
		end
	end)

	dofile("config")
	config.features.passenger.computerId = os.computerID()
	config.modem = net.openModem(config.modem)
	stations = serializer.readFromFile("stations")

	railstation.writeHeader()

	autostartup.waitForDependencies({{type = "dns", address = config.router}})
	if config.stationId == nil then
		print("Requesting station list...")
		net.sendMessage(config.router, "getStations", {})
	else
		net.sendMessage(config.router, "stationOnline", config)
		print(string.format("Station %i online", config.stationId))
	end

	events.runMessageLoop()
end

return railstation
