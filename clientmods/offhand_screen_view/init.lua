-- offhand_screen_view - client-side companion mod
--
-- The server never receives the "change camera" keypress (it is a purely
-- local client action, like taking a screenshot), so the server cannot count
-- view switches. This mod reads the actual camera mode every frame with
-- core.camera:get_camera_mode() and reports changes to the server mod
-- "offhand_screen_view" over the "offhand_screen_view" mod channel
-- ("FP <mode>", 0 = first person, 1/2 = third person). The server then hides
-- the offhand HUD icon while the view is not first person.
--
-- INSTALL (on the client):
--   1. Copy this folder to <minetest user dir>/clientmods/offhand_screen_view/
--      (the user dir is the folder that contains your minetest.conf;
--       on a standard Windows install:
--       C:\Users\<you>\AppData\minetest\clientmods\offhand_screen_view\)
--   2. In minetest.conf set:  enable_client_modding = true
--   3. In <minetest user dir>/clientmods/mods.conf add:
--         load_mod_offhand_screen_view = true
--   4. In the SAME minetest.conf (server side) set:  enable_mod_channels = true
--   5. Restart the game. In-world, type /osv_status in the chat to check the
--      companion's state.
--
-- Without this mod installed the server mod simply keeps the icon visible in
-- every view (the old behaviour).

local CHANNEL_NAME = "offhand_screen_view"

local channel = nil
local last_mode = nil
local sent_count = 0

local function camera_mode()
    if core.camera and core.camera.get_camera_mode then
        return core.camera:get_camera_mode()
    end
    return nil
end

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

    local mode = camera_mode()
    if mode == nil then return end
    if mode == last_mode then return end
    last_mode = mode
    sent_count = sent_count + 1
    channel:send_message("FP " .. tostring(mode))
end)

-- diagnostic command: /osv_status
core.register_chatcommand("osv_status", {
    description = "Offhand Screen View: estado del companion cliente",
    func = function()
        local mode = camera_mode()
        local names = {
            [0] = "primera persona",
            [1] = "tercera persona (atras)",
            [2] = "tercera persona (frente)",
        }
        local state
        if not core.mod_channel_join then
            state = "este cliente no tiene mod channels"
        elseif not channel then
            state = "canal todavia no unido"
        elseif not channel:is_writable() then
            state = "canal unido pero NO escribible: falta "
                .. "enable_mod_channels = true en el servidor/minetest.conf"
        else
            state = "canal OK, reportes enviados: " .. sent_count
        end
        return true, "OSV | camara: "
            .. (names[mode] or tostring(mode))
            .. " | " .. state
    end,
})
