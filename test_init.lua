-- Tests for offhand_screen_view/init.lua
--
-- Runs the real init.lua against a minimal fake minetest/offhand API and checks
-- the textures it builds plus the HUD elements it creates/changes/removes.
--
-- Usage (from the mod folder):  lua5.1 tests/test_init.lua
-- No engine needed, only a Lua interpreter.

local test_path = (arg and arg[0]) or "tests/test_init.lua"
local mod_root = test_path:gsub("tests[/\\]test_init%.lua$", "")
if mod_root == "" then mod_root = "./" end

-- ==== tiny assert helpers ==========================================
local passed, failed = 0, 0

local function ok(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
    end
end

local function eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("FAIL: %s\n  expected: %s\n  actual:   %s",
            msg, tostring(expected), tostring(actual)))
    end
end

-- ==== fake environment =============================================
vector = {
    length = function(v)
        return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    end,
}

local overrides = {}
overrides["offhand_screen_icon_size"] = "64"      -- keep expectations simple
overrides["offhand_screen_show_background"] = true -- exercise the bg element

minetest = {}

minetest.settings = {
    get = function(_, name)
        return overrides[name]
    end,
    get_bool = function(_, name)
        return overrides[name]
    end,
}

local logs = {}
function minetest.log(level, msg)
    table.insert(logs, level .. ": " .. msg)
end

-- ==== fake item/node definitions ===================================
minetest.registered_nodes = {
    -- cubic node, no icon: this is the case that used to show up flat
    ["default:dirt_with_grass"] = {
        type = "node",
        drawtype = "normal",
        tiles = {
            "default_grass.png",
            "default_dirt.png",
            "dt_px.png^default_grass_side.png",
            "dt_nx.png",
            "dt_pz.png^default_grass_side.png",
            "dt_nz.png",
        },
    },
    ["default:stone"] = {
        type = "node",
        drawtype = "normal",
        tiles = {"default_stone.png"},
    },
    ["default:bookshelf"] = {
        type = "node",
        drawtype = "normal",
        tiles = {"default_wood.png"},
        inventory_image = "default_bookshelf.png",
    },
    ["flowers:dandelion_white"] = {
        type = "node",
        drawtype = "plantlike",
        tiles = {"flowers_dandelion_white.png"},
    },
}

minetest.registered_items = {
    ["default:pick_steel"] = {
        type = "tool",
        inventory_image = "default_tool_steelpick.png",
        wield_image = "default_tool_steelpick.png",
    },
    ["default:apple"] = {
        type = "craftitem",
        inventory_image = "default_apple.png",
    },
    ["default:torch"] = {
        type = "node",
        drawtype = "torchlike",
        inventory_image = "default_torch_on_floor.png",
        tiles = {"default_torch_on_floor.png"},
    },
}
for name, def in pairs(minetest.registered_nodes) do
    minetest.registered_items[name] = def
end

-- same implementation as builtin/misc_helpers.lua
local inventorycube_calls = 0
minetest.inventorycube = function(top, left, right)
    inventorycube_calls = inventorycube_calls + 1
    return "[inventorycube{" .. (top:gsub("%^", "&")) ..
        "{" .. (left:gsub("%^", "&")) ..
        "{" .. (right:gsub("%^", "&"))
end

local on_joinplayer, on_leaveplayer, on_globalstep, after_cb
function minetest.register_on_joinplayer(f) on_joinplayer = f end
function minetest.register_on_leaveplayer(f) on_leaveplayer = f end
function minetest.register_globalstep(f) on_globalstep = f end
function minetest.after(_, f) after_cb = f end

local players = {}
function minetest.get_connected_players() return players end

-- ==== fake offhand mod =============================================
local item_change_cb
offhand = {
    stacks = {},
    register_on_item_change = function(f) item_change_cb = f end,
}

local function ItemStack(name, count)
    return {
        name = name,
        count = count or 1,
        get_name = function(self) return self.name end,
        get_count = function(self) return self.count end,
    }
end

function offhand.get_offhand(player)
    return offhand.stacks[player:get_player_name()] or ItemStack("")
end

-- ==== fake player / HUD ============================================
local function new_player(name)
    local p = {
        pname = name,
        huds = {},
        ops = {},
        next_id = 1,
        velocity = {x = 0, y = 0, z = 0},
    }
    function p:get_player_name() return self.pname end
    function p:is_player() return true end
    function p:get_player_velocity() return self.velocity end
    function p:hud_add(def)
        assert(def.hud_elem_type or def.type, "hud_add without element type")
        local id = self.next_id
        self.next_id = id + 1
        self.huds[id] = def
        table.insert(self.ops, {op = "add", id = id, def = def})
        return id
    end
    function p:hud_remove(id)
        assert(self.huds[id], "hud_remove of unknown id " .. tostring(id))
        self.huds[id] = nil
        table.insert(self.ops, {op = "remove", id = id})
    end
    function p:hud_change(id, stat, value)
        assert(self.huds[id], "hud_change of unknown id " .. tostring(id))
        self.huds[id][stat] = value
        table.insert(self.ops, {op = "change", id = id, stat = stat, value = value})
    end
    function p:count_huds()
        local n = 0
        for _ in pairs(self.huds) do n = n + 1 end
        return n
    end
    function p:find_hud(name)
        for id, def in pairs(self.huds) do
            if def.name == name then return id end
        end
        return nil
    end
    table.insert(players, p)
    return p
end

-- ==== load the mod =================================================
local function load_mod()
    local chunk, err = loadfile(mod_root .. "init.lua")
    assert(chunk, "cannot load init.lua: " .. tostring(err))
    local ok, err2 = pcall(chunk)
    assert(ok, "init.lua failed: " .. tostring(err2))
end
load_mod()

-- ==== build_icon / frames ==========================================
local build_icon = offhand_screen_view.build_icon
ok(build_icon ~= nil, "offhand_screen_view.build_icon is exported")
ok(offhand_screen_view.build_icon_frames ~= nil, "build_icon_frames is exported")

local px = "dt_px.png&default_grass_side.png"
local nx = "dt_nx.png"
local pz = "dt_pz.png&default_grass_side.png"
local nz = "dt_nz.png"
local frame1 = "[inventorycube{default_grass.png{" .. px .. "{" .. pz .. "^[resize:64x64"
local frame2 = "[inventorycube{default_grass.png{" .. pz .. "{" .. nx .. "^[resize:64x64"
local frame3 = "[inventorycube{default_grass.png{" .. nx .. "{" .. nz .. "^[resize:64x64"
local frame4 = "[inventorycube{default_grass.png{" .. nz .. "{" .. px .. "^[resize:64x64"

eq(build_icon("default:dirt_with_grass"), frame1,
    "cubic node is rendered as a 3D inventory cube")
ok(inventorycube_calls >= 1, "minetest.inventorycube() is used for escaping")

local frames = offhand_screen_view.build_icon_frames("default:dirt_with_grass")
eq(#frames, 4, "a cubic node gets the four rotation frames")
eq(frames[1], frame1, "frame 1 shows the +X/+Z sides")
eq(frames[2], frame2, "frame 2 is a 90 degree turn")
eq(frames[3], frame3, "frame 3 continues the turn")
eq(frames[4], frame4, "frame 4 closes the turn")

eq(#offhand_screen_view.build_icon_frames("default:pick_steel"), 1,
    "tools do not spin")
eq(build_icon("default:pick_steel"), "default_tool_steelpick.png^[resize:64x64",
    "wield_image is preferred for tools")
eq(build_icon("default:apple"), "default_apple.png^[resize:64x64",
    "craftitems use their inventory_image")
eq(build_icon("default:bookshelf"), "default_bookshelf.png^[resize:64x64",
    "inventory_image is used when the node defines one")
eq(build_icon("default:torch"), "default_torch_on_floor.png^[resize:64x64",
    "sprite drawtypes keep their inventory_image")
eq(build_icon("default:stone"),
    "[inventorycube{default_stone.png{default_stone.png{default_stone.png^[resize:64x64",
    "single tile is repeated on all cube faces")
eq(build_icon("some:unknown_item"), "unknown_item.png^[resize:64x64",
    "unknown items fall back to unknown_item.png")
eq(build_icon(""), nil, "empty itemname gives no icon")
eq(build_icon(nil), nil, "nil itemname gives no icon")

-- ==== HUD handling =================================================
local player = new_player("tester")
offhand_screen_view.update(player)
eq(player:count_huds(), 0, "no HUD while the offhand is empty")

offhand.stacks.tester = ItemStack("default:dirt_with_grass", 1)
item_change_cb(player, ItemStack(""), ItemStack("default:dirt_with_grass"))
eq(player:count_huds(), 3, "background + shadow + icon are added")

local icon_id = player:find_hud("offhand_screen_view_icon")
local bg_id = player:find_hud("offhand_screen_view_bg")
local shadow_id = player:find_hud("offhand_screen_view_shadow")
local count_id = player:find_hud("offhand_screen_view_count")
ok(icon_id ~= nil, "icon element exists")
ok(bg_id ~= nil, "background element exists (enabled for this test)")
ok(shadow_id ~= nil, "shadow element exists")
eq(count_id, nil, "no stack counter for a single item")
eq(player.huds[icon_id].text, frame1, "the HUD element carries the 3D cube texture")
eq(player.huds[shadow_id].text, frame1 .. "^[multiply:#000000^[opacity:90",
    "the shadow is a dark silhouette of the icon")
eq(player.huds[bg_id].text, "[fill:76x76:#00000066",
    "background is sized icon + padding")

local ops_before = #player.ops
offhand_screen_view.update(player)
eq(#player.ops, ops_before, "no HUD traffic when nothing changed")

-- the cube turns one frame per spin step
on_globalstep(0.41)
eq(player.huds[icon_id].text, frame2, "the cube turns on the spin timer")
eq(player.huds[shadow_id].text, frame2 .. "^[multiply:#000000^[opacity:90",
    "the shadow follows the turning cube")

-- stack size shows up as a counter
offhand.stacks.tester = ItemStack("default:dirt_with_grass", 5)
offhand_screen_view.update(player)
count_id = player:find_hud("offhand_screen_view_count")
ok(count_id ~= nil, "stack counter appears when the count grows")
eq(player.huds[count_id].text, "5", "stack counter shows the count")

-- swapping the item only updates the icon texture
offhand.stacks.tester = ItemStack("default:pick_steel", 1)
item_change_cb(player, ItemStack("default:dirt_with_grass"), ItemStack("default:pick_steel"))
eq(player.huds[icon_id].text, "default_tool_steelpick.png^[resize:64x64",
    "icon texture follows the new item")
eq(player:count_huds(), 3, "stack counter is gone again")

-- walking makes the icon sway
player.velocity = {x = 4, y = 0, z = 0}
on_globalstep(0.11)
local off = player.huds[icon_id].offset
ok(off and (off.x ~= 0 or off.y ~= 0), "the icon bobs while walking")
player.velocity = {x = 0, y = 0, z = 0}
on_globalstep(0.11)
off = player.huds[icon_id].offset
ok(off and off.x == 0 and off.y == 0, "the icon settles when standing still")

-- emptying the offhand removes every element
offhand.stacks.tester = ItemStack("")
offhand_screen_view.update(player)
eq(player:count_huds(), 0, "all HUD elements are removed for an empty offhand")

-- a stack of blocks also gets a counter
local other = new_player("other")
offhand.stacks.other = ItemStack("default:stone", 3)
offhand_screen_view.update(other)
eq(other:count_huds(), 4, "background + shadow + icon + counter for a stack of blocks")

-- joining re-reads the offhand after the mod had time to set it up
local newcomer = new_player("newbie")
on_joinplayer(newcomer)
eq(newcomer:count_huds(), 0, "nothing is drawn before the delayed update runs")
offhand.stacks.newbie = ItemStack("default:apple", 2)
after_cb()
eq(newcomer:count_huds(), 4, "the delayed join update draws the icon")

-- leaving the game drops the stale HUD ids
on_leaveplayer(other)
for id in pairs(other.huds) do other.huds[id] = nil end
offhand_screen_view.update(other)
eq(other:count_huds(), 4, "a returning player gets fresh HUD elements")

-- ==== hiding the base offhand mod's icon ===========================
local base_ids = {slot = 10, item = 11, wear_bar = 12}
offhand[player] = {hud = base_ids}
for _, id in pairs(base_ids) do
    player.huds[id] = {name = "base", offset = {x = 0, y = 0}}
end

-- by default the base icon is left visible
offhand_screen_view.hide_base_hud(player)
eq(player.huds[11].offset.x, 0, "base icon stays visible by default")

-- enabling the setting parks every base element off-screen
overrides["offhand_screen_hide_base_icon"] = true
offhand_screen_view = nil
load_mod()
offhand_screen_view.hide_base_hud(player)
for key, id in pairs(base_ids) do
    eq(player.huds[id].offset.x, -100000, "base hud '" .. key .. "' parked offscreen")
end
overrides["offhand_screen_hide_base_icon"] = nil
offhand[player] = nil
offhand_screen_view = nil
load_mod()

-- ==== show_icon = false removes our HUD ============================
overrides["offhand_screen_show_icon"] = false
offhand_screen_view = nil
load_mod()
for id in pairs(player.huds) do player.huds[id] = nil end -- engine keeps HUDs across reloads; the fake does not
offhand.stacks.tester = ItemStack("default:stone", 1)
offhand_screen_view.update(player)
eq(player:count_huds(), 0, "no icon is drawn when show_icon is off")
overrides["offhand_screen_show_icon"] = nil
offhand_screen_view = nil
load_mod()

-- ==== fallback without minetest.inventorycube ======================
local saved = minetest.inventorycube
minetest.inventorycube = nil
offhand_screen_view = nil
load_mod()
eq(offhand_screen_view.build_icon("default:dirt_with_grass"), frame1,
    "manual caret escaping matches minetest.inventorycube()")
minetest.inventorycube = saved

-- ==== flat icons setting ==========================================
overrides["offhand_screen_3d_icons"] = false
offhand_screen_view = nil
load_mod()
eq(offhand_screen_view.build_icon("default:stone"), "default_stone.png^[resize:64x64",
    "3d icons can be turned off")
overrides["offhand_screen_3d_icons"] = nil

-- ==== default icon size ===========================================
overrides["offhand_screen_icon_size"] = nil
offhand_screen_view = nil
minetest.inventorycube = saved
load_mod()
eq(offhand_screen_view.build_icon("default:stone"),
    "[inventorycube{default_stone.png{default_stone.png{default_stone.png^[resize:380x380",
    "icons default to 380 px")

-- leave the module in its default configuration
offhand_screen_view = nil
load_mod()

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end