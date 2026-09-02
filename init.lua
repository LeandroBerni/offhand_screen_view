-- offhand_screen_view
--
-- Add-on for the "offhand" mod (SFENCE / t-affeldt fork of mcl_offhand).
-- Shows the item currently held in the offhand as an on-screen icon,
-- similar to Minecraft's off-hand indicator.
--
-- WHY A HUD ICON AND NOT A 3D HAND MODEL?
-- Luanti's engine only supports rendering ONE "wielditem" viewmodel in
-- first person (the main hand). There is no engine API to add a second
-- 3D hand+item view in first person. The 3D model you see in third
-- person comes from an entity bone-attached to the player model, which
-- is never rendered for yourself in first person.
-- A 2D HUD image, however, IS rendered in both first person and third
-- person, so it is the closest equivalent to Minecraft's on-screen
-- offhand item, and it actually solves "I can't see my offhand item in
-- first person".
--
-- INSTALL: put this folder next to the "offhand" mod folder in your
-- world/game mods directory and enable it like any other mod.

if not offhand then
    minetest.log("error", "[offhand_screen_view] 'offhand' mod not found, disabling.")
    return
end

-- ==== settings (also see settingtypes.txt) ====================
local icon_scale   = tonumber(minetest.settings:get("offhand_screen_icon_scale")) or 2.2
local bg_extra     = tonumber(minetest.settings:get("offhand_screen_bg_padding")) or 0.6
local offset_x     = tonumber(minetest.settings:get("offhand_screen_offset_x")) or 130
local offset_y     = tonumber(minetest.settings:get("offhand_screen_offset_y")) or -110
local show_bg      = minetest.settings:get_bool("offhand_screen_show_background")
if show_bg == nil then show_bg = true end
-- =================================================================

local huds = {} -- [player_name] = { bg = id_or_nil, icon = id_or_nil }

local function get_tile_name(tiledef)
    if type(tiledef) == "table" then
        return tiledef.name
    end
    return tiledef
end

-- Figures out a flat texture to represent the item, reusing the same
-- fallbacks the original mod uses for its own icon building.
local function get_item_icon(itemname)
    if not itemname or itemname == "" then
        return nil
    end
    local def = minetest.registered_items[itemname]
    if not def then
        return "unknown_item.png"
    end
    if def.inventory_image and def.inventory_image ~= "" then
        return def.inventory_image
    end
    if def.wield_image and def.wield_image ~= "" then
        return def.wield_image
    end
    if def.tiles and def.tiles[1] then
        return get_tile_name(def.tiles[1])
    end
    return "unknown_item.png"
end

local function remove_huds(player)
    local pname = player:get_player_name()
    local data = huds[pname]
    if not data then return end
    if data.bg then player:hud_remove(data.bg) end
    if data.icon then player:hud_remove(data.icon) end
    huds[pname] = nil
end

local function update_screen_offhand(player)
    if not player or not player:is_player() then return end
    local pname = player:get_player_name()

    local ok, stack = pcall(offhand.get_offhand, player)
    if not ok or not stack then
        remove_huds(player)
        return
    end

    local itemname = stack:get_name()

    if itemname == "" then
        remove_huds(player)
        return
    end

    local icon = get_item_icon(itemname)
    local data = huds[pname]

    if not data then
        data = {}
        if show_bg then
            data.bg = player:hud_add({
                hud_elem_type = "image",
                position  = {x = 0.5, y = 1},
                offset    = {x = offset_x, y = offset_y},
                alignment = {x = 0, y = 0},
                scale     = {x = icon_scale + bg_extra, y = icon_scale + bg_extra},
                text      = "[fill:16x16:#00000066",
                z_index   = 100,
            })
        end
        data.icon = player:hud_add({
            hud_elem_type = "image",
            position  = {x = 0.5, y = 1},
            offset    = {x = offset_x, y = offset_y},
            alignment = {x = 0, y = 0},
            scale     = {x = icon_scale, y = icon_scale},
            text      = icon,
            z_index   = 101,
        })
        huds[pname] = data
    else
        player:hud_change(data.icon, "text", icon)
    end
end

minetest.register_on_joinplayer(function(player)
    huds[player:get_player_name()] = nil
    -- small delay so the "offhand" mod has finished setting up the
    -- player's inventory list before we read it
    minetest.after(0.5, function()
        if player and player:is_player() then
            update_screen_offhand(player)
        end
    end)
end)

minetest.register_on_leaveplayer(function(player)
    huds[player:get_player_name()] = nil
end)

-- react instantly whenever the offhand mod swaps/uses items
offhand.register_on_item_change(function(player, item_before, item_after)
    update_screen_offhand(player)
end)

-- safety net: keeps the icon in sync even if something changes the
-- "offhand" inventory list directly (e.g. drag & drop in a formspec)
-- without going through offhand's own change handlers
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < 0.5 then return end
    timer = 0
    for _, player in ipairs(minetest.get_connected_players()) do
        update_screen_offhand(player)
    end
end)
