os.loadAPI("apis/events")
os.loadAPI("apis/net")
os.loadAPI("apis/serializer")
os.loadAPI("apis/wire")
os.loadAPI("apis/minecartevents")
os.loadAPI("apis/railnetwork")
os.loadAPI("apis/autostartup")
os.loadAPI("apis/autoupdater")

function setSwitchOutput(value)
	print(string.format("Setting switch to %s", tostring(value)))
	wire.setOutput(config.switch, value)
	if config.slowTrack ~= nil then
		wire.setOutput(config.slowTrack, not value)
	end
end

function setSwitch(update)
	local value = update.state
	setSwitchOutput(value)
	state.switch = value
	serializer.writeToFile("state", state)
end

function minecartDetected(eventName, detector, minecartType, minecartName)
	print(string.format("Minecart detected: %s", minecartName))
	local msg = {
		switchId = config.switchId,
		location = config.location,
		minecartName = minecartName,
		minecartType = minecartType
	}
	net.sendMessage("railrouter://", "minecartDetected", msg)
end

function onStartup()
	net.registerMessageHandler("setSwitch", setSwitch)
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
	minecartevents.registerMinecartHandler(minecartDetected)
	autoupdater.initialize()
	
	dofile("config")
	print(string.format("RailSwitchOS: Switch %i (%s) listening on %s...", 
		config.switchId, railnetwork.formatLocation(config.location), net.openModem(config.modem)))

	state = serializer.readFromFile("state")
	if state.switch == nil then
		state.switch = false
	end
	setSwitchOutput(state.switch)
	
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

onStartup()