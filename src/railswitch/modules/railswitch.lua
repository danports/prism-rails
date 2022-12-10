package.path = package.path .. ";/modules/?;/modules/?.lua;/modules/?/init.lua"
local events = require("events")
local net = require("net")
local serializer = require("serializer")
local wire = require("wire")
local minecartevents = require("minecartevents")
local railnetwork = require("railnetwork")
local autostartup = require("autostartup")
local autoupdater = require("autoupdater")
local railswitch = {}

function railswitch.setSwitchOutput(value)
	print(string.format("Setting switch to %s", tostring(value)))
	wire.setOutput(config.switch, value)
	if config.slowTrack ~= nil then
		wire.setOutput(config.slowTrack, not value)
	end
end

function railswitch.setSwitch(update)
	local value = update.state
	railswitch.setSwitchOutput(value)
	state.switch = value
	serializer.writeToFile("state", state)
end

function railswitch.minecartDetected(eventName, detector, minecartType, minecartName)
	print(string.format("Minecart detected: %s", minecartName))
	local msg = {
		switchId = config.switchId,
		location = config.location,
		minecartName = minecartName,
		minecartType = minecartType
	}
	net.sendMessage("railrouter://", "minecartDetected", msg)
end

function railswitch.onStartup()
	net.registerMessageHandler("setSwitch", railswitch.setSwitch)
	events.registerHandler("char", function(evt, pressed)
		if pressed == "d" then
			net.sendMessage(config.router, "switchOffline", {id = config.switchId})
			print(string.format("Switch %i offline", config.switchId))
			return false
		end
		if pressed == "u" then
			autoupdater.updatePackages(true)
		end
	end)
	minecartevents.registerMinecartHandler(railswitch.minecartDetected)
	autoupdater.initialize()

	dofile("config")
	print(string.format("RailSwitchOS: Switch %i (%s) listening on %s...",
		config.switchId, railnetwork.formatLocation(config.location), net.openModem(config.modem)))

	state = serializer.readFromFile("state")
	if state.switch == nil then
		state.switch = false
	end
	railswitch.setSwitchOutput(state.switch)

	autostartup.waitForDependencies({{type = "dns", address = config.router}})
	net.sendMessage(config.router, "switchOnline", {
		id = config.switchId,
		computerId = os.computerID(),
		location = config.location,
		continuesTo = config.continuesTo,
		divergesTo = config.divergesTo
	})
	print(string.format("Switch %i online", config.switchId))

	events.runMessageLoop()
end

return railswitch
