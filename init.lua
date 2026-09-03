-- offhand_screen_view
--
-- Add-on for the "offhand" mod (SFENCE / t-affeldt fork of mcl_offhand).
-- Shows the item currently held in the offhand as an on-screen element,
-- drawn in BOTH first and third person.
--
-- WHAT THIS MOD DOES
-- * Renders the item through the [inventorycube texture modifier (the same
--   software 3D renderer the engine uses for the hotbar cubes), so blocks
--   look like shaded cubes instead of a flat tile, and tools use their
--   wield_image.
-- * Draws it LARGE, anchored to the lower-left corner of the screen (the
--   mirror image of the engine's main-hand wield view, which sits in the
--   lower-right). Position is given as a fraction of the screen so it works
--   on any resolution.
-- * Optionally hides the small icon the base "offhand" mod draws next to the
--   hotbar (offhand_screen_hide_base_icon, OFF by default).
--
-- WHY NOT A REAL SECOND 3D HAND?
-- * The engine renders exactly ONE first-person wield model (the main hand);
--   a second one is an open engine feature request (luanti#10345).
-- * The base mod's real 3D item is attached to the Arm_Left bone. Attached
--   objects are hidden in first person unless attached with forced_visible,
--   but in first person the client does NOT apply the local player's bone
--   transforms, so the item shows up floating at your feet. A screen-anchored
--   HUD element is the only thing that can sit at "hand height" in view.
--
-- INSTALL: put this folder next to the "offhand" mod folder in your
-- world/game mods directory and enable it like any other mod.

offhand_screen_view = {}

if not offhand then
    minetest.log("error", "[offhand_screen_view] 'offhand' mod not found, disabling.")
    return
end

-- ==== settings (also see settingtypes.txt) ====================
local function get_number(name, default)
    return tonumber(minetest.settings:get(name)) or default
end

local function get_bool(name, default)
    local value = minetest.settings:get_bool(name)
    if value == nil then
        return default
    end
    return value
end

-- Icons are normalised to icon_px x icon_px pixels so that all the pixel
-- offsets below stay consistent.
local icon_px  = math.floor(get_number("offhand_screen_icon_size", 380))
local bg_pad   = math.floor(get_number("offhand_screen_bg_padding", 6))
local pos_x    = get_number("offhand_screen_pos_x", 0.12)
local pos_y    = get_number("offhand_screen_pos_y", 0.88)
local show_icon  = get_bool("offhand_screen_show_icon", true)
local show_bg    = get_bool("offhand_screen_show_background", false)
local show_count = get_bool("offhand_screen_show_count", true)
local use_cubes  = get_bool("offhand_screen_3d_icons", true)
local hide_base  = get_bool("offhand_screen_hide_base_icon", false)

if icon_px < 8 then icon_px = 8 end
if bg_pad < 0 then bg_pad = 0 end
-- =================================================================

local huds = {} -- [player_name] = { icon = id, bg = id, count = id, itemname = "", count_n = 0 }

local function get_tile_name(tiledef)
    if type(tiledef) == "table" then
        return tiledef.name
    end
    return tiledef
end

-- Drawtypes that are drawn as flat sprites in the world. Building a fake cube
-- out of them looks worse than the flat image, so they keep their tile.
local FLAT_DRAWTYPES = {
    plantlike = true,
    firelike = true,
    torchlike = true,
    signlike = true,
    raillike = true,
    airlike = true,
}

-- [inventorycube uses "{" as a separator, so "^" inside its arguments has to
-- be replaced by "&". minetest.inventorycube() does that for us.
local function inventorycube(top, left, right)
    if minetest.inventorycube then
        return minetest.inventorycube(top, left, right)
    end
    local function escape(tex)
        return (tex:gsub("%^", "&"))
    end
    return "[inventorycube{" .. escape(top) .. "{" .. escape(left) .. "{" .. escape(right)
end

local function normalized(tex)
    return tex .. "^[resize:" .. icon_px .. "x" .. icon_px
end

-- Builds the texture shown in the HUD for the given item.
-- Priority mirrors what the engine puts into the main hand:
--   wield_image -> inventory_image -> 3D cube built from the node tiles.
function offhand_screen_view.build_icon(itemname)
    if not itemname or itemname == "" then
        return nil
    end

    local def = minetest.registered_items[itemname]
    if not def then
        return normalized("unknown_item.png")
    end

    if def.wield_image and def.wield_image ~= "" then
        return normalized(def.wield_image)
    end

    if def.inventory_image and def.inventory_image ~= "" then
        return normalized(def.inventory_image)
    end

    local tiles = def.tiles
    if tiles and tiles[1] then
        local top = get_tile_name(tiles[1])
        if top and top ~= "" then
            local is_node = minetest.registered_nodes[itemname] ~= nil
            if use_cubes and is_node and not FLAT_DRAWTYPES[def.drawtype] then
                local left = get_tile_name(tiles[3] or tiles[1])
                local right = get_tile_name(tiles[5] or tiles[3] or tiles[1])
                return normalized(inventorycube(top, left, right))
            end
            return normalized(top)
        end
    end

    return normalized("unknown_item.png")
end

local function add_icon_hud(player, icon)
    return player:hud_add({
        hud_elem_type = "image",
        type = "image",
        name = "offhand_screen_view_icon",
        position  = {x = pos_x, y = pos_y},
        alignment = {x = 0, y = 0},
        scale     = {x = 1, y = 1},
        text      = icon,
        z_index   = 101,
    })
end

local function add_bg_hud(player)
    local size = icon_px + 2 * bg_pad
    return player:hud_add({
        hud_elem_type = "image",
        type = "image",
        name = "offhand_screen_view_bg",
        position  = {x = pos_x, y = pos_y},
        alignment = {x = 0, y = 0},
        scale     = {x = 1, y = 1},
        text      = "[fill:" .. size .. "x" .. size .. ":#00000066",
        z_index   = 100,
    })
end

local function add_count_hud(player, count)
    return player:hud_add({
        hud_elem_type = "text",
        type = "text",
        name = "offhand_screen_view_count",
        position  = {x = pos_x, y = pos_y},
        offset    = {x = icon_px / 2 - 12, y = icon_px / 2 - 12},
        alignment = {x = -1, y = -1},
        text      = tostring(count),
        number    = 0xFFFFFF,
        z_index   = 102,
    })
end

local function remove_huds(player)
    local pname = player:get_player_name()
    local data = huds[pname]
    if not data then return end
    for _, key in ipairs({"bg", "icon", "count"}) do
        if data[key] then
            player:hud_remove(data[key])
            data[key] = nil
        end
    end
    huds[pname] = nil
end

-- The base "offhand" mod draws its own small icon next to the hotbar and
-- keeps the HUD ids in the global `offhand[player].hud` table. The ids cannot
-- be removed safely (the base mod still calls hud_change/hud_get on them),
-- so we just park every element far off-screen. Disabled by default.
function offhand_screen_view.hide_base_hud(player)
    if not hide_base then return end
    local data = offhand[player]
    if type(data) ~= "table" or type(data.hud) ~= "table" then return end
    for _, id in pairs(data.hud) do
        if type(id) == "number" then
            pcall(player.hud_change, player, id, "offset",
                {x = -100000, y = -100000})
        end
    end
end

function offhand_screen_view.update(player)
    if not player or not player:is_player() then return end
    local pname = player:get_player_name()

    if not show_icon then
        remove_huds(player)
        return
    end

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

    local count = stack:get_count()
    local data = huds[pname]

    if not data then
        data = {itemname = itemname, count_n = count}
        if show_bg then
            data.bg = add_bg_hud(player)
        end
        data.icon = add_icon_hud(player, offhand_screen_view.build_icon(itemname))
        if show_count and count > 1 then
            data.count = add_count_hud(player, count)
        end
        huds[pname] = data
        return
    end

    -- nothing to do: the slot still shows exactly this stack
    if data.itemname == itemname and data.count_n == count then
        return
    end

    if data.itemname ~= itemname then
        player:hud_change(data.icon, "text", offhand_screen_view.build_icon(itemname))
        data.itemname = itemname
    end

    if data.count_n ~= count then
        if show_count and count > 1 then
            if data.count then
                player:hud_change(data.count, "text", tostring(count))
            else
                data.count = add_count_hud(player, count)
            end
        elseif data.count then
            player:hud_remove(data.count)
            data.count = nil
        end
        data.count_n = count
    end
end

minetest.register_on_joinplayer(function(player)
    huds[player:get_player_name()] = nil
    -- small delay so the "offhand" mod has finished setting up the
    -- player's inventory list before we read it
    minetest.after(0.5, function()
        if player and player:is_player() then
            offhand_screen_view.update(player)
            offhand_screen_view.hide_base_hud(player)
        end
    end)
end)

minetest.register_on_leaveplayer(function(player)
    huds[player:get_player_name()] = nil
end)

-- react instantly whenever the offhand mod swaps/uses items
offhand.register_on_item_change(function(player, item_before, item_after)
    offhand_screen_view.update(player)
    offhand_screen_view.hide_base_hud(player)
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
        offhand_screen_view.update(player)
        offhand_screen_view.hide_base_hud(player)
    end
end)