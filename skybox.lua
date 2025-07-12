-- plains55: Dynamic skybox with rough horizon silhouette

local modpath = minetest.get_modpath(minetest.get_current_modname())
local plains55 = dofile(modpath .. "/params.lua")

local last_positions = {}

local UPDATE_DISTANCE = 80  -- Update when player moves this far
local TEXTURE_WIDTH = 64
local TEXTURE_HEIGHT = 512
local MIN_SAMPLE_DISTANCE = 200
local MAX_SAMPLE_DISTANCE = 4000
local SAMPLE_STEP_ADD = 30  -- Interval for sampling
local SAMPLE_STEP_MULTIPLY = 1.1  -- Interval for sampling
local VERTICAL_SCALE = 2.0  -- This seems to be accurate

-- Hardcoded day sky colors for gradient
local SKY_TOP_R, SKY_TOP_G, SKY_TOP_B = 97, 181, 245  -- #61b5f5
--local HORIZON_BOTTOM_R, HORIZON_BOTTOM_G, HORIZON_BOTTOM_B = 144, 211, 246  -- #90d3f6
--local HORIZON_BOTTOM_R, HORIZON_BOTTOM_G, HORIZON_BOTTOM_B = 0xc8, 0xc8, 0xc8  -- #c8c8c8
--local HORIZON_BOTTOM_R, HORIZON_BOTTOM_G, HORIZON_BOTTOM_B = 0xc8 - 150, 0xc8 - 120, 0xc8 - 50
local HORIZON_BOTTOM_R, HORIZON_BOTTOM_G, HORIZON_BOTTOM_B = 0x42,0x70,0x96
--local HORIZON_BOTTOM_R, HORIZON_BOTTOM_G, HORIZON_BOTTOM_B = 0x06,0x48,0x82

local SKY_BOTTOM_R, SKY_BOTTOM_G, SKY_BOTTOM_B = HORIZON_BOTTOM_R, HORIZON_BOTTOM_G, HORIZON_BOTTOM_B

-- Silhouette color
local CLOSE_R, CLOSE_G, CLOSE_B = HORIZON_BOTTOM_R, HORIZON_BOTTOM_G, HORIZON_BOTTOM_B
--local CLOSE_R, CLOSE_G, CLOSE_B = HORIZON_BOTTOM_R - 60, HORIZON_BOTTOM_G - 40, HORIZON_BOTTOM_B - 20
--local CLOSE_R, CLOSE_G, CLOSE_B = 0x06,0x48,0x82
--local FAR_R, FAR_G, FAR_B = SKY_TOP_R, SKY_TOP_G, SKY_TOP_B
--local FAR_R, FAR_G, FAR_B = SKY_TOP_R + 20, SKY_TOP_G + 10, SKY_TOP_B + 20
--local FAR_R, FAR_G, FAR_B = 0xff, 0xff, 0xff
--local FAR_R, FAR_G, FAR_B = (SKY_TOP_R + 0xff) / 2, (SKY_TOP_G + 0xff) / 2, (SKY_TOP_B + 0xff) / 2
local FAR_R, FAR_G, FAR_B = (SKY_TOP_R * 3 + 0xff) / 4, (SKY_TOP_G * 3 + 0xff) / 4, (SKY_TOP_B * 3 + 0xff) / 4

-- Precompute 1x1 textures for top and bottom
local top_color = 0xFF000000 + SKY_TOP_R * 0x10000 + SKY_TOP_G * 0x100 + SKY_TOP_B
local top_pixels = {top_color}
local top_png = minetest.encode_png(1, 1, top_pixels)
local top_base64 = minetest.encode_base64(top_png)
local top_tex = "[png:" .. top_base64

local bottom_color = 0xFF000000 + CLOSE_R * 0x10000 + CLOSE_G * 0x100 + CLOSE_B  -- Use close color for bottom
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
        local bg_r = math.floor(SKY_TOP_R * (1 - grad_frac) + SKY_BOTTOM_R * grad_frac)
        local bg_g = math.floor(SKY_TOP_G * (1 - grad_frac) + SKY_BOTTOM_G * grad_frac)
        local bg_b = math.floor(SKY_TOP_B * (1 - grad_frac) + SKY_BOTTOM_B * grad_frac)
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

        -- Collect samples along the ray
        local samples = {}
        local dist = MIN_SAMPLE_DISTANCE
        while dist <= MAX_SAMPLE_DISTANCE do
            local tx = pos.x + dist * dx
            local tz = pos.z + dist * dz
            local th = plains55.get_height_at(tx, tz, false)
            th = math.max(th, plains55.SEA_LEVEL)

            local delta_h = th - eye_y
            --if delta_h < 0 then delta_h = 0 end

            local theta = math.atan(delta_h / dist)
            table.insert(samples, {dist = dist, theta = theta})

            dist = dist * SAMPLE_STEP_MULTIPLY + SAMPLE_STEP_ADD
        end

        -- Sort samples by dist descending (far to near)
        -- Don't do this; this makes it look wrong
        --table.sort(samples, function(a, b) return a.dist > b.dist end)

        -- Track current max py from previous (closer) layers
        --local current_max_py = horizon_py
        local current_max_py = horizon_py + TEXTURE_HEIGHT / 4

        -- Draw from far to near
        for _, sample in ipairs(samples) do
            local max_theta_py = horizon_py - math.floor((math.deg(sample.theta) / 90) * (TEXTURE_HEIGHT / 2) * VERTICAL_SCALE)
            local draw_start_py = math.max(1, max_theta_py)

            if draw_start_py < current_max_py then
                -- Compute blend factor: far = close to far color, close = close color
                local blend_frac = (sample.dist - MIN_SAMPLE_DISTANCE) / (MAX_SAMPLE_DISTANCE - MIN_SAMPLE_DISTANCE)
                blend_frac = math.sqrt(blend_frac)
                blend_frac = 1 - blend_frac  -- 1 for close, 0 for far

                local layer_r = math.floor(CLOSE_R * blend_frac + FAR_R * (1 - blend_frac))
                local layer_g = math.floor(CLOSE_G * blend_frac + FAR_G * (1 - blend_frac))
                local layer_b = math.floor(CLOSE_B * blend_frac + FAR_B * (1 - blend_frac))
                local layer_color = 0xFF000000 + layer_r * 0x10000 + layer_g * 0x100 + layer_b

                -- Draw this layer's visible part (from draw_start_py to current_max_py - 1)
                for py = draw_start_py, current_max_py - 1 do
                    local vi = (py - 1) * TEXTURE_WIDTH + px
                    pixels[vi] = layer_color
                end

                -- Update current max for next (closer) layer
                current_max_py = draw_start_py
            end
        end

        -- Fill below horizon with horizon color
        for py = horizon_py + TEXTURE_HEIGHT / 4, TEXTURE_HEIGHT do
            local vi = (py - 1) * TEXTURE_WIDTH + px
            pixels[vi] = 0xFF000000 + HORIZON_BOTTOM_R * 0x10000 + HORIZON_BOTTOM_G * 0x100 + HORIZON_BOTTOM_B
        end
    end

    local png_data = minetest.encode_png(TEXTURE_WIDTH, TEXTURE_HEIGHT, pixels)
    local base64 = minetest.encode_base64(png_data)
    return "[png:" .. base64
end

-- Update the skybox for a player
-- TODO: What we actually need is a way to set up textures to be drawn inside
--       the skybox but behind the fog. Currently there is no API for that so we
--       need to use the skybox. Many games use the skybox for other purposes
--       and this won't work in that case.
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
        --base_color = "#ffffff",
        base_color = "#427096",
        textures = textures,
        clouds = true,
        sky_color = {  -- Example base sky (adjust as needed)
            --day_sky = "#61b5f5",
            --day_sky = "#427096",
            --day_horizon = "#90d3f6",
            day_sky = "#427096",
            day_horizon = "#427096",
            dawn_sky = "#b4bafa",
            --dawn_horizon = "#bac1f0",
            --dawn_sky = "#427096",
            dawn_horizon = "#427096",
            night_sky = "#006aff",
            --night_horizon = "#4090ff",
            --night_sky = "#427096",
            night_horizon = "#427096",
            indoors = "#646464",
            --indoors = "#427096",
            fog_sun_tint = "#eeb672",
            fog_moon_tint = "#eee9c9",
            --fog_sun_tint = "#427096",
            --fog_moon_tint = "#427096",
            --fog_tint_type = "default"
            fog_tint_type = "custom"
        },
        fog = {
            --fog_color = "#c8c8c8",
            --fog_distance = 500,
            --fog_start = 0.666,
            fog_color = "#427096",
            --fog_color = "#064882",
            --fog_color = "#326086",
        },
    })
    player:set_sun({
        visible = true,
        sunrise_visible = false, -- The sunrise doesn't look good with the skybox
    })
    -- Clouds use the same fog as the terrain which doesn't look very good as we
    -- set an intermediate for color which comes before the horizon, but that's
    -- what we have to use
    player:set_clouds({
        height = plains55.HEIGHT_SCALE * 0.5,
        --thickness = 8,
    })
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
