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