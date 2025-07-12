-- plains55: Shared parameters and helpers

local plains55 = {}

plains55.SEA_LEVEL = 0
plains55.SAND_LEVEL = plains55.SEA_LEVEL + 2
plains55.HEIGHT_MIN = -32
plains55.HEIGHT_SCALE = 256  -- Increased for bigger (taller) mountains
plains55.RIDGE_SIZE = 0.4

-- Noise parameters
plains55.noises = {}

plains55.noises.terrain = {
    offset = 0,
    scale = 1,
    spread = {x = 512, y = 512, z = 512},
    seed = 12345,
    octaves = 7,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

plains55.noises.sea_floor = {
    offset = -0.05,
    scale = 0.05,
    spread = {x = 512, y = 512, z = 512},
    seed = 10,
    octaves = 3,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

plains55.noises.plains_height = {
    offset = 0.14,
    scale = 0.20,
    spread = {x = 2048, y = 2048, z = 2048},
    seed = 20,
    octaves = 4,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

plains55.noises.plains_width = {
    offset = 0.2,
    scale = 0.1,
    spread = {x = 512, y = 512, z = 512},
    seed = 30,
    octaves = 3,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

plains55.noises.mountain_power = {
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
plains55.noises.ridge_strength = {
    offset = 0,
    scale = 0.3,
    spread = {x = 1024, y = 1024, z = 1024},
    seed = 50,
    octaves = 2,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

plains55.noises.ridge = {
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
plains55.noises.highland_height = {
    offset = 0,
    scale = 0.4,
    spread = {x = 2048, y = 2048, z = 2048},
    seed = 70,
    octaves = 2,
    persistence = 0.5,
    lacunarity = 2.0,
    flags = ""
}

plains55.noises.highland = {
    offset = 0,
    scale = 1,
    spread = {x = 512, y = 512, z = 512},
    seed = 80,
    octaves = 6,
    persistence = 0.6,
    lacunarity = 2.0,
    flags = "absvalue"
}

-- Theoretical amplitude sum for normalization
plains55.sum_amp = (1 - math.pow(plains55.noises.terrain.persistence, plains55.noises.terrain.octaves)) / (1 - plains55.noises.terrain.persistence)  -- ~1.984375
plains55.sum_amp_ridge = (1 - math.pow(plains55.noises.ridge.persistence, plains55.noises.ridge.octaves)) / (1 - plains55.noises.ridge.persistence)  -- ~2.176
plains55.sum_amp_highland = (1 - math.pow(plains55.noises.highland.persistence, plains55.noises.highland.octaves)) / (1 - plains55.noises.highland.persistence)  -- Adjusted for octaves=6 ~2.5216

-- Modular function to compute scaled height from noises
function plains55.compute_scaled(norm, sea_floor_level, plains_height, plains_width, mountain_power, ridge_strength, ridge_noise, highland_height, highland_noise)
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
            local ridged = 1 - (ridge_noise / plains55.sum_amp_ridge)  -- Normalize absvalue noise to [0,1], then invert for ridges
            scaled = scaled + ridge_strength * ridged * plains55.RIDGE_SIZE
        end
    end
    -- Add highland effect
    local highland_y = (1 - (highland_noise / plains55.sum_amp_highland) - 0.6) / 0.6  -- Adjusted for clamp filter
    local highland_maxheight = math.max(0, highland_height)
    highland_y = math.min(highland_maxheight, math.max(0, highland_y))
    scaled = scaled + highland_y

    return scaled
end

-- Initialize perlin objects for single-point queries (e.g., for preview)
function plains55.init_perlins()
    plains55.perlins = {}
    for name, np in pairs(plains55.noises) do
        plains55.perlins[name] = minetest.get_perlin(np)
    end
end

-- Get all noise values at a specific world position
function plains55.get_noises_at(world_x, world_z)
    if not plains55.perlins then
        plains55.init_perlins()
    end
    local noises = {}
    for name, perlin in pairs(plains55.perlins) do
        noises[name] = perlin:get_2d({x = world_x, y = world_z})
    end
    return noises
end

-- Compute height at a specific world position (not floored by default)
function plains55.get_height_at(world_x, world_z, floor_it)
    local noises = plains55.get_noises_at(world_x, world_z)

    local norm = (noises.terrain + plains55.sum_amp) / (2 * plains55.sum_amp)
    norm = math.max(0, math.min(1, norm))

    local scaled = plains55.compute_scaled(
        norm,
        noises.sea_floor,
        noises.plains_height,
        noises.plains_width,
        noises.mountain_power,
        noises.ridge_strength,
        noises.ridge,
        noises.highland_height,
        noises.highland
    )

    local height = plains55.HEIGHT_MIN + plains55.HEIGHT_SCALE * scaled
    if floor_it then
        height = math.floor(height)
    end
    return height
end

-- Get RGB color for a given height
function plains55.get_color_for_height(height)
    local r, g, b
    if height <= plains55.SEA_LEVEL then
        -- Water: shade blue based on depth
        local depth = math.min(1, (plains55.SEA_LEVEL - height) / (-plains55.HEIGHT_MIN))  -- 0 to 1
        r = math.floor(25 * (1 - depth))
        g = math.floor(50 * (1 - depth))
        b = math.floor(150 + 105 * (1 - depth))
    else
        -- Land: green to white
        local land_norm = (height - plains55.SEA_LEVEL) / (plains55.HEIGHT_SCALE - plains55.HEIGHT_MIN)  -- Adjusted denominator for better normalization (max ~256)
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
    return r, g, b
end

-- Content IDs (shared for mapgen)
plains55.c_air = minetest.get_content_id("air")
plains55.c_water = minetest.get_content_id("default:water_source")
plains55.c_stone = minetest.get_content_id("default:stone")
plains55.c_dirt = minetest.get_content_id("default:dirt")
plains55.c_grass = minetest.get_content_id("default:dirt_with_grass")
plains55.c_sand = minetest.get_content_id("default:sand")

return plains55
