package.path = package.path .. ";/modules/?;/modules/?.lua;/modules/?/init.lua"
local railstation = require("railstation")

railstation.onStartup()
