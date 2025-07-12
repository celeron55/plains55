-- plains55: mapgen mod for Luanti
-- To use: Set mapgen to "singlenode" in world creation or minetest.conf (mg_name = singlenode)

local modpath = minetest.get_modpath(minetest.get_current_modname())

-- Load modules
dofile(modpath .. "/params.lua")  -- Loaded first as dependency
dofile(modpath .. "/mapgen.lua")
dofile(modpath .. "/preview.lua")
