-- offhand_screen_view
--
-- Add-on for the "offhand" mod (SFENCE / t-affeldt fork of mcl_offhand).
-- Shows the item currently held in the offhand as an on-screen element.
-- With the bundled client-side companion mod (clientmods/) installed the icon
-- is shown ONLY in first person and disappears automatically in 2nd/3rd
-- person; without it the icon is drawn in both views.
--
-- WHAT THIS MOD DOES
-- * Renders the item through the [inventorycube texture modifier (the same
--   software 3D renderer the engine uses for the hotbar cubes), so blocks
--   look like shaded cubes instead of a flat tile, and tools use their
--   wield_image.
-- * Makes the cube feel like a held 3D object instead of a pasted sticker:
--     - it slowly turns (the four isometric rotations of the cube are cycled),
--     - it casts a soft drop shadow,
--     - it bobs while you walk.
-- * Draws it large, anchored to the lower-left corner (the mirror image of
--   the engine's main-hand wield view, which sits in the lower right). The
--   position is a fraction of the screen, so it works on any resolution.
-- * Optionally hides the small icon the base "offhand" mod draws next to the
--   hotbar (offhand_screen_hide_base_icon, OFF by default).
--
-- WHY NOT A REAL SECOND 3D HAND?
-- * The engine renders exactly ONE first-person wield model (the main hand);
--   a second one is an open engine feature request (luanti#10345), so no mod
--   can add it.
-- * The base mod's real 3D item is attached to the Arm_Left bone. Attached
--   objects are hidden in first person unless attached with forced_visible,
--   but in first person the client does NOT apply the local player's bone
--   transforms, so the item shows up floating at your feet. A screen-anchored
--   HUD element is the only thing that can sit at "hand height" in view.
--
-- INSTALL: put this folder next to the "offhand" mod folder in your
-- world/game mods directory and enable it like any other mod.

offhand_screen_view = {}

-- The base "offhand" mod is optional: if it is present we use its API, and if
-- it is missing (or loads after us) we read the "offhand" inventory list
-- directly, so this mod never hard-fails at startup.
local offhand_api = nil

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
local icon_px     = math.floor(get_number("offhand_screen_icon_size", 380))
local bg_pad      = math.floor(get_number("offhand_screen_bg_padding", 6))
local pos_x       = get_number("offhand_screen_pos_x", 0.12)
local pos_y       = get_number("offhand_screen_pos_y", 0.88)
local show_icon   = get_bool("offhand_screen_show_icon", true)
local show_bg     = get_bool("offhand_screen_show_background", false)
local show_count  = get_bool("offhand_screen_show_count", true)
local use_cubes   = get_bool("offhand_screen_3d_icons", true)
local hide_base   = get_bool("offhand_screen_hide_base_icon", false)
local use_spin    = get_bool("offhand_screen_spin", true)
local spin_period = math.max(0.4, get_number("offhand_screen_spin_period", 1.6))
local use_shadow  = get_bool("offhand_screen_shadow", true)
local use_bob     = get_bool("offhand_screen_bob", true)
local first_person_only = get_bool("offhand_screen_first_person_only", true)

if icon_px < 8 then icon_px = 8 end
if bg_pad < 0 then bg_pad = 0 end
-- =================================================================

local huds = {}
-- [player_name] = { icon=id, bg=id, shadow=id, count=id,
--                   itemname="", count_n=0, frames={}, frame_i=1,
--                   bob_x=0, bob_y=0 }

-- camera mode per player, reported by the optional client-side companion mod
-- over the "offhand_screen_view" mod channel: 0 = first person, 1/2 = third
-- person (back/front). nil while unknown (client mod absent or not joined).
local cam_modes = {}

local function is_first_person(pname)
    if not first_person_only then
        return true
    end
    local mode = cam_modes[pname]
    -- without the client mod we cannot tell the view: keep the old behaviour
    return mode == nil or mode == 0
end

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

local function silhouette(tex)
    return tex .. "^[multiply:#000000^[opacity:90"
end

-- Returns the stack held in the offhand: via the base mod's API when it is
-- available, otherwise straight from the "offhand" inventory list (which the
-- base mod creates; size 0 if nobody created it).
local function get_offhand_stack(player)
    if offhand_api then
        local ok, stack = pcall(offhand_api.get_offhand, player)
        if ok and stack then
            return stack
        end
    end
    local inv = player.get_inventory and player:get_inventory()
    if inv and inv.get_size and inv:get_size("offhand") > 0 then
        return inv:get_stack("offhand", 1)
    end
    return nil
end

-- Builds the animation frames of the HUD icon. Cubic nodes get the four
-- isometric rotations of their cube (cycling them reads as a turning 3D
-- object); everything else gets a single static frame.
-- Priority mirrors what the engine puts into the main hand:
--   wield_image -> inventory_image -> 3D cube built from the node tiles.
function offhand_screen_view.build_icon_frames(itemname)
    if not itemname or itemname == "" then
        return nil
    end

    local def = minetest.registered_items[itemname]
    if not def then
        return {normalized("unknown_item.png")}
    end

    if def.wield_image and def.wield_image ~= "" then
        return {normalized(def.wield_image)}
    end

    if def.inventory_image and def.inventory_image ~= "" then
        return {normalized(def.inventory_image)}
    end

    local tiles = def.tiles
    if tiles and tiles[1] then
        local top = get_tile_name(tiles[1])
        if top and top ~= "" then
            local is_node = minetest.registered_nodes[itemname] ~= nil
            if use_cubes and is_node and not FLAT_DRAWTYPES[def.drawtype] then
                local t1 = top
                local t3 = get_tile_name(tiles[3] or tiles[1])
                local t5 = get_tile_name(tiles[5] or tiles[3] or tiles[1])
                local t4 = get_tile_name(tiles[4] or tiles[3] or tiles[1])
                local t6 = get_tile_name(tiles[6] or tiles[5] or tiles[3] or tiles[1])
                -- one full turn, 90 degrees per frame: which side faces the
                -- left/right of the isometric view
                return {
                    normalized(inventorycube(t1, t3, t5)),
                    normalized(inventorycube(t1, t5, t4)),
                    normalized(inventorycube(t1, t4, t6)),
                    normalized(inventorycube(t1, t6, t3)),
                }
            end
            return {normalized(top)}
        end
    end

    return {normalized("unknown_item.png")}
end

function offhand_screen_view.build_icon(itemname)
    local frames = offhand_screen_view.build_icon_frames(itemname)
    return frames and frames[1] or nil
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

local function add_shadow_hud(player, icon)
    return player:hud_add({
        hud_elem_type = "image",
        type = "image",
        name = "offhand_screen_view_shadow",
        position  = {x = pos_x, y = pos_y},
        offset    = {x = 10, y = 10},
        alignment = {x = 0, y = 0},
        scale     = {x = 1, y = 1},
        text      = silhouette(icon),
        z_index   = 100,
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
        z_index   = 99,
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
    for _, key in ipairs({"bg", "shadow", "icon", "count"}) do
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
    local data = offhand_api and offhand_api[player]
    if type(data) ~= "table" or type(data.hud) ~= "table" then return end
    for _, id in pairs(data.hud) do
        if type(id) == "number" then
            pcall(player.hud_change, player, id, "offset",
                {x = -100000, y = -100000})
        end
    end
end

local function set_item(player, data, itemname)
    data.frames = offhand_screen_view.build_icon_frames(itemname) or {}
    data.frame_i = 1
    data.itemname = itemname
    player:hud_change(data.icon, "text", data.frames[1] or "")
    if data.shadow then
        player:hud_change(data.shadow, "text", silhouette(data.frames[1] or ""))
    end
end

function offhand_screen_view.update(player)
    if not player or not player:is_player() then return end
    local pname = player:get_player_name()

    if not show_icon then
        remove_huds(player)
        return
    end

    -- first-person-only mode: the companion client mod (see the bottom of
    -- this file) reports the camera mode over a mod channel; while the view
    -- is 2nd/3rd person the whole HUD is torn down. With no report from the
    -- client the icon stays visible, like the old behaviour.
    if not is_first_person(pname) then
        remove_huds(player)
        return
    end

    local stack = get_offhand_stack(player)
    if not stack then
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
        data = {itemname = "", count_n = count}
        if show_bg then
            data.bg = add_bg_hud(player)
        end
        if use_shadow then
            data.shadow = add_shadow_hud(player, "unknown_item.png")
        end
        data.icon = add_icon_hud(player, "unknown_item.png")
        set_item(player, data, itemname)
        if show_count and count > 1 then
            data.count = add_count_hud(player, count)
        end
        huds[pname] = data
        return
    end

    if data.itemname ~= itemname then
        set_item(player, data, itemname)
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

-- turns the cube one frame further
function offhand_screen_view.spin(player)
    if not use_spin then return end
    local data = huds[player:get_player_name()]
    if not data or not data.frames or #data.frames < 2 then return end
    data.frame_i = data.frame_i % #data.frames + 1
    local frame = data.frames[data.frame_i]
    player:hud_change(data.icon, "text", frame)
    if data.shadow then
        player:hud_change(data.shadow, "text", silhouette(frame))
    end
end

-- makes the icon sway while the player walks, like a carried object
function offhand_screen_view.bob(player, clock)
    if not use_bob then return end
    local data = huds[player:get_player_name()]
    if not data then return end

    local bx, by = 0, 0
    if player.get_player_velocity and vector and vector.length then
        local ok, vel = pcall(player.get_player_velocity, player)
        if ok and vel and vector.length(vel) > 1 then
            bx = math.cos(clock * 9) * 5
            by = math.sin(clock * 18) * 6
        end
    end

    if bx == data.bob_x and by == data.bob_y then return end
    data.bob_x, data.bob_y = bx, by

    player:hud_change(data.icon, "offset", {x = bx, y = by})
    if data.shadow then
        player:hud_change(data.shadow, "offset", {x = bx + 10, y = by + 10})
    end
    if data.count then
        player:hud_change(data.count, "offset",
            {x = icon_px / 2 - 12 + bx, y = icon_px / 2 - 12 + by})
    end
end

minetest.register_on_joinplayer(function(player)
    huds[player:get_player_name()] = nil
    cam_modes[player:get_player_name()] = nil
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
    cam_modes[player:get_player_name()] = nil
end)

-- react instantly whenever the offhand mod swaps/uses items; the base mod may
-- not be loaded yet (it can come after us), so this is wired up in bind()
local function bind(api)
    offhand_api = api
    if type(api.register_on_item_change) == "function" then
        api.register_on_item_change(function(player, item_before, item_after)
            offhand_screen_view.update(player)
            offhand_screen_view.hide_base_hud(player)
        end)
    end
end

-- duck-type the base mod: t-affeldt / SFENCE expose `offhand`, MCL2 exposes
-- `mcl_offhand`; both provide get_offhand()
local function find_offhand()
    for _, name in ipairs({"offhand", "mcl_offhand"}) do
        local candidate = _G[name]
        if type(candidate) == "table"
                and type(candidate.get_offhand) == "function" then
            return candidate
        end
    end
    return nil
end

local function try_bind(deferred)
    local api = find_offhand()
    if api then
        bind(api)
        return true
    end
    if deferred then
        minetest.log("warning", "[offhand_screen_view] base 'offhand' mod not "
            .. "detected; reading the 'offhand' inventory list directly. The "
            .. "icon appears as soon as that list holds an item.")
    end
    return false
end

if not try_bind(false) and minetest.register_on_mods_loaded then
    minetest.register_on_mods_loaded(function()
        try_bind(true)
    end)
end

-- safety net + animations:
-- * every 0.5 s the icon is resynced with the "offhand" inventory list, in
--   case something changed it without going through offhand's own handlers
--   (e.g. drag & drop in a formspec)
-- * the cube is turned and the walk-bob applied continuously
local sync_timer = 0
local spin_timer = 0
local bob_timer = 0
minetest.register_globalstep(function(dtime)
    sync_timer = sync_timer + dtime
    spin_timer = spin_timer + dtime
    bob_timer = bob_timer + dtime

    local do_sync = sync_timer >= 0.5
    local do_spin = spin_timer >= spin_period / 4
    local do_bob = bob_timer >= 0.1
    if not (do_sync or do_spin or do_bob) then return end

    if do_sync then sync_timer = 0 end
    if do_spin then spin_timer = 0 end
    if do_bob then bob_timer = 0 end

    local clock = os.clock()
    for _, player in ipairs(minetest.get_connected_players()) do
        if do_sync then
            offhand_screen_view.update(player)
            offhand_screen_view.hide_base_hud(player)
        end
        if do_spin then
            offhand_screen_view.spin(player)
        end
        if do_bob then
            offhand_screen_view.bob(player, clock)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Camera-mode reports from the optional client-side companion mod
--
-- The server has no API for the camera mode the client is currently in
-- (player:get_camera() only returns server-imposed restrictions), so the
-- companion mod in clientmods/offhand_screen_view/init.lua sends
-- "FP <mode>" (0 = first person, 1/2 = third person) over the
-- "offhand_screen_view" mod channel whenever the view changes.
--
-- For the auto-hiding to work:
--   client minetest.conf:  enable_client_modding = true
--                          and the client mod enabled in
--                          <minetest>/clientmods/mods.conf
--   server minetest.conf:  enable_mod_channels = true
--
-- If no client mod is installed, no messages arrive and the icon is simply
-- always visible (the pre-companion behaviour).
-- ---------------------------------------------------------------------------
local CHANNEL_NAME = "offhand_screen_view"

if first_person_only and minetest.mod_channel_join
        and minetest.register_on_modchannel_message then
    minetest.mod_channel_join(CHANNEL_NAME)

    minetest.register_on_modchannel_message(function(channel_name, sender, message)
        if channel_name ~= CHANNEL_NAME or sender == "" then return end
        local mode = tonumber(tostring(message):match("^FP (%d+)$"))
        if mode == nil or mode < 0 or mode > 2 then return end
        if cam_modes[sender] == mode then return end
        cam_modes[sender] = mode
        local player = minetest.get_player_by_name(sender)
        if player then
            offhand_screen_view.update(player)
        end
    end)
end