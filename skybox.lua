-- plains55: Dynamic skybox with rough horizon silhouette

local modpath = minetest.get_modpath(minetest.get_current_modname())
local plains55 = dofile(modpath .. "/params.lua")

local last_positions = {}

local UPDATE_DISTANCE = 50  -- Update when player moves this far
local TEXTURE_WIDTH = 64
local TEXTURE_HEIGHT = 512
local SAMPLE_STEP = 50  -- Interval for sampling
local MIN_SAMPLE_DISTANCE = 300
local MAX_SAMPLE_DISTANCE = 3000
local VERTICAL_SCALE = 1.0

-- Hardcoded day sky colors for gradient (adjust as needed; hex to RGB)
local SKY_TOP_R, SKY_TOP_G, SKY_TOP_B = 97, 181, 245  -- #61b5f5
local HORIZON_BOTTOM_R, HORIZON_BOTTOM_G, HORIZON_BOTTOM_B = 144, 211, 246  -- #90d3f6

-- Constant silhouette color (light gray, almost white, for fog-like integration; adjust as needed)
local CLOSE_R, CLOSE_G, CLOSE_B = 200, 200, 200  -- #C8C8C8
local FAR_R, FAR_G, FAR_B = HORIZON_BOTTOM_R, HORIZON_BOTTOM_G, HORIZON_BOTTOM_B

local CLOSE_COLOR = 0xFF000000 + CLOSE_R * 0x10000 + CLOSE_G * 0x100 + CLOSE_B

-- Precompute 1x1 textures for top and bottom
local top_color = 0xFF000000 + SKY_TOP_R * 0x10000 + SKY_TOP_G * 0x100 + SKY_TOP_B
local top_pixels = {top_color}
local top_png = minetest.encode_png(1, 1, top_pixels)
local top_base64 = minetest.encode_base64(top_png)
local top_tex = "[png:" .. top_base64

local bottom_color = CLOSE_COLOR
local bottom_pixels = {bottom_color}
local bottom_png = minetest.encode_png(1, 1, bottom_pixels)
local bottom_base64 = minetest.encode_base64(bottom_png)
local bottom_tex = "[png:" .. bottom_base64

-- Generate a side texture for a given world direction (angle_base in degrees: 0=+X, 90=+Z, etc.)
local function generate_side_texture(pos, angle_base)
    local pixels = {}
    local eye_y = pos.y + 1.625  -- Approximate player eye height
    local horizon_py = math.floor(TEXTURE_HEIGHT / 2)  -- Horizon at middle

    -- Draw row by row (vertical gradient background first)
    for py = 1, TEXTURE_HEIGHT do
        -- Compute background gradient color for this row (full height gradient, top sky to bottom horizon)
        local grad_frac = (py - 1) / (TEXTURE_HEIGHT - 1)  -- 0 at top, 1 at bottom
        local bg_r = math.floor(SKY_TOP_R * (1 - grad_frac) + HORIZON_BOTTOM_R * grad_frac)
        local bg_g = math.floor(SKY_TOP_G * (1 - grad_frac) + HORIZON_BOTTOM_G * grad_frac)
        local bg_b = math.floor(SKY_TOP_B * (1 - grad_frac) + HORIZON_BOTTOM_B * grad_frac)
        local bg_color = 0xFF000000 + bg_r * 0x10000 + bg_g * 0x100 + bg_b

        for px = 1, TEXTURE_WIDTH do
            table.insert(pixels, bg_color)
        end
    end

    -- Now overlay the silhouette layers from far to near
    for px = 1, TEXTURE_WIDTH do
        local frac = 0.5 - (px - 0.5) / TEXTURE_WIDTH  -- Reversed to fix horizontal mirroring: now 0.5 to -0.5 as px increases
        local angle_deg = angle_base + frac * 90  -- Span 90 degrees per side, reversed direction
        local angle_rad = math.rad(angle_deg)
        local dx = math.cos(angle_rad)
        local dz = math.sin(angle_rad)

        -- Find the max theta and its dist (the min dist with that theta, as closest visible)
        local max_theta = 0
        local min_dist_for_max = MAX_SAMPLE_DISTANCE
        for dist = MIN_SAMPLE_DISTANCE, MAX_SAMPLE_DISTANCE, SAMPLE_STEP do
            local tx = pos.x + dist * dx
            local tz = pos.z + dist * dz
            local th = plains55.get_height_at(tx, tz, false)

            local delta_h = th - eye_y
            if delta_h < 0 then delta_h = 0 end

            local theta = math.atan(delta_h / dist)
            if theta > max_theta then
                max_theta = theta
                min_dist_for_max = dist
            end
        end

        -- Compute blend factor based on the dist of the visible peak
        local blend_frac = (min_dist_for_max - MIN_SAMPLE_DISTANCE) / (MAX_SAMPLE_DISTANCE - MIN_SAMPLE_DISTANCE)

        local layer_r = math.floor(CLOSE_R * (1 - blend_frac) + FAR_R * blend_frac)
        local layer_g = math.floor(CLOSE_G * (1 - blend_frac) + FAR_G * blend_frac)
        local layer_b = math.floor(CLOSE_B * (1 - blend_frac) + FAR_B * blend_frac)
        local layer_color = 0xFF000000 + layer_r * 0x10000 + layer_g * 0x100 + layer_b

        -- Compute the height py
        local scaled_pixels = math.floor((math.deg(max_theta) / 90) * (TEXTURE_HEIGHT / 2) * VERTICAL_SCALE)
        local sil_start_py = horizon_py - scaled_pixels
        local draw_start_py = math.max(1, sil_start_py)

        -- Fill from draw_start_py to horizon with the layer color
        for py = draw_start_py, horizon_py do
            local vi = (py - 1) * TEXTURE_WIDTH + px
            pixels[vi] = layer_color
        end

        -- Fill below horizon with close color
        for py = horizon_py + 1, TEXTURE_HEIGHT do
            local vi = (py - 1) * TEXTURE_WIDTH + px
            pixels[vi] = CLOSE_COLOR
        end
    end

    local png_data = minetest.encode_png(TEXTURE_WIDTH, TEXTURE_HEIGHT, pixels)
    local base64 = minetest.encode_base64(png_data)
    return "[png:" .. base64
end

-- Update the skybox for a player
local function update_player_skybox(player, pos)
    local textures = {
        top_tex,  -- +Y (top)
        bottom_tex,  -- -Y (bottom)
        generate_side_texture(pos, 0),   -- X+ (east)
        generate_side_texture(pos, 180), -- X- (west)
        generate_side_texture(pos, 270), -- Z- (south)
        generate_side_texture(pos, 90),  -- Z+ (north)
    }

    player:set_sky({
        type = "skybox",
        base_color = "#ffffff",
        textures = textures,
        clouds = true,
        sky_color = {  -- Example base sky (adjust as needed)
            day_sky = "#61b5f5",
            day_horizon = "#90d3f6",
            dawn_sky = "#b4bafa",
            dawn_horizon = "#bac1f0",
            night_sky = "#006aff",
            night_horizon = "#4090ff",
            indoors = "#646464",
            fog_sun_tint = "#eeb672",
            fog_moon_tint = "#eee9c9",
            fog_tint_type = "default"
        },
        fog = {
            fog_color = "#c8c8c8",
        },
    })
    player:set_clouds({density = 0})  -- Ensure no clouds interfere
end

-- Global step to check for updates
minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local pos = player:get_pos()
        local last_pos = last_positions[name] or pos
        local dist = vector.distance({x = pos.x, y = 0, z = pos.z}, {x = last_pos.x, y = 0, z = last_pos.z})  -- Ignore Y for distance

        if dist > UPDATE_DISTANCE then
            update_player_skybox(player, pos)
            last_positions[name] = pos
        end
    end
end)

-- Initial setup on join
minetest.register_on_joinplayer(function(player)
    local pos = player:get_pos()
    update_player_skybox(player, pos)
    last_positions[player:get_player_name()] = pos
end)

-- Cleanup on leave
minetest.register_on_leaveplayer(function(player)
    last_positions[player:get_player_name()] = nil
end)
