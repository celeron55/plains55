-- plains55: mapgen mod for Luanti
-- To use: Set mapgen to "singlenode" in world creation or minetest.conf (mg_name = singlenode)

local SEA_LEVEL = 0
local SAND_LEVEL = SEA_LEVEL + 2
local HEIGHT_MIN = -32
local HEIGHT_SCALE = 256  -- Increased for bigger (taller) mountains
local RIDGE_SIZE = 0.4

-- Noise parameters (matching Python fractal noise: octaves=6, persistence=0.5, lacunarity=2.0)
local np_terrain = {
    offset = 0,
    scale = 1,
    spread = {x = 512, y = 512, z = 512},
    seed = 12345,
    octaves = 7,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""  -- Additional low-frequency noises for dynamic interpolation parameters
}

local np_sea_floor = {
    offset = -0.05,
    scale = 0.05,
    spread = {x = 512, y = 512, z = 512},
    seed = 10,
    octaves = 3,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

local np_plains_height = {
    offset = 0.14,
    scale = 0.20,
    spread = {x = 2048, y = 2048, z = 2048},
    seed = 20,
    octaves = 4,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

local np_plains_width = {
    offset = 0.2,
    scale = 0.1,
    spread = {x = 512, y = 512, z = 512},
    seed = 30,
    octaves = 3,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

local np_mountain_power = {
    offset = 1.5,
    scale = 0.5,
    spread = {x = 512, y = 512, z = 512},
    seed = 40,
    octaves = 3,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

-- New noises for ridges
-- TODO: These noises could probably be combined into one. Ridges only occur at
--       the edges of mountain areas and one noise should be able to elevate the
--       mountain area so that there's a sharp edge
local np_ridge_strength = {
    offset = 0,
    scale = 0.3,
    spread = {x = 1024, y = 1024, z = 1024},
    seed = 50,
    octaves = 2,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

local np_ridge = {
    offset = 0,
    scale = 1,
    spread = {x = 512, y = 512, z = 512},
    seed = 60,
    octaves = 4,
    persistence = 0.6,
    lacunarity = 2.0,
    flags = "absvalue"
}

-- New noise for highlands
local np_highland_height = {
    offset = 0,
    scale = 0.4,
    spread = {x = 2048, y = 2048, z = 2048},
    seed = 70,
    octaves = 2,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

local np_highland = {
    offset = 0,
    scale = 1,
    spread = {x = 512, y = 512, z = 512},
    seed = 80,
    octaves = 6,
    persistence = 0.6,
    lacunarity = 2.0,
    flags = "absvalue"
}

-- Theoretical amplitude sum for normalization (sum of geometric series)
local sum_amp = (1 - math.pow(np_terrain.persistence, np_terrain.octaves)) / (1 - np_terrain.persistence)  -- ~1.984375
local sum_amp_ridge = (1 - math.pow(0.6, 4)) / (1 - 0.6)  -- For ridge noise ~2.176
local sum_amp_highland = sum_amp_ridge  -- Same parameters

-- Modular function to compute scaled height from noises
local function compute_scaled(norm, sea_floor_level, plains_height, plains_width, mountain_power, ridge_strength, ridge_noise, highland_height, highland_noise)
    -- Clamp parameters for stability
    plains_width = math.max(0.01, math.min(0.5, plains_width))
    mountain_power = math.max(1.0, math.min(3.0, mountain_power))

    local ocean_end = 0.2
    local rise_end = 0.4
    local plains_start = rise_end
    local plains_end = plains_start + plains_width
    if plains_end > 0.8 then
        plains_end = 0.8
        plains_width = 0.8 - plains_start
    end
    local mountain_start = plains_end

    local scaled
    if norm <= ocean_end then
        scaled = sea_floor_level
    elseif norm < rise_end then
        local frac = (norm - ocean_end) / (rise_end - ocean_end)
        scaled = sea_floor_level + frac * (plains_height - sea_floor_level)
    elseif norm < plains_end then
        scaled = plains_height
    else
        local frac = (norm - mountain_start) / (1 - mountain_start)
        scaled = plains_height + (1 - plains_height) * math.pow(frac, mountain_power)
        -- Add ridge effect
        if ridge_strength > 0 then
            local ridged = 1 - (ridge_noise / sum_amp_ridge)  -- Normalize absvalue noise to [0,1], then invert for ridges
            scaled = scaled + ridge_strength * ridged * RIDGE_SIZE
        end
    end
    -- Add highland effect
    local highland_y = (1 - (highland_noise / sum_amp_highland) - 0.6) / 0.6  -- Adjusted for clamp filter
    local highland_maxheight = math.max(0, highland_height)
    highland_y = math.min(highland_maxheight, math.max(0, highland_y))
    scaled = scaled + highland_y

    return scaled
end

-- Content IDs
local c_air = minetest.get_content_id("air")
local c_water = minetest.get_content_id("default:water_source")
local c_stone = minetest.get_content_id("default:stone")
local c_dirt = minetest.get_content_id("default:dirt")
local c_grass = minetest.get_content_id("default:dirt_with_grass")
local c_sand = minetest.get_content_id("default:sand")  -- For underwater floors

-- Buffers for mapgen
local nvals = {}
local data = {}

minetest.register_on_generated(function(minp, maxp, seed)
    local t0 = os.clock()

    -- Side length
    local sidelen = maxp.x - minp.x + 1

    -- Get 2D Perlin map for terrain
    local permapdims2d = {x = sidelen, y = sidelen, z = 1}
    local nobj_terrain = minetest.get_perlin_map(np_terrain, permapdims2d)
    nobj_terrain:get_2d_map_flat({x = minp.x, y = minp.z}, nvals)

    -- Get maps for dynamic parameters
    local nobj_sea = minetest.get_perlin_map(np_sea_floor, permapdims2d)
    local nvals_sea = {}
    nobj_sea:get_2d_map_flat({x = minp.x, y = minp.z}, nvals_sea)

    local nobj_plains_h = minetest.get_perlin_map(np_plains_height, permapdims2d)
    local nvals_plains_h = {}
    nobj_plains_h:get_2d_map_flat({x = minp.x, y = minp.z}, nvals_plains_h)

    local nobj_plains_w = minetest.get_perlin_map(np_plains_width, permapdims2d)
    local nvals_plains_w = {}
    nobj_plains_w:get_2d_map_flat({x = minp.x, y = minp.z}, nvals_plains_w)

    local nobj_mtn_p = minetest.get_perlin_map(np_mountain_power, permapdims2d)
    local nvals_mtn_p = {}
    nobj_mtn_p:get_2d_map_flat({x = minp.x, y = minp.z}, nvals_mtn_p)

    local nobj_ridge_s = minetest.get_perlin_map(np_ridge_strength, permapdims2d)
    local nvals_ridge_s = {}
    nobj_ridge_s:get_2d_map_flat({x = minp.x, y = minp.z}, nvals_ridge_s)

    local nobj_ridge = minetest.get_perlin_map(np_ridge, permapdims2d)
    local nvals_ridge = {}
    nobj_ridge:get_2d_map_flat({x = minp.x, y = minp.z}, nvals_ridge)

    local nobj_highland_h = minetest.get_perlin_map(np_highland_height, permapdims2d)
    local nvals_highland_h = {}
    nobj_highland_h:get_2d_map_flat({x = minp.x, y = minp.z}, nvals_highland_h)

    local nobj_highland = minetest.get_perlin_map(np_highland, permapdims2d)
    local nvals_highland = {}
    nobj_highland:get_2d_map_flat({x = minp.x, y = minp.z}, nvals_highland)

    -- Voxelmanip
    local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
    local area = VoxelArea:new{MinEdge = emin, MaxEdge = emax}
    vm:get_data(data)

    -- Generation loop - basic terrain
    local heightmap = {}
    for x_rel = 1, sidelen do
        heightmap[x_rel] = {}
    end
    local ni = 1
    for z = minp.z, maxp.z do
        for x = minp.x, maxp.x do
            local noise = nvals[ni]
            local norm = (noise + sum_amp) / (2 * sum_amp)
            norm = math.max(0, math.min(1, norm))

            local sea_floor_level = nvals_sea[ni]
            local plains_height = nvals_plains_h[ni]
            local plains_width = nvals_plains_w[ni]
            local mountain_power = nvals_mtn_p[ni]
            local ridge_strength = nvals_ridge_s[ni]
            local ridge_noise = nvals_ridge[ni]
            local highland_height = nvals_highland_h[ni]
            local highland_noise = nvals_highland[ni]

            local scaled = compute_scaled(norm, sea_floor_level, plains_height, plains_width, mountain_power, ridge_strength, ridge_noise, highland_height, highland_noise)

            -- Compute height
            local height = math.floor(HEIGHT_MIN + HEIGHT_SCALE * scaled)

            local x_rel = x - minp.x + 1
            local z_rel = z - minp.z + 1
            heightmap[x_rel][z_rel] = height

            -- Fill column
            for y = minp.y, maxp.y do
                local vi = area:index(x, y, z)
                if y <= height then
                    if y == height then
                        if height >= SAND_LEVEL then
                            data[vi] = c_grass
                        else
                            data[vi] = c_sand  -- Underwater floor
                        end
                    elseif y > height - 3 then
                        data[vi] = c_dirt
                    else
                        data[vi] = c_stone
                    end
                else  -- y > height
                    if y <= SEA_LEVEL then
                        data[vi] = c_water
                    else
                        data[vi] = c_air
                    end
                end
            end
            ni = ni + 1
        end
    end

    -- Post-processing: Fill enclosed depressions with water
    local visited = {}
    for x = 1, sidelen do
        visited[x] = {}
        for z = 1, sidelen do
            visited[x][z] = false
        end
    end

    local open = {}

    -- Add borders to open
    for x = 1, sidelen do
        table.insert(open, {x_rel = x, z_rel = 1, h = heightmap[x][1]})
        table.insert(open, {x_rel = x, z_rel = sidelen, h = heightmap[x][sidelen]})
        visited[x][1] = true
        visited[x][sidelen] = true
    end
    for z = 2, sidelen - 1 do
        table.insert(open, {x_rel = 1, z_rel = z, h = heightmap[1][z]})
        table.insert(open, {x_rel = sidelen, z_rel = z, h = heightmap[sidelen][z]})
        visited[1][z] = true
        visited[sidelen][z] = true
    end

    while #open > 0 do
        -- Find cell with min h
        local min_idx = 1
        for i = 2, #open do
            if open[i].h < open[min_idx].h then
                min_idx = i
            end
        end
        local cell = table.remove(open, min_idx)
        local fill_h = cell.h

        -- Neighbors
        local dirs = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
        for _, dir in ipairs(dirs) do
            local nx = cell.x_rel + dir[1]
            local nz = cell.z_rel + dir[2]
            if nx >= 1 and nx <= sidelen and nz >= 1 and nz <= sidelen and not visited[nx][nz] then
                visited[nx][nz] = true
                local nh = heightmap[nx][nz]
                local prop_h = math.max(nh, fill_h)
                table.insert(open, {x_rel = nx, z_rel = nz, h = prop_h})
                if nh < fill_h then
                    local lake_level = fill_h - 1  -- Adjusted to fill to water level
                    if lake_level > nh then
                        -- Check if the fill range overlaps with chunk's y
                        local fill_min = nh + 1
                        local fill_max = lake_level
                        if fill_max >= minp.y and fill_min <= maxp.y then
                            -- Fill with water only within chunk range
                            local start_y = math.max(fill_min, minp.y)
                            local end_y = math.min(fill_max, maxp.y)
                            for y = start_y, end_y do
                                local vi = area:index(minp.x + nx - 1, y, minp.z + nz - 1)
                                data[vi] = c_water
                            end
                            -- Set bottom to sand if bottom is in chunk
                            if nh >= minp.y and nh <= maxp.y then
                                local bottom_vi = area:index(minp.x + nx - 1, nh, minp.z + nz - 1)
                                data[bottom_vi] = c_sand
                            end
                        end
                    end
                end
            end
        end
    end

    -- Write back
    vm:set_data(data)
    minetest.generate_ores(vm, minp, maxp)
    minetest.generate_decorations(vm, minp, maxp, seed)
    vm:write_to_map()
    vm:update_map()  -- Optional for lighting

    local t1 = os.clock()
    print("[noise_terrain] Chunk gen time: " .. (t1 - t0) * 1000 .. " ms")
end)

-- Function to generate preview texture
local function generate_preview_texture(center_x, center_z)
    local preview_size = 512  -- Increased for more pixels
    local world_scale = 16  -- Increased to cover more area (~4096x4096 nodes)
    local half = preview_size / 2

    -- Get Perlin objects for all noises
    local p_terrain = minetest.get_perlin(np_terrain)
    local p_sea = minetest.get_perlin(np_sea_floor)
    local p_plains_h = minetest.get_perlin(np_plains_height)
    local p_plains_w = minetest.get_perlin(np_plains_width)
    local p_mtn_p = minetest.get_perlin(np_mountain_power)
    local p_ridge_s = minetest.get_perlin(np_ridge_strength)
    local p_ridge = minetest.get_perlin(np_ridge)
    local p_highland_h = minetest.get_perlin(np_highland_height)
    local p_highland = minetest.get_perlin(np_highland)

    -- Compute pixels
    local pixels = {}
    for py = 1, preview_size do
        for px = 1, preview_size do
            local world_x = center_x + (px - half - 0.5) * world_scale
            local world_z = center_z + (half - py + 0.5) * world_scale  -- Flipped to correct vertical mirroring

            local noise = p_terrain:get_2d({x = world_x, y = world_z})
            local norm = (noise + sum_amp) / (2 * sum_amp)
            norm = math.max(0, math.min(1, norm))

            local sea_floor_level = p_sea:get_2d({x = world_x, y = world_z})
            local plains_height = p_plains_h:get_2d({x = world_x, y = world_z})
            local plains_width = p_plains_w:get_2d({x = world_x, y = world_z})
            local mountain_power = p_mtn_p:get_2d({x = world_x, y = world_z})
            local ridge_strength = p_ridge_s:get_2d({x = world_x, y = world_z})
            local ridge_noise = p_ridge:get_2d({x = world_x, y = world_z})
            local highland_height = p_highland_h:get_2d({x = world_x, y = world_z})
            local highland_noise = p_highland:get_2d({x = world_x, y = world_z})

            local scaled = compute_scaled(norm, sea_floor_level, plains_height, plains_width, mountain_power, ridge_strength, ridge_noise, highland_height, highland_noise)

            -- Compute height (not floored for smoother coloring)
            local height = HEIGHT_MIN + HEIGHT_SCALE * scaled

            -- Color based on effective surface
            local r, g, b
            if height <= SEA_LEVEL then
                -- Water: shade blue based on depth
                local depth = math.min(1, (SEA_LEVEL - height) / (-HEIGHT_MIN))  -- 0 to 1
                r = math.floor(25 * (1 - depth))
                g = math.floor(50 * (1 - depth))
                b = math.floor(150 + 105 * (1 - depth))
            else
                -- Land: green to white
                local land_norm = (height - SEA_LEVEL) / (HEIGHT_SCALE - HEIGHT_MIN)  -- Adjusted denominator for better normalization (max ~256)
                land_norm = math.max(0, land_norm)  -- Clamp
                if land_norm < 0.3 then  -- Plains green
                    r = math.floor(34 + 200 * land_norm)
                    g = math.floor(139 + 300 * land_norm)
                    b = math.floor(34 + 150 * land_norm)
                elseif land_norm < 0.6 then  -- Hills brown
                    local hill_frac = (land_norm - 0.3) / 0.3
                    r = math.floor(139 + 116 * hill_frac)
                    g = math.floor(69 + 186 * (1 - hill_frac))
                    b = math.floor(19)
                else  -- Mountains gray/white
                    local mtn_frac = (land_norm - 0.6) / 0.4
                    local gray = math.floor(160 + 95 * mtn_frac)
                    r = gray
                    g = gray
                    b = gray
                end
            end
            local color = 0xFF000000 + (r * 0x10000) + (g * 0x100) + b  -- ARGB8
            table.insert(pixels, color)
        end
    end

    -- Encode PNG and base64
    local png_data = minetest.encode_png(preview_size, preview_size, pixels)
    local base64 = minetest.encode_base64(png_data)
    return "[png:" .. base64 .. "]"
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
