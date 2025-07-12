-- plains55: Core map generation logic

local modpath = minetest.get_modpath(minetest.get_current_modname())
local plains55 = dofile(modpath .. "/params.lua")

-- Buffers for mapgen
local data = {}

minetest.register_on_generated(function(minp, maxp, seed)
    local t0 = os.clock()

    -- Side length
    local sidelen = maxp.x - minp.x + 1

    -- Perlin map dimensions
    local permapdims2d = {x = sidelen, y = sidelen, z = 1}

    -- Dynamically get perlin maps for all noises
    local noise_vals = {}
    for name, np in pairs(plains55.noises) do
        local nobj = minetest.get_perlin_map(np, permapdims2d)
        noise_vals[name] = {}
        nobj:get_2d_map_flat({x = minp.x, y = minp.z}, noise_vals[name])
    end

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
            local norm = (noise_vals.terrain[ni] + plains55.sum_amp) / (2 * plains55.sum_amp)
            norm = math.max(0, math.min(1, norm))

            local scaled = plains55.compute_scaled(
                norm,
                noise_vals.sea_floor[ni],
                noise_vals.plains_height[ni],
                noise_vals.plains_width[ni],
                noise_vals.mountain_power[ni],
                noise_vals.ridge_strength[ni],
                noise_vals.ridge[ni],
                noise_vals.highland_height[ni],
                noise_vals.highland[ni]
            )

            -- Compute height
            local height = math.floor(plains55.HEIGHT_MIN + plains55.HEIGHT_SCALE * scaled)

            local x_rel = x - minp.x + 1
            local z_rel = z - minp.z + 1
            heightmap[x_rel][z_rel] = height

            -- Fill column
            for y = minp.y, maxp.y do
                local vi = area:index(x, y, z)
                if y <= height then
                    if y == height then
                        if height >= plains55.SAND_LEVEL then
                            data[vi] = plains55.c_grass
                        else
                            data[vi] = plains55.c_sand  -- Underwater floor
                        end
                    elseif y > height - 3 then
                        data[vi] = plains55.c_dirt
                    else
                        data[vi] = plains55.c_stone
                    end
                else  -- y > height
                    if y <= plains55.SEA_LEVEL then
                        data[vi] = plains55.c_water
                    else
                        data[vi] = plains55.c_air
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
                                data[vi] = plains55.c_water
                            end
                            -- Set bottom to sand if bottom is in chunk
                            if nh >= minp.y and nh <= maxp.y then
                                local bottom_vi = area:index(minp.x + nx - 1, nh, minp.z + nz - 1)
                                data[bottom_vi] = plains55.c_sand
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
