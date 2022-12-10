package.path = package.path .. ";/modules/?;/modules/?.lua;/modules/?/init.lua"
local railrouter = require("railrouter")

railrouter.onStartup()
