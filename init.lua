-- offhand_screen_view
--
-- Add-on for the "offhand" mod (SFENCE / t-affeldt fork of mcl_offhand).
-- Shows the item currently held in the offhand slot as an on-screen icon,
-- similar to Minecraft's off-hand indicator.
--
-- WHY A HUD ICON AND NOT A REAL SECOND 3D HAND?
-- * The engine renders exactly ONE first-person wield model (the main hand).
--   A second one is still an open engine feature request
--   (luanti-org/luanti#10345 "Add Second Hand"), so no mod can add it.
-- * A HUD element, on the other hand, IS drawn in both first and third person.
--
-- To keep the icon from looking like a flat inventory picture, every icon is
-- rendered through the [inventorycube texture modifier: the very same software
-- 3D renderer the engine uses to draw cubic nodes in the hotbar/inventory.
-- So a block shows up as a shaded cube (top + two side faces), and tools show
-- up with their wield_image, i.e. the same picture the engine extrudes into
-- the main hand.
--
-- ON TOP OF THAT this mod re-attaches the real 3D item that the "offhand" mod
-- puts in your left arm with forced_visible = true (see ObjectRef:set_attach).
-- Objects attached to a player are hidden in first person by default, which is
-- why that item only ever showed up in third person. It stays glued to your
-- arm, so you see it whenever your arm is inside the view (looking down),
-- while the HUD icon covers the rest of the time.
--
-- INSTALL: put this folder next to the "offhand" mod folder in your
-- world/game mods directory and enable it like any other mod.

offhand_screen_view = {}

if not offhand then
    minetest.log("error", "[offhand_screen_view] 'offhand' mod not found, disabling.")
    return
end

-- ==== settings (also see settingtypes.txt) ====================
-- Icons are normalised to ICON_PX x ICON_PX pixels so that the scale of the
-- HUD element is independent of the texture pack's resolution.
local ICON_PX = 64

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

local icon_px    = math.floor(get_number("offhand_screen_icon_size", ICON_PX))
local bg_padding = math.floor(get_number("offhand_screen_bg_padding", 6))
local offset_x   = get_number("offhand_screen_offset_x", 130)
local offset_y   = get_number("offhand_screen_offset_y", -110)
local show_bg    = get_bool("offhand_screen_show_background", true)
local show_count = get_bool("offhand_screen_show_count", true)
local use_cubes  = get_bool("offhand_screen_3d_icons", true)
local force_3d   = get_bool("offhand_screen_force_first_person", true)

if icon_px < 8 then icon_px = 8 end
if bg_padding < 0 then bg_padding = 0 end
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
        position  = {x = 0.5, y = 1},
        offset    = {x = offset_x, y = offset_y},
        alignment = {x = 0, y = 0},
        scale     = {x = 1, y = 1},
        text      = icon,
        z_index   = 101,
    })
end

local function add_bg_hud(player)
    local size = icon_px + 2 * bg_padding
    return player:hud_add({
        hud_elem_type = "image",
        type = "image",
        name = "offhand_screen_view_bg",
        position  = {x = 0.5, y = 1},
        offset    = {x = offset_x, y = offset_y},
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
        position  = {x = 0.5, y = 1},
        offset    = {x = offset_x + icon_px / 2, y = offset_y + icon_px / 2},
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

-- The "offhand" mod draws a real 3D item by attaching a "wielditem" entity to
-- the Arm_Left bone of the player model (offhand/wielditem.lua). Attached
-- objects are hidden in first person unless they are attached with
-- forced_visible = true, so we re-attach it with that flag set.
local function is_offhand_wield_entity(child)
    local luaentity = child.get_luaentity and child:get_luaentity()
    local name = luaentity and luaentity.name
    return type(name) == "string" and name:find("offhand") ~= nil
        and name:find("wield") ~= nil
end

function offhand_screen_view.force_first_person_item(player)
    if not force_3d or not player.get_children then return end

    local ok, children = pcall(player.get_children, player)
    if not ok or not children then return end

    for _, child in ipairs(children) do
        if is_offhand_wield_entity(child) and child.get_attach then
            local attached = {pcall(child.get_attach, child)}
            -- attached = {ok, parent, bone, position, rotation, forced_visible}
            if attached[1] and attached[2] and attached[6] ~= true then
                pcall(child.set_attach, child, attached[2], attached[3],
                    attached[4], attached[5], true)
            end
        end
    end
end

function offhand_screen_view.update(player)
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
            offhand_screen_view.force_first_person_item(player)
        end
    end)
end)

minetest.register_on_leaveplayer(function(player)
    huds[player:get_player_name()] = nil
end)

-- react instantly whenever the offhand mod swaps/uses items
offhand.register_on_item_change(function(player, item_before, item_after)
    offhand_screen_view.update(player)
    -- the offhand mod re-attaches its entity here, which resets forced_visible,
    -- so the flag has to be applied afterwards
    offhand_screen_view.force_first_person_item(player)
end)

-- safety net: keeps the icon in sync even if something changes the
-- "offhand" inventory list directly (e.g. drag & drop in a formspec)
-- without going through offhand's own change handlers, and re-applies the
-- forced_visible flag when the offhand mod recreates its entity
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < 0.5 then return end
    timer = 0
    for _, player in ipairs(minetest.get_connected_players()) do
        offhand_screen_view.update(player)
        offhand_screen_view.force_first_person_item(player)
    end
end)