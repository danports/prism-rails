os.loadAPI("apis/util")
os.loadAPI("apis/events")

local eventHandlers = util.initializeGlobalTable("minecartEventHandlers")
local lastMinecartEvent = util.initializeGlobalTable("lastMinecartEvent")

function registerMinecartHandler(handler)
	eventHandlers["minecart"] = handler
end

function handleMinecartEvent(eventName, detector, minecartType, minecartName, ...)
	local timestamp = os.clock()
	-- The entire point of this library is to eliminate the duplicate minecarts events that the digital detector sometimes fires.
	if lastMinecartEvent.minecartName == minecartName and lastMinecartEvent.minecartType == minecartType and (timestamp - lastMinecartEvent.timestamp) < 1 then
		return
	end
	
	-- Setting timers doesn't seem to work here (the timer event is never fired), so we use timestamps instead.
	lastMinecartEvent.minecartName = minecartName
	lastMinecartEvent.minecartType = minecartType
	lastMinecartEvent.timestamp = timestamp
	
	local handler = eventHandlers["minecart"]
	if handler ~= nil then
		return handler(eventName, detector, minecartType, minecartName, ...)
	end
end

events.registerHandler("minecart", handleMinecartEvent)