-- Explicit requires keep every preset's Lua dependencies visible to Bob.
local gtao = require("drp.features.gtao.gtao")
local clustered = require("drp.features.clustered.clustered")
local hdr = require("drp.features.hdr.hdr")

local M = {}

function M.default()
	return { gtao, clustered, hdr }
end

function M.compatibility()
	return { gtao, hdr }
end

return M
