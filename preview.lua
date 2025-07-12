-- plains55: Preview generation and command

local modpath = minetest.get_modpath(minetest.get_current_modname())
local plains55 = dofile(modpath .. "/params.lua")

-- Function to generate preview texture
local function generate_preview_texture(center_x, center_z)
    local preview_size = 512  -- Increased for more pixels
    local world_scale = 16  -- Increased to cover more area (~4096x4096 nodes)
    local half = preview_size / 2

    -- Compute pixels
    local pixels = {}
    for py = 1, preview_size do
        for px = 1, preview_size do
            local world_x = center_x + (px - half - 0.5) * world_scale
            local world_z = center_z + (half - py + 0.5) * world_scale  -- Flipped to correct vertical mirroring

            -- Get height using unified function
            local height = plains55.get_height_at(world_x, world_z, false)

            -- Get color using unified function
            local r, g, b = plains55.get_color_for_height(height)

            local color = 0xFF000000 + (r * 0x10000) + (g * 0x100) + b  -- ARGB8
            table.insert(pixels, color)
        end
    end

    -- Encode PNG and base64
    local png_data = minetest.encode_png(preview_size, preview_size, pixels)
    local base64 = minetest.encode_base64(png_data)
    return "[png:" .. base64
end

-- Chat command to show preview
minetest.register_chatcommand("p55", {
    description = "Show 2D terrain preview",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return end

        -- Center on player position
        local pos = player:get_pos()
        local center_x = math.floor(pos.x)
        local center_z = math.floor(pos.z)
        local texture = generate_preview_texture(center_x, center_z)

        -- Calculate area covered
        local preview_size = 512
        local world_scale = 16
        local half = (preview_size / 2) * world_scale
        local x_min = center_x - half
        local x_max = center_x + half
        local z_min = center_z - half
        local z_max = center_z + half
        local area_label = string.format("Area: x=%d to %d, z=%d to %d", x_min, x_max, z_min, z_max)

        -- Formspec
        local form = "size[9,7]" ..
                     "label[0.25,0.25;Terrain Preview]" ..
                     "label[0.25,0.5;" .. area_label .. "]" ..
                     "image[0.1,0.1;8.0,8.0;" .. texture .. "]" ..
                     "button_exit[8.0,6.5;1.25,0.75;close;Close]"

        minetest.show_formspec(name, "noise_terrain:preview", form)
    end
})
