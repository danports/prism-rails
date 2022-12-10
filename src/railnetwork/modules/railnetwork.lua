package.path = package.path .. ";/modules/?;/modules/?.lua;/modules/?/init.lua"
local graph = require("graph")
local railnetwork = {}

-- TODO: Make this into an object with a metatable.
function railnetwork.railnetwork.formatLocation(location)
    if location then
        return string.format("%s@%i", location.line, location.position)
    end
    return "???"
end

function railnetwork.parseLocation(text)
    local line, position = text:match("^(.+)@(.+)$")
    position = tonumber(position)
    if line ~= nil and position ~= nil then
        return {line = line, position = position}
    end
end

function railnetwork.locationsMatch(a, b)
    return a.line == b.line and a.position == b.position
end

function railnetwork.distanceBetween(a, b)
    if a.line == b.line then
        return math.abs(a.position - b.position)
    end
    return 1 -- There's really no way to know.
end

local RailNetwork = {}
function railnetwork.RailNetwork:addNode(id, node)
    self.nodes[id] = node
    self:clearGraph()
end

function railnetwork.RailNetwork:removeNode(id)
    self.nodes[id] = nil
    self:clearGraph()
end

function railnetwork.RailNetwork:addLine(id, line)
    self.lines[id] = line
    self:clearGraph()
end

function railnetwork.RailNetwork:removeLine(id)
    self.lines[id] = nil
    self:clearGraph()
end

function railnetwork.RailNetwork:clearGraph()
    self.graph = nil
    self.lineNodes = nil
    self.tags = nil
end

function railnetwork.RailNetwork:buildGraph()
    if self.graph then
        return
    end
    local lines = {}
    function railnetwork.establishNode(location, node)
        local lineName = location.line
        local line = lines[lineName]
        if not line then
            line = {}
            lines[lineName] = line
        end
        local existing = line[location.position]
        if node and existing and existing.edges then
            error(string.format("Conflicting nodes defined at %s", railnetwork.railnetwork.formatLocation(location)))
        end
        line[location.position] = node or existing or {location = location}
        return line[location.position]
    end

    local allTags = {}
    function railnetwork.establishTags(tags)
        for tag in pairs(tags or {}) do
            allTags[tag] = true
        end
    end

    for _, line in pairs(self.lines) do
        railnetwork.establishTags(line.tags)
    end

    for _, node in pairs(self.nodes) do
        node.edges = {}
        for _, connection in pairs(node.connections or {}) do
            railnetwork.establishNode(connection.location)
            railnetwork.establishTags(connection.tags)
            connection.destination = railnetwork.railnetwork.formatLocation(connection.location)
            connection.distance = connection.distance or railnetwork.distanceBetween(node.location, connection.location)
            if node.location.line == connection.location.line and self.lines[node.location.line] then
                connection.inheritedTags = self.lines[node.location.line].tags
            end
            table.insert(node.edges, connection)
        end
        railnetwork.establishNode(node.location, node)
    end

    local graph = {}
    local locationsByLine = {}
    for line, lineNodes in pairs(lines) do
        local lineTags
        if self.lines[line] then
            lineTags = self.lines[line].tags
        end
        local sorted = {}
        local positions = {}
        locationsByLine[line] = positions
        for _, node in pairs(lineNodes) do
            table.insert(sorted, node)
        end
        table.sort(sorted, function(a, b)
            return a.location.position < b.location.position
        end)
        for index, node in ipairs(sorted) do
            graph[railnetwork.railnetwork.formatLocation(node.location)] = node
            table.insert(positions, node.location)
            node.edges = node.edges or {}
            -- If direction is not set or is 0, we assume the line does not continue beyond this point.
            local direction = node.location.direction
            if direction and direction > 0 and index < #sorted then
                table.insert(node.edges, {
                    destination = railnetwork.railnetwork.formatLocation(sorted[index + 1].location),
                    distance = railnetwork.distanceBetween(node.location, sorted[index + 1].location),
                    inheritedTags = lineTags
                })
            elseif direction and direction < 0 and index > 1 then
                table.insert(node.edges, {
                    destination = railnetwork.railnetwork.formatLocation(sorted[index - 1].location),
                    distance = railnetwork.distanceBetween(node.location, sorted[index - 1].location),
                    inheritedTags = lineTags
                })
            end
        end
    end

    self.graph = graph
    self.lineNodes = locationsByLine
    self.tags = allTags
end

function railnetwork.RailNetwork:findClosestNode(location)
    if not location then
        return nil, "Location not specified"
    end
    if not location.line then
        return nil, "Line not specified"
    end
    if location.position == nil then
        return nil, "Position not specified"
    end
    self:buildGraph()
    if self.graph[railnetwork.railnetwork.formatLocation(location)] then
        return location
    end
    local line = self.lineNodes[location.line]
    if not line or not next(line) then
        return nil, string.format("Line %s has no defined locations", location.line)
    end
    if location.position < line[1].position then
        if line[1].direction and line[1].direction < 0 then
            return line[1]
        else
            return nil, string.format("Inaccessible location %s: first position %i on this line does not connect here", railnetwork.railnetwork.formatLocation(location), line[1].position)
        end
    end
    for index, lineLocation in ipairs(line) do
        if location.position == lineLocation.position then
            return lineLocation
        elseif location.position > lineLocation.position then
            local nextLocation = line[index + 1]
            if nextLocation then
                if location.position < nextLocation.position then
                    -- Our desired location is in between this node and the next one.
                    if lineLocation.direction and lineLocation.direction > 0 then
                        return lineLocation
                    elseif nextLocation.direction and nextLocation.direction < 0 then
                        return nextLocation
                    else
                        return nil, string.format("Inaccessible location %s: neighboring positions %i and %i on this line do not connect here", railnetwork.railnetwork.formatLocation(location), lineLocation.position, nextLocation.position)
                    end
                end
            else
                -- End of the line!
                if lineLocation.direction and lineLocation.direction > 0 then
                    return lineLocation
                else
                    return nil, string.format("Inaccessible location %s: last position %i on this line does not connect here", railnetwork.railnetwork.formatLocation(location), lineLocation.position)
                end
            end
        end
    end
end

function railnetwork.RailNetwork:findRoute(trip)
    local originNode, originError = self:findClosestNode(trip.origin)
    if not originNode then
        return nil, string.format("Unable to find rail network location for origin %s: %s", railnetwork.railnetwork.formatLocation(trip.origin), originError)
    end
    local destinationNode, destinationError = self:findClosestNode(trip.destination)
    if not destinationNode then
        return nil, string.format("Unable to find rail network location for destination %s: %s", railnetwork.railnetwork.formatLocation(trip.destination), destinationError)
    end
    function railnetwork.edgeWeight(edge)
        local distance = edge.distance or 1
        if trip.tags then
            local edgeTags = edge.tags or {}
            local inheritedTags = edge.inheritedTags or {}
            for tag, weight in pairs(trip.tags) do
                if weight then
                    distance = distance * (edgeTags[tag] or inheritedTags[tag] or weight)
                elseif edgeTags[tag] or inheritedTags[tag] then
                    return math.huge
                end
            end
        end
        return distance
    end
    local path = graph.shortestPath(self.graph, {origin = railnetwork.formatLocation(originNode), destination = railnetwork.formatLocation(destinationNode)}, railnetwork.edgeWeight)
    if not path then
        return nil, string.format("No path exists between origin %s and destination %s; did you misconfigure a switch or station?", railnetwork.formatLocation(originNode), railnetwork.formatLocation(destinationNode))
    end
    if not railnetwork.locationsMatch(trip.origin, originNode) then
        -- Add an edge for the segment between the origin and the first location in the network.
        path.origin = railnetwork.formatLocation(trip.origin)
        table.insert(path.edges, 1, {
            edge = {destination = railnetwork.formatLocation(originNode)},
            weight = 1
        })
    end
    if not railnetwork.locationsMatch(trip.destination, destinationNode) then
        -- Add an edge for the segment between the last location in the network and the final destination.
        path.destination = railnetwork.formatLocation(trip.destination)
        table.insert(path.edges, {
            edge = {destination = railnetwork.formatLocation(trip.destination)},
            weight = 1
        })
    end
    return path
end

function railnetwork._routeMatches(a, b)
    if #a.edges ~= #b.edges then
        return false
    end
    for key, edge in ipairs(a.edges) do
        if edge.destination ~= b.edges[key].destination then
            return false
        end
    end
    return true
end

function railnetwork.findMatchingRoute(routes, route)
    for key, existing in pairs(routes) do
        if railnetwork._routeMatches(existing, route) then
            return key, existing
        end
    end
end

function railnetwork.RailNetwork:findRoutes(trip, tagWeight)
    self:buildGraph()
    local routes = {}
    function railnetwork.addRoute(trip, tripTags)
        trip.tags = tripTags
        local route, routeError = self:findRoute(trip) -- TODO: Handle errors
        if route then
            local key = railnetwork.findMatchingRoute(routes, route)
            if key then
                table.insert(key, tripTags)
            else
                routes[{tripTags}] = route
            end
        end
        trip.tags = nil
    end

    railnetwork.addRoute(trip, {})
    tagWeight = tagWeight or 2
    for tag in pairs(self.tags) do
        railnetwork.addRoute(trip, {[tag] = tagWeight})
    end
    return routes
end

local metatable = {
    __index = RailNetwork
}

function railnetwork.new()
    return setmetatable({lines = {}, nodes = {}}, metatable)
end

return railnetwork
