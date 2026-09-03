-- offhand_screen_view - client-side companion mod
--
-- The server cannot see which camera mode (first / second / third person)
-- the client is in, so this mod reads it every frame and reports changes to
-- the server mod "offhand_screen_view" over the "offhand_screen_view" mod
-- channel ("FP <mode>", 0 = first person, 1/2 = third person). The server
-- then hides the offhand HUD icon while the view is not first person.
--
-- INSTALL (on the client):
--   1. Copy this folder to <minetest user dir>/clientmods/offhand_screen_view/
--      (on Windows: C:\Users\<you>\AppData\minetest\clientmods\offhand_screen_view\)
--   2. In minetest.conf set:  enable_client_modding = true
--   3. In <minetest user dir>/clientmods/mods.conf add:
--         load_mod_offhand_screen_view = true
--   The SERVER side additionally needs:  enable_mod_channels = true
--
-- Without this mod installed the server mod simply keeps the icon visible in
-- every view (the old behaviour).

local CHANNEL_NAME = "offhand_screen_view"

local channel = nil
local last_mode = nil

core.register_globalstep(function()
    if not channel then
        if not core.mod_channel_join then return end
        channel = core.mod_channel_join(CHANNEL_NAME)
        return
    end

    if not channel:is_writable() then
        -- channel not ready yet (or temporarily dropped): forget the last
        -- reported mode so it is sent again once the channel is usable
        last_mode = nil
        return
    end

    if not core.camera or not core.camera.get_camera_mode then return end

    local mode = core.camera:get_camera_mode()
    if mode == last_mode then return end
    last_mode = mode
    channel:send_message("FP " .. tostring(mode))
end)
