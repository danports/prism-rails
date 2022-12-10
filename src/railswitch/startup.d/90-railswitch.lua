package.path = package.path .. ";/modules/?;/modules/?.lua;/modules/?/init.lua"
local railswitch = require("railswitch")

railswitch.onStartup()
