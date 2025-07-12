-- plains55: Dynamic skybox with rough horizon silhouette

local modpath = minetest.get_modpath(minetest.get_current_modname())
local plains55 = dofile(modpath .. "/params.lua")

local last_positions = {}

local UPDATE_DISTANCE = 100  -- Update when player moves this far
local TEXTURE_WIDTH = 128
local TEXTURE_HEIGHT = 128
local SAMPLE_STEP = 50  -- Interval for sampling
local MIN_SAMPLE_DISTANCE = 300
local MAX_SAMPLE_DISTANCE = 4000
local VERTICAL_SCALE = 1.0

-- Hardcoded day sky colors for gradient (adjust as needed; hex to RGB)
local SKY_TOP_R, SKY_TOP_G, SKY_TOP_B = 97, 181, 245  -- #61b5f5
local HORIZON_BOTTOM_R, HORIZON_BOTTOM_G, HORIZON_BOTTOM_B = 144, 211, 246  -- #90d3f6

-- Constant silhouette color (light gray, almost white, for fog-like integration; adjust as needed)
local SILHOUETTE_R, SILHOUETTE_G, SILHOUETTE_B = 200, 200, 200  -- #C8C8C8
local SILHOUETTE_COLOR = 0xFF000000 + SILHOUETTE_R * 0x10000 + SILHOUETTE_G * 0x100 + SILHOUETTE_B

-- Precompute 1x1 textures for top and bottom
local top_color = 0xFF000000 + SKY_TOP_R * 0x10000 + SKY_TOP_G * 0x100 + SKY_TOP_B
local top_pixels = {top_color}
local top_png = minetest.encode_png(1, 1, top_pixels)
local top_base64 = minetest.encode_base64(top_png)
local top_tex = "[png:" .. top_base64

local bottom_color = SILHOUETTE_COLOR
local bottom_pixels = {bottom_color}
local bottom_png = minetest.encode_png(1, 1, bottom_pixels)
local bottom_base64 = minetest.encode_base64(bottom_png)
local bottom_tex = "[png:" .. bottom_base64

-- Generate a side texture for a given world direction (angle_base in degrees: 0=+X, 90=+Z, etc.)
local function generate_side_texture(pos, angle_base)
    local pixels = {}
    local eye_y = pos.y + 1.625  -- Approximate player eye height
    local horizon_py = math.floor(TEXTURE_HEIGHT / 2)  -- Horizon at middle

    -- Precompute silhouette start py (above horizon) for each column
    local sil_starts = {}
    for px = 1, TEXTURE_WIDTH do
        local frac = (px - 0.5) / TEXTURE_WIDTH - 0.5  -- -0.5 to 0.5
        local angle_deg = angle_base + frac * 90  -- Span 90 degrees per side
        local angle_rad = math.rad(angle_deg)
        local dx = math.cos(angle_rad)
        local dz = math.sin(angle_rad)

        local max_theta = 0
        for dist = MIN_SAMPLE_DISTANCE, MAX_SAMPLE_DISTANCE, SAMPLE_STEP do
            local tx = pos.x + dist * dx
            local tz = pos.z + dist * dz
            local th = plains55.get_height_at(tx, tz, false)

            local delta_h = th - eye_y
            if delta_h < 0 then delta_h = 0 end

            local theta = math.atan(delta_h / dist)
            if theta > max_theta then
                max_theta = theta
            end
        end

        -- Compute scaled pixels above horizon
        local scaled_pixels = math.floor((math.deg(max_theta) / 90) * (TEXTURE_HEIGHT / 2) * VERTICAL_SCALE)
        local sil_start_py = horizon_py - scaled_pixels
        sil_starts[px] = math.max(1, sil_start_py)
    end

    -- Draw row by row (vertical gradient and silhouette)
    for py = 1, TEXTURE_HEIGHT do
        -- Compute background gradient color for this row (full height gradient, top sky to bottom horizon)
        local grad_frac = (py - 1) / (TEXTURE_HEIGHT - 1)  -- 0 at top, 1 at bottom
        local bg_r = math.floor(SKY_TOP_R * (1 - grad_frac) + HORIZON_BOTTOM_R * grad_frac)
        local bg_g = math.floor(SKY_TOP_G * (1 - grad_frac) + HORIZON_BOTTOM_G * grad_frac)
        local bg_b = math.floor(SKY_TOP_B * (1 - grad_frac) + HORIZON_BOTTOM_B * grad_frac)
        local bg_color = 0xFF000000 + bg_r * 0x10000 + bg_g * 0x100 + bg_b

        for px = 1, TEXTURE_WIDTH do
            if py >= sil_starts[px] and py <= horizon_py then
                -- Silhouette above horizon: constant color
                table.insert(pixels, SILHOUETTE_COLOR)
            elseif py > horizon_py then
                -- Below horizon: constant color for ground
                table.insert(pixels, SILHOUETTE_COLOR)
            else
                -- Above silhouette: background
                table.insert(pixels, bg_color)
            end
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
        textures = textures,
        clouds = false,  -- Disable clouds to avoid occlusion
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
