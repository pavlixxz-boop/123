--[[
    ╔══════════════════════════════════════════════════════════╗
    ║                       ASTRUM                             ║
    ║              Maximum Accuracy Resolver                   ║
    ╚══════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

local is_on_ground = false
local ticks = 0
local helpers = {}

function helpers.get_state()
    local me = entity.get_local_player()
    if not entity.is_alive(me) then 
        return 'Global' 
    end

    -- Check for fake duck first (use direct reference since 'reference' table is not defined yet)
    local fake_duck_ref = ui.reference("RAGE", "Other", "Duck peek assist")
    if fake_duck_ref and ui.get(fake_duck_ref) then
        return 'Fake duck'
    end

    local vel = {entity.get_prop(me, 'm_vecVelocity')}
    local speed = math.sqrt((vel[1] or 0)^2 + (vel[2] or 0)^2)

    local ground_entity = entity.get_prop(me, 'm_hGroundEntity')
    local is_on_player = ground_entity ~= 0 and entity.get_classname(ground_entity) == 'CCSPlayer'
    ticks = (ground_entity == 0) and (ticks + 1) or 0

    if is_on_player then
        is_on_ground = true
    end

    if not is_on_ground then 
        return (entity.get_prop(me, 'm_flDuckAmount') == 1) and 'Air+' or 'Air'
    end

    if is_on_ground and entity.get_prop(me, 'm_flDuckAmount') == 1 then
        return (speed > 10) and 'Sneak' or 'Crouch'
    end

    return (speed > 10) and 'Run' or 'Stand'
end

-- ═══════════════════════════════════════════════════════════
-- MODULES
-- ═══════════════════════════════════════════════════════════

local ffi = require('ffi')
local pui = require('gamesense/pui')
local base64 = require('gamesense/base64')
local clipboard = require('gamesense/clipboard')
local string_tables = require('gamesense/string_tables')
local http = require('gamesense/http')

-- ═══════════════════════════════════════════════════════════
-- AA ICON REPLACEMENT
-- ═══════════════════════════════════════════════════════════

local original_aa_icon = nil

if not _G.astrum_icon_patched then
    local function patch_aa_icon()
        local tabs = {"RAGE", "AA", "LEGIT", "VISUALS", "MISC", "SKINS", "PLIST", "Tab"}
        local tabsptr = ffi.cast("intptr_t*", 0x434799AC + 0x54)
        local tabsinfo = {}
        
        for i = 0, #tabs do
            local tab = ffi.cast("int*", tabsptr[0])[i]
            tabsinfo[i] = { 
                id = ffi.cast("int*", tab + 0x80), 
                offset = ffi.cast("int*", tab + 0x84), 
                width = ffi.cast("int*", tab + 0x8C), 
                height = ffi.cast("int*", tab + 0x90)
            }
        end
        
        -- Save original icon
        for i = 0, #tabs do
            if tabs[i + 1] == "AA" then
                original_aa_icon = {
                    id = tabsinfo[i].id[0],
                    width = tabsinfo[i].width[0],
                    height = tabsinfo[i].height[0]
                }
                break
            end
        end
        
        local icon_url = "https://raw.githubusercontent.com/pavlixxz-boop/123/main/square-image%20(7)%20(1).png"
        
        http.get(icon_url, function(status, response)
            if status and response.body then
                local texture_id = renderer.load_png(response.body)
                if not texture_id or texture_id <= 0 then texture_id = renderer.load_png(response.body, 32, 32) end
                if not texture_id or texture_id <= 0 then texture_id = renderer.load_png(response.body, 64, 64) end
                
                if texture_id and texture_id > 0 then
                    -- Store globally for watermark
                    _G.astrum_icon_texture = texture_id
                    
                    for i = 0, #tabs do
                        if tabs[i + 1] == "AA" then
                            tabsinfo[i].id[0] = texture_id
                            tabsinfo[i].width[0] = 64
                            tabsinfo[i].height[0] = 64
                            _G.astrum_icon_patched = true
                            client.log("[ASTRUM] AA icon replaced successfully")
                            break
                        end
                    end
                else
                    client.log("[ASTRUM] Failed to load PNG texture")
                end
            else
                client.log("[ASTRUM] Failed to download icon")
            end
        end)
        
        -- Load watermark icon separately
        local watermark_icon_url = "https://raw.githubusercontent.com/pavlixxz-boop/123/main/free-icon-neon-planet-17335894%20(1).png"
        http.get(watermark_icon_url, function(status, response)
            if status and response.body then
                local texture_id = renderer.load_png(response.body, 64, 64)
                if texture_id and texture_id > 0 then
                    _G.astrum_watermark_icon = texture_id
                    client.log("[ASTRUM] Watermark icon loaded successfully")
                end
            end
        end)
    end
    
    client.delay_call(0.001, patch_aa_icon)
end

-- Restore original icon on shutdown
client.set_event_callback('shutdown', function()
    if original_aa_icon then
        local tabs = {"RAGE", "AA", "LEGIT", "VISUALS", "MISC", "SKINS", "PLIST", "Tab"}
        local tabsptr = ffi.cast("intptr_t*", 0x434799AC + 0x54)
        local tabsinfo = {}
        
        for i = 0, #tabs do
            local tab = ffi.cast("int*", tabsptr[0])[i]
            tabsinfo[i] = { 
                id = ffi.cast("int*", tab + 0x80), 
                width = ffi.cast("int*", tab + 0x8C), 
                height = ffi.cast("int*", tab + 0x90)
            }
        end
        
        for i = 0, #tabs do
            if tabs[i + 1] == "AA" then
                tabsinfo[i].id[0] = original_aa_icon.id
                tabsinfo[i].width[0] = original_aa_icon.width
                tabsinfo[i].height[0] = original_aa_icon.height
                break
            end
        end
    end
end)

-- Nickname changer FFI
local function follow_instruction(address)
    local ptr = ffi.cast("uint8_t*", address)
    if ptr[0] == 232 then
        return ptr + ffi.cast("int32_t*", ptr + 1)[0] + 5
    elseif ptr[0] == 255 and ptr[1] == 21 then
        return ffi.cast("uint32_t**", ffi.cast("const char*", address) + 2)[0][0]
    else
        error(string.format("unknown instruction to follow: %02X!", ptr[0]))
    end
end

local player_info_t = ffi.typeof([[
    struct {
        uint64_t version;
        uint64_t xuid;
        char name[128];
        int userid;
        char guid[33];
        uint32_t friendsid;
        char friendsname[128];
        bool isbot;
        bool ishltv;
        uint32_t customfiles[4];
        uint8_t filesdownloaded;
    }
]])
local player_info_ptr_t = ffi.typeof("$*", player_info_t)
local set_clan_tag_fn = ffi.cast("char*(__thiscall*)(void*, const char*)", follow_instruction(client.find_signature("client.dll", "\xE8\xCC\xCC\xCC̉\x87\x1C\x03\x00\x00")))
local engine_client = ffi.cast("void**", ffi.cast("char*", client.find_signature("client.dll", "\xB9\xCC\xCC\xCC\xCC\xE8\xCC\xCC\xCC̉\x06")) + 1)[0]

local nickname_changer = {
    enabled = false,
    text = "",
    last_name = nil,
    original_name = nil
}

local function set_client_name(name)
    local local_player = entity.get_local_player()
    if local_player == nil then return end
    
    local userinfo = string_tables.userinfo
    if userinfo == nil then return end
    
    local player_info = ffi.cast(player_info_ptr_t, userinfo:get_user_data(local_player - 1))
    if player_info == nil then return end
    
    local current_name = ffi.string(player_info.name)
    if current_name ~= nickname_changer.last_name then
        nickname_changer.original_name = current_name
    end
    
    name = name or nickname_changer.original_name
    if name == nil then return end
    
    ffi.copy(player_info.name, name)
    
    local clan_tag = set_clan_tag_fn(engine_client, name)
    if clan_tag ~= nil then
        ffi.copy(clan_tag, name)
    end
    
    nickname_changer.last_name = name
end

-- ═══════════════════════════════════════════════════════════
-- EXPLOITS HELPER
-- ═══════════════════════════════════════════════════════════

local exploits do
    local g_ctx = {
        local_player = nil,
        weapon = nil,
        aimbot = ui.reference("RAGE","Aimbot","Enabled"),
        doubletap = {ui.reference("RAGE","Aimbot","Double tap")},
        hideshots = {ui.reference("AA","Other","On shot anti-aim")},
        fakeduck = ui.reference("RAGE","Other","Duck peek assist")
    }
    
    local clamp = function(value, min, max)
        return math.min(math.max(value, min), max)
    end
    
    exploits = {
        max_process_ticks = (math.abs(client.get_cvar("sv_maxusrcmdprocessticks") or 16) - 1),
        tickbase_difference = 0,
        ticks_processed = 0,
        command_number = 0,
        choked_commands = 0,
        need_force_defensive = false,
        
        reset_vars = function(self)
            self.ticks_processed = 0
            self.tickbase_difference = 0
            self.choked_commands = 0
            self.command_number = 0
        end,
        
        store_vars = function(self, ctx)
            self.command_number = ctx.command_number or 0
            self.choked_commands = ctx.chokedcommands or 0
        end,
        
        store_tickbase_difference = function(self, ctx)
            if ctx.command_number == self.command_number then
                local tickbase = entity.get_prop(g_ctx.local_player, "m_nTickBase") or 0
                self.ticks_processed = clamp(math.abs(tickbase - (self.tickbase_difference or 0)), 0, (self.max_process_ticks or 0) - (self.choked_commands or 0))
                self.tickbase_difference = math.max(tickbase, self.tickbase_difference or 0)
                self.command_number = 0
            end
        end,
        
        is_doubletap = function(self)
            return ui.get(g_ctx.doubletap[2])
        end,
        
        is_hideshots = function(self)
            return ui.get(g_ctx.hideshots[2])
        end,
        
        is_active = function(self)
            return self:is_doubletap() or self:is_hideshots()
        end,
        
        in_defensive = function(self, max)
            max = max or self.max_process_ticks
            return self:is_active() and (self.ticks_processed > 1 and self.ticks_processed < max)
        end,
        
        is_defensive_ended = function(self)
            return not self:in_defensive() or ((self.ticks_processed >= 0 and self.ticks_processed <= 5) and (self.tickbase_difference or 0) > 0)
        end,
        
        should_force_defensive = function(self, state)
            if not self:is_active() then return false end
            self.need_force_defensive = state and self:is_defensive_ended()
        end,
        
        in_recharge = function(self)
            if not self:is_active() or self:in_defensive() then return false end
            
            local latency_shift = math.ceil(toticks(client.latency()) * 1.25)
            local current_shift_amount = (((self.tickbase_difference or 0) - globals.tickcount()) * -1) + latency_shift
            local max_shift_amount = (self.max_process_ticks - 1) - latency_shift
            local min_shift_amount = -(self.max_process_ticks - 1) + latency_shift
            
            if latency_shift ~= 0 then
                return current_shift_amount > min_shift_amount and current_shift_amount < max_shift_amount
            else
                return current_shift_amount > (min_shift_amount / 2) and current_shift_amount < (max_shift_amount / 2)
            end
        end
    }
    
    client.set_event_callback('setup_command', function(ctx)
        if not (entity.get_local_player() and entity.is_alive(entity.get_local_player())) then return end
        g_ctx.local_player = entity.get_local_player()
        g_ctx.weapon = entity.get_player_weapon(g_ctx.local_player)
        
        -- Apply force defensive if needed (embertrash logic)
        if exploits.need_force_defensive then
            ctx.force_defensive = true
        end
    end)
    
    client.set_event_callback('run_command', function(ctx)
        exploits:store_vars(ctx)
    end)
    
    client.set_event_callback('predict_command', function(ctx)
        exploits:store_tickbase_difference(ctx)
    end)
    
    client.set_event_callback('player_death', function(ctx)
        if not (ctx.userid and ctx.attacker) then return end
        if g_ctx.local_player ~= client.userid_to_entindex(ctx.userid) then return end
        exploits:reset_vars()
    end)
    
    client.set_event_callback('round_start', function()
        exploits:reset_vars()
    end)
end

-- ═══════════════════════════════════════════════════════════
-- REFERENCES
-- ═══════════════════════════════════════════════════════════

local reference = {
    rage = {
        aimbot = {
            enabled = {pui.reference('rage', 'aimbot', 'enabled')},
            double_tap = {pui.reference('rage', 'aimbot', 'double tap')},
            force_body = pui.reference('rage', 'aimbot', 'force body aim'),
            force_safe = pui.reference('rage', 'aimbot', 'force safe point'),
            minimum_damage_override = {pui.reference('rage', 'aimbot', 'minimum damage override')},
            minimum_hitchance = pui.reference('rage', 'aimbot', 'minimum hit chance')
        },
        other = {
            quickpeek = {pui.reference('rage', 'other', 'quick peek assist')},
            fake_duck = pui.reference('rage', 'other', 'duck peek assist')
        },
        ps = {pui.reference('misc', 'miscellaneous', 'ping spike')}
    },
    antiaim = {
        angles = {
            enabled = pui.reference('aa', 'anti-aimbot angles', 'enabled'),
            pitch = {pui.reference('aa', 'anti-aimbot angles', 'pitch')},
            yaw = {pui.reference('aa', 'anti-aimbot angles', 'yaw')},
            yaw_base = pui.reference('aa', 'anti-aimbot angles', 'yaw base'),
            yaw_jitter = {pui.reference('aa', 'anti-aimbot angles', 'yaw jitter')},
            body_yaw = {pui.reference('aa', 'anti-aimbot angles', 'body yaw')},
            fs_body_yaw = pui.reference('aa', 'anti-aimbot angles', 'freestanding body yaw'),
            freestanding = {pui.reference('aa', 'anti-aimbot angles', 'freestanding')},
            edge_yaw = pui.reference('aa', 'anti-aimbot angles', 'edge yaw'),
            roll = pui.reference('aa', 'anti-aimbot angles', 'roll')
        },
        fakelag = {
            enabled = pui.reference('aa', 'fake lag', 'enabled'),
            amount = pui.reference('aa', 'fake lag', 'amount'),
            variance = pui.reference('aa', 'fake lag', 'variance'),
            limit = pui.reference('aa', 'fake lag', 'limit')
        },
        other = {
            on_shot_anti_aim = {pui.reference('aa', 'other', 'on shot anti-aim')},
            slow_motion = {pui.reference('aa', 'other', 'slow motion')},
            leg_movement = pui.reference('aa', 'other', 'leg movement')
        }
    },
    visuals = {
        scope = pui.reference('visuals', 'effects', 'remove scope overlay')
    },
    misc = {
        settings = {
            menu_color = pui.reference('misc', 'settings', 'menu color')
        }
    }
}

-- Hide all antiaim functions like embertrash
do
    defer(function()
        pui.traverse(reference, function(ref)
            ref:override()
            ref:set_enabled(true)
            if ref.hotkey then ref.hotkey:set_enabled(true) end
        end)
    end)
    
    -- Hide antiaim elements with impossible conditions (1488 value)
    reference.antiaim.angles.yaw[2]:depend({reference.antiaim.angles.yaw[1], 1488}, {reference.antiaim.angles.yaw[2], 1488})
    reference.antiaim.angles.pitch[2]:depend({reference.antiaim.angles.pitch[1], 1488}, {reference.antiaim.angles.pitch[2], 1488})
    reference.antiaim.angles.yaw_jitter[1]:depend({reference.antiaim.angles.yaw[1], 1488}, {reference.antiaim.angles.yaw[2], 1488})
    reference.antiaim.angles.yaw_jitter[2]:depend({reference.antiaim.angles.yaw[1], 1488}, {reference.antiaim.angles.yaw[2], 1488}, {reference.antiaim.angles.yaw_jitter[1], 1488}, {reference.antiaim.angles.yaw_jitter[2], 1488})
    reference.antiaim.angles.body_yaw[2]:depend({reference.antiaim.angles.body_yaw[1], 1488})
    reference.antiaim.angles.fs_body_yaw:depend({reference.antiaim.angles.body_yaw[1], 1488})
    pui.traverse(reference.antiaim.angles, function(ref)
        ref:depend({reference.antiaim.angles.enabled, 1488})
        if ref.hotkey then ref.hotkey:depend({reference.antiaim.angles.enabled, 1488}) end
    end)
    
    -- Hide all fakelag elements
    reference.antiaim.fakelag.enabled:depend({reference.antiaim.fakelag.enabled, 1488})
    if reference.antiaim.fakelag.enabled.hotkey then
        reference.antiaim.fakelag.enabled.hotkey:depend({reference.antiaim.fakelag.enabled, 1488})
    end
    reference.antiaim.fakelag.amount:depend({reference.antiaim.fakelag.enabled, 1488})
    reference.antiaim.fakelag.variance:depend({reference.antiaim.fakelag.enabled, 1488})
    reference.antiaim.fakelag.limit:depend({reference.antiaim.fakelag.enabled, 1488})
end

-- Simple JSON
local json = {
    stringify = function(t)
        local result = "{"
        local first = true
        for k, v in pairs(t) do
            if not first then result = result .. "," end
            first = false
            result = result .. '"' .. tostring(k) .. '":'
            if type(v) == "table" then
                result = result .. json.stringify(v)
            elseif type(v) == "string" then
                result = result .. '"' .. v .. '"'
            else
                result = result .. tostring(v)
            end
        end
        return result .. "}"
    end,
    parse = function(str)
        return loadstring("return " .. str)()
    end
}

-- ═══════════════════════════════════════════════════════════
-- IS_ON_GROUND TRACKING (from embertrash)
-- ═══════════════════════════════════════════════════════════

do
    local pre, post = 0, 0
    local function on_setup_command()
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then 
            return 
        end
        pre = entity.get_prop(me, 'm_fFlags')
    end

    local function on_run_command()
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then 
            return 
        end
        post = entity.get_prop(me, 'm_fFlags')
        is_on_ground = bit.band(pre, 1) == 1 and bit.band(post, 1) == 1
    end

    client.set_event_callback('setup_command', on_setup_command)
    client.set_event_callback('run_command', on_run_command)
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION SYSTEM
-- ═══════════════════════════════════════════════════════════

local animations = {}

local function lerp(name, target_value, speed, tolerance, easing_style)
    if animations[name] == nil then
        animations[name] = target_value
    end

    speed = speed or 8
    tolerance = tolerance or 0.005
    easing_style = easing_style or 'linear'
    
    local current_value = animations[name]
    local delta = globals.absoluteframetime() * speed
    local new_value
    
    if easing_style == 'linear' then
        new_value = current_value + (target_value - current_value) * delta
    elseif easing_style == 'smooth' then
        new_value = current_value + (target_value - current_value) * (delta * delta * (3 - 2 * delta))
    elseif easing_style == 'ease_in' then
        new_value = current_value + (target_value - current_value) * (delta * delta)
    elseif easing_style == 'ease_out' then
        local progress = 1 - (1 - delta) * (1 - delta)
        new_value = current_value + (target_value - current_value) * progress
    elseif easing_style == 'ease_in_out' then
        local progress = delta < 0.5 and 2 * delta * delta or 1 - math.pow(-2 * delta + 2, 2) / 2
        new_value = current_value + (target_value - current_value) * progress
    else
        new_value = current_value + (target_value - current_value) * delta
    end

    if math.abs(target_value - new_value) <= tolerance then
        animations[name] = target_value
    else
        animations[name] = new_value
    end
    
    return animations[name]
end

local function animate(name, target, speed, tolerance, easing_style)
    speed = speed or 8
    tolerance = tolerance or 0.005
    easing_style = easing_style or 'linear'
    
    if animations[name] == nil then
        animations[name] = target
    end
    
    local current_value = animations[name]
    local delta = globals.absoluteframetime() * speed
    local new_value
    
    if easing_style == 'linear' then
        new_value = current_value + (target - current_value) * delta
    elseif easing_style == 'smooth' then
        new_value = current_value + (target - current_value) * (delta * delta * (3 - 2 * delta))
    elseif easing_style == 'ease_in' then
        new_value = current_value + (target - current_value) * (delta * delta)
    elseif easing_style == 'ease_out' then
        local progress = 1 - (1 - delta) * (1 - delta)
        new_value = current_value + (target - current_value) * progress
    elseif easing_style == 'ease_in_out' then
        local progress = delta < 0.5 and 2 * delta * delta or 1 - math.pow(-2 * delta + 2, 2) / 2
        new_value = current_value + (target - current_value) * progress
    else
        new_value = current_value + (target - current_value) * delta
    end
    
    if math.abs(target - new_value) <= tolerance then
        animations[name] = target
    else
        animations[name] = new_value
    end
    
    return animations[name]
end

-- ═══════════════════════════════════════════════════════════
-- CVARS (direct access)
-- ═══════════════════════════════════════════════════════════

-- No wrappers needed, use cvar directly

-- ═══════════════════════════════════════════════════════════
-- UI SYSTEM (PUI)
-- ═══════════════════════════════════════════════════════════

-- Save reference to global ui API before we override it
local ui_api = {
    mouse_position = ui.mouse_position,
    is_menu_open = ui.is_menu_open,
    new_hotkey = ui.new_hotkey,
    get = ui.get,
    set = ui.set
}

local menu = {
    group = {
        aa = pui.group('AA', 'Anti-aimbot angles'),
        fakelag = pui.group('AA', 'Fake lag')
    }
}

-- Main tab
local ui = {
    tab = menu.group.fakelag:combobox('ASTRUM Tab', {'Ragebot', 'Anti-Aim', 'Visuals', 'Misc', 'Config'}),
    
    -- Tab headers
    ragebot_label = menu.group.aa:label('\a8BAAFFFF\u{E148}\aD0D0D0FF - Ragebot'),
    ragebot_separator = menu.group.aa:label('─────────────────────────────────'),
    
    antiaim_label = menu.group.aa:label('\a8BAAFFFF\u{E1CF}\aD0D0D0FF - Anti-Aim'),
    antiaim_separator = menu.group.aa:label('─────────────────────────────────'),
    
    visuals_label = menu.group.aa:label('\a8BAAFFFF\u{E104}\aD0D0D0FF - Visuals'),
    visuals_separator = menu.group.aa:label('─────────────────────────────────'),
    
    misc_label = menu.group.aa:label('\a8BAAFFFF\u{E115}\aD0D0D0FF - Misc'),
    misc_separator = menu.group.aa:label('─────────────────────────────────'),
    
    config_label = menu.group.aa:label('\a8BAAFFFF\u{E105}\aD0D0D0FF - Config'),
    config_separator = menu.group.aa:label('─────────────────────────────────'),
    
    -- Ragebot
    unsafe_exploit = menu.group.aa:checkbox('Unsafe exploit recharge'),
    
    aim_punch_fix = menu.group.aa:checkbox('Aim punch miss fix'),
    
    predict_enemies = menu.group.aa:checkbox('Predict enemies'),
    
    -- Defensive Fix
    defensive_fix = {
        enable = menu.group.aa:checkbox('Fix defensive in peek')
    },
    
    -- Anti-Aim Builder
    other_tab = menu.group.aa:combobox('Anti-Aim Tab', {'Builder', 'Defensive', 'Hotkeys', 'Other'}),
    
    builder_state = menu.group.aa:combobox('Anti-Aim State', {'Global', 'Stand', 'Run', 'Walk', 'Crouch', 'Sneak', 'Air', 'Air+'}),
    
    builder = {},
    
    -- Defensive state selector (separate from builder state)
    defensive_state = menu.group.aa:combobox('Defensive State', {'Global', 'Stand', 'Run', 'Walk', 'Crouch', 'Sneak', 'Air', 'Air+'}),
    
    defensive = {},
    
    -- Manual Yaw
    manual_yaw = {
        enable = menu.group.aa:checkbox('Manual Yaw'),
        left = menu.group.aa:hotkey('Left'),
        right = menu.group.aa:hotkey('Right'),
        forward = menu.group.aa:hotkey('Forward'),
        reset = menu.group.aa:hotkey('Reset')
    },
    
    -- Freestanding
    freestanding = {
        enable = menu.group.aa:hotkey('Freestanding')
    },
    
    -- Other tab
    avoid_backstab = {
        enable = menu.group.aa:checkbox('Avoid Backstab'),
        distance = menu.group.aa:slider('\nBackstab Distance', 150, 320, 240, true, 'u')
    },
    safe_head = {
        enable = menu.group.aa:checkbox('Safe Head'),
        conditions = menu.group.aa:multiselect('\nSafe Head Conditions', {'Standing', 'Moving', 'Crouch', 'Air'})
    },
    static_aa = menu.group.aa:multiselect('Static Anti-Aim', {'On Manual', 'On Freestanding'}),
}

-- Create builder UI elements for each state
local builder_states = {'Global', 'Stand', 'Run', 'Walk', 'Crouch', 'Sneak', 'Air', 'Air+'}
for i, state in ipairs(builder_states) do
    ui.builder[state] = {
        enable = menu.group.aa:checkbox('Enable ' .. state),
        yaw = menu.group.aa:slider('Yaw Offset ' .. state, -180, 180, 0, true, '°'),
        yaw_jitter = menu.group.aa:combobox('Yaw Jitter ' .. state, {'Off', 'Offset', 'Center', 'Random'}),
        yaw_jitter_value = menu.group.aa:slider('Jitter Value ' .. state, -180, 180, 0, true, '°'),
        
        -- Delay system for jitter
        jitter_delay_enable = menu.group.aa:checkbox('Jitter Delay ' .. state),
        jitter_delay = menu.group.aa:slider('Delay ' .. state, 1, 17, 1, true, 't', 1, {[1] = 'OFF'}),
        jitter_delay_randomize = menu.group.aa:checkbox('Randomize Delay ' .. state),
        jitter_small_delay_min_toggle = menu.group.aa:checkbox('Small Min Delay ' .. state),
        jitter_small_delay_min = menu.group.aa:slider('Small Min Value ' .. state, 1, 12, 1, true, 't', 0.2),
        jitter_delay_min = menu.group.aa:slider('Min Delay ' .. state, 1, 17, 1, true, 't', 1, {[1] = 'OFF'}),
        jitter_small_delay_max_toggle = menu.group.aa:checkbox('Small Max Delay ' .. state),
        jitter_small_delay_max = menu.group.aa:slider('Small Max Value ' .. state, 1, 12, 1, true, 't', 0.2),
        jitter_delay_max = menu.group.aa:slider('Max Delay ' .. state, 1, 17, 17, true, 't', 1, {[1] = 'OFF'}),
        
        body_yaw = menu.group.aa:combobox('Body Yaw ' .. state, {'Off', 'Opposite', 'Jitter', 'Static'}, 2),
        body_yaw_value = menu.group.aa:slider('Body Yaw Value ' .. state, -180, 180, 60, true, '°'),
    }
end

-- Initialize defensive table
ui.defensive = {}

-- Create defensive UI elements for each state
for i, state in ipairs(builder_states) do
    ui.defensive[state] = {
        enable = menu.group.aa:checkbox('Enable Defensive ' .. state),
        defensive_on = menu.group.aa:multiselect('Defensive On ' .. state, {'Double tap', 'Hide shots'}),
        defensive_mode = menu.group.aa:combobox('Defensive Mode ' .. state, {'Always on', 'On peek'}),
        
        -- Pitch mode
        pitch_mode = menu.group.aa:combobox('Pitch Mode ' .. state, {'Static', 'Jitter', 'Random'}),
        pitch = menu.group.aa:slider('Pitch ' .. state, -89, 89, 89, true, '°'),
        
        -- Jitter pitch settings
        pitch_first = menu.group.aa:slider('First Pitch ' .. state, -89, 89, 89, true, '°'),
        pitch_second = menu.group.aa:slider('Second Pitch ' .. state, -89, 89, -89, true, '°'),
        pitch_delay = menu.group.aa:slider('Pitch Delay ' .. state, 1, 64, 2, true, 't'),
        
        -- Random pitch settings
        pitch_min = menu.group.aa:slider('Min Pitch ' .. state, -89, 89, -89, true, '°'),
        pitch_max = menu.group.aa:slider('Max Pitch ' .. state, -89, 89, 89, true, '°'),
        pitch_random_delay = menu.group.aa:slider('Random Pitch Delay ' .. state, 1, 64, 2, true, 't'),
        
        -- Yaw mode
        yaw_mode = menu.group.aa:combobox('Yaw Mode ' .. state, {'Static', 'Jitter', 'Random'}),
        yaw_offset = menu.group.aa:slider('Yaw Offset ' .. state, -180, 180, 0, true, '°'),
        
        -- Jitter yaw settings
        yaw_first = menu.group.aa:slider('First Yaw ' .. state, -180, 180, 30, true, '°'),
        yaw_second = menu.group.aa:slider('Second Yaw ' .. state, -180, 180, -30, true, '°'),
        yaw_delay = menu.group.aa:slider('Yaw Delay ' .. state, 1, 64, 2, true, 't'),
        
        -- Random yaw settings
        yaw_min = menu.group.aa:slider('Min Yaw ' .. state, -180, 180, -180, true, '°'),
        yaw_max = menu.group.aa:slider('Max Yaw ' .. state, -180, 180, 180, true, '°'),
        yaw_random_delay = menu.group.aa:slider('Random Yaw Delay ' .. state, 1, 64, 2, true, 't'),
    }
end

-- Visuals
ui.enable_ui = menu.group.aa:checkbox('Enable UI')
ui.ui_elements = menu.group.aa:multiselect('\nUI Elements', {'Watermark', 'Keybinds'})
ui.icon_color_label = menu.group.aa:label('Icon Color:')
ui.icon_color = menu.group.aa:color_picker('Icon Color', 139, 186, 255, 255)
ui.background_color_label = menu.group.aa:label('Background Color:')
ui.background_color = menu.group.aa:color_picker('Background Color', 28, 28, 28, 165)
ui.text_color_label = menu.group.aa:label('Text Color:')
ui.text_color = menu.group.aa:color_picker('Text Color', 255, 255, 255, 255)

-- Legacy references for compatibility
ui.watermark = ui.enable_ui
ui.keybinds = ui.enable_ui

-- Keybinds position sliders (hidden)
ui.keybinds_x = menu.group.aa:slider('\nKeybinds X', 0, 3840, 0, true, 'px')
ui.keybinds_y = menu.group.aa:slider('\nKeybinds Y', 0, 2160, 200, true, 'px')

-- Hide keybinds position sliders completely
ui.keybinds_x:depend({ui.enable_ui, false}, {ui.enable_ui, true})
ui.keybinds_y:depend({ui.enable_ui, false}, {ui.enable_ui, true})

-- Crosshair Indicator
ui.crosshair = {
    enable = menu.group.aa:checkbox('Crosshair Indicator'),
    type = menu.group.aa:combobox('\nCrosshair Type', {'Unique', 'Simple'}),
    select = menu.group.aa:multiselect('\nCrosshair Select', {'States', 'Binds'}),
    y = menu.group.aa:slider('\nCrosshair Y', -2160, 2160, 0, true, 'px')
}

ui.crosshair.type:depend({ui.crosshair.enable, true})
ui.crosshair.select:depend({ui.crosshair.enable, true})
ui.crosshair.y:depend({ui.crosshair.enable, false}, {ui.crosshair.enable, true})

-- Hide keybinds position sliders completely
ui.keybinds_x:depend({ui.keybinds, false}, {ui.keybinds, true})
ui.keybinds_y:depend({ui.keybinds, false}, {ui.keybinds, true})

ui.aspect_ratio = {
    enable = menu.group.aa:checkbox('Aspect Ratio'),
    value = menu.group.aa:slider('\nAspect Ratio Value', 80, 250, 133, true, '%', 0.01, {[125] = '5:4', [133] = '4:3', [150] = '3:2', [160] = '16:10', [178] = '16:9', [200] = '2:1'})
}

ui.custom_scope = {
    enable = menu.group.aa:checkbox('Custom Scope'),
    gap = menu.group.aa:slider('\nScope Gap', 0, 100, 10, true, 'px'),
    size = menu.group.aa:slider('\nScope Size', 0, 500, 100, true, 'px'),
    invert = menu.group.aa:checkbox('\nScope Invert'),
    speed = menu.group.aa:slider('\nScope Speed', 1, 20, 4, true, 'x'),
    color = menu.group.aa:color_picker('\nScope Color', 120, 160, 255, 255)
}

ui.sunset_mode = {
    enable = menu.group.aa:checkbox('Sunset Mode'),
    x = menu.group.aa:slider('\nSunset X', -180, 180, 0, true, '°'),
    y = menu.group.aa:slider('\nSunset Y', -180, 180, 0, true, '°')
}

ui.nade_esp = {
    enable = menu.group.aa:checkbox('Nade ESP'),
    size = menu.group.aa:slider('\nNade Icon Size', 4, 12, 6, true, 'px'),
    he_label = menu.group.aa:label('HE Grenade:'),
    he_color = menu.group.aa:color_picker('\nHE Color', 0, 0, 0, 255),
    smoke_label = menu.group.aa:label('Smoke Grenade:'),
    smoke_color = menu.group.aa:color_picker('\nSmoke Color', 0, 0, 0, 255),
    molotov_label = menu.group.aa:label('Molotov:'),
    molotov_color = menu.group.aa:color_picker('\nMolotov Color', 0, 0, 0, 255)
}

ui.viewmodel = {
    enable = menu.group.aa:checkbox('Viewmodel'),
    fov = menu.group.aa:slider('\nFOV', -1800, 1800, 680, true, '°', 0.1),
    x = menu.group.aa:slider('\nX', -100, 100, 25, true, 'u', 0.1),
    y = menu.group.aa:slider('\nY', -100, 100, 0, true, 'u', 0.1),
    z = menu.group.aa:slider('\nZ', -100, 100, -15, true, 'u', 0.1)
}

-- Misc
ui.nickname_changer = {
    enable = menu.group.aa:checkbox('Nickname Changer'),
    text = menu.group.aa:textbox('\nNickname')
}

-- Set manual yaw hotkey modes (pui hotkeys don't need mode setting, they work automatically)
-- The mode is set when user clicks on the hotkey in menu


-- ═══════════════════════════════════════════════════════════
-- CONFIG SYSTEM (PUI)
-- ═══════════════════════════════════════════════════════════

local config_db = database.read('astrum_configs') or {}
config_db.presets = config_db.presets or {}
config_db.data = config_db.data or {}
database.write('astrum_configs', config_db)
database.flush()

local config_setup = pui.setup(ui, true)

ui.config_name = menu.group.aa:textbox('Config Name')

ui.config_create = menu.group.aa:button('Create Config', function()
    local name = ui.config_name:get()
    if name == "" or name == "No configs" then
        client.log("[ASTRUM] Enter valid config name")
        return
    end
    
    for _, cfg in ipairs(config_db.presets) do
        if cfg == name then
            client.log("[ASTRUM] Config already exists")
            return
        end
    end
    
    table.insert(config_db.presets, name)
    config_db.data[name] = config_setup:save()
    database.write('astrum_configs', config_db)
    database.flush()
    ui.config_list:update(config_db.presets)
    ui.config_name:set("")
    client.log("[ASTRUM] Config '" .. name .. "' created")
end)

ui.config_list = menu.group.aa:listbox('Configs', #config_db.presets > 0 and config_db.presets or {'No configs'})

ui.config_save = menu.group.aa:button('Save Config', function()
    local selected = ui.config_list:get()
    if not config_db.presets[selected + 1] then
        client.log("[ASTRUM] Select a config")
        return
    end
    
    local name = config_db.presets[selected + 1]
    config_db.data[name] = config_setup:save()
    database.write('astrum_configs', config_db)
    database.flush()
    client.log("[ASTRUM] Config '" .. name .. "' saved")
end)

ui.config_load = menu.group.aa:button('Load Config', function()
    local selected = ui.config_list:get()
    if not config_db.presets[selected + 1] then
        client.log("[ASTRUM] Select a config")
        return
    end
    
    local name = config_db.presets[selected + 1]
    if config_db.data[name] then
        config_setup:load(config_db.data[name])
        client.log("[ASTRUM] Config '" .. name .. "' loaded")
    else
        client.log("[ASTRUM] Config data not found")
    end
end)

ui.config_delete = menu.group.aa:button('Delete Config', function()
    local selected = ui.config_list:get()
    if not config_db.presets[selected + 1] then
        client.log("[ASTRUM] Select a config")
        return
    end
    
    local name = config_db.presets[selected + 1]
    table.remove(config_db.presets, selected + 1)
    config_db.data[name] = nil
    database.write('astrum_configs', config_db)
    database.flush()
    ui.config_list:update(#config_db.presets > 0 and config_db.presets or {'No configs'})
    client.log("[ASTRUM] Config '" .. name .. "' deleted")
end)

ui.config_export = menu.group.aa:button('Export to Clipboard', function()
    local data = config_setup:save()
    clipboard.set(base64.encode(json.stringify(data)))
    client.log("[ASTRUM] Config exported to clipboard")
end)

ui.config_import = menu.group.aa:button('Import from Clipboard', function()
    local encoded = clipboard.get()
    if not encoded or encoded == "" then
        client.log("[ASTRUM] Clipboard is empty")
        return
    end
    
    local success, decoded = pcall(function() return json.parse(base64.decode(encoded)) end)
    if not success then
        client.log("[ASTRUM] Invalid config")
        return
    end
    
    config_setup:load(decoded)
    client.log("[ASTRUM] Config imported")
end)

-- Visibility dependencies
do
    local is_ragebot = {ui.tab, 'Ragebot'}
    local is_antiaim = {ui.tab, 'Anti-Aim'}
    local is_visuals = {ui.tab, 'Visuals'}
    local is_misc = {ui.tab, 'Misc'}
    local is_config = {ui.tab, 'Config'}
    
    -- Ragebot tab
    ui.ragebot_label:depend(is_ragebot)
    ui.ragebot_separator:depend(is_ragebot)
    ui.unsafe_exploit:depend(is_ragebot)
    ui.aim_punch_fix:depend(is_ragebot)
    ui.predict_enemies:depend(is_ragebot)
    
    -- Defensive Fix dependencies
    ui.defensive_fix.enable:depend(is_ragebot)
    
    -- Anti-Aim tab
    ui.antiaim_label:depend(is_antiaim)
    ui.antiaim_separator:depend(is_antiaim)
    ui.other_tab:depend(is_antiaim)
    
    local is_builder = {ui.other_tab, 'Builder'}
    local is_defensive = {ui.other_tab, 'Defensive'}
    local is_hotkeys = {ui.other_tab, 'Hotkeys'}
    local is_other = {ui.other_tab, 'Other'}
    
    ui.builder_state:depend(is_antiaim, is_builder)
    
    -- Hotkeys tab dependencies
    ui.manual_yaw.enable:depend(is_antiaim, is_hotkeys)
    ui.manual_yaw.left:depend(is_antiaim, is_hotkeys, {ui.manual_yaw.enable, true})
    ui.manual_yaw.right:depend(is_antiaim, is_hotkeys, {ui.manual_yaw.enable, true})
    ui.manual_yaw.forward:depend(is_antiaim, is_hotkeys, {ui.manual_yaw.enable, true})
    ui.manual_yaw.reset:depend(is_antiaim, is_hotkeys, {ui.manual_yaw.enable, true})
    
    ui.freestanding.enable:depend(is_antiaim, is_hotkeys)
    
    -- Other tab dependencies
    ui.avoid_backstab.enable:depend(is_antiaim, is_other)
    ui.avoid_backstab.distance:depend(is_antiaim, is_other, {ui.avoid_backstab.enable, true})
    ui.safe_head.enable:depend(is_antiaim, is_other)
    ui.safe_head.conditions:depend(is_antiaim, is_other, {ui.safe_head.enable, true})
    ui.static_aa:depend(is_antiaim, is_other)
    
    -- Builder dependencies for each state
    for i, state in ipairs(builder_states) do
        local is_state = {ui.builder_state, state}
        local is_enabled = {ui.builder[state].enable, true}
        local body_yaw_jitter = {ui.builder[state].body_yaw, 'Jitter'}
        local jitter_delay_enabled = {ui.builder[state].jitter_delay_enable, true}
        local jitter_delay_randomize_enabled = {ui.builder[state].jitter_delay_randomize, true}
        local jitter_small_min_enabled = {ui.builder[state].jitter_small_delay_min_toggle, true}
        local jitter_small_max_enabled = {ui.builder[state].jitter_small_delay_max_toggle, true}
        
        -- Чекбокс виден только когда стейт выбран
        ui.builder[state].enable:depend(is_antiaim, is_builder, is_state)
        
        -- Настройки видны только когда стейт выбран И чекбокс включен
        ui.builder[state].yaw:depend(is_antiaim, is_builder, is_state, is_enabled)
        ui.builder[state].yaw_jitter:depend(is_antiaim, is_builder, is_state, is_enabled)
        ui.builder[state].yaw_jitter_value:depend(is_antiaim, is_builder, is_state, is_enabled)
        
        -- Body yaw - всегда видна
        ui.builder[state].body_yaw:depend(is_antiaim, is_builder, is_state, is_enabled)
        ui.builder[state].body_yaw_value:depend(is_antiaim, is_builder, is_state, is_enabled)
        
        -- Jitter delay checkbox - видна только когда body yaw = Jitter
        ui.builder[state].jitter_delay_enable:depend(is_antiaim, is_builder, is_state, is_enabled, body_yaw_jitter)
        
        -- Jitter delay settings - видны только когда delay checkbox включен
        ui.builder[state].jitter_delay:depend(is_antiaim, is_builder, is_state, is_enabled, body_yaw_jitter, jitter_delay_enabled, {ui.builder[state].jitter_delay_randomize, false})
        ui.builder[state].jitter_delay_randomize:depend(is_antiaim, is_builder, is_state, is_enabled, body_yaw_jitter, jitter_delay_enabled)
        
        -- Randomize jitter delay settings
        ui.builder[state].jitter_small_delay_min_toggle:depend(is_antiaim, is_builder, is_state, is_enabled, body_yaw_jitter, jitter_delay_enabled, jitter_delay_randomize_enabled)
        ui.builder[state].jitter_small_delay_min:depend(is_antiaim, is_builder, is_state, is_enabled, body_yaw_jitter, jitter_delay_enabled, jitter_delay_randomize_enabled, jitter_small_min_enabled)
        ui.builder[state].jitter_delay_min:depend(is_antiaim, is_builder, is_state, is_enabled, body_yaw_jitter, jitter_delay_enabled, jitter_delay_randomize_enabled, jitter_small_min_enabled)
        ui.builder[state].jitter_small_delay_max_toggle:depend(is_antiaim, is_builder, is_state, is_enabled, body_yaw_jitter, jitter_delay_enabled, jitter_delay_randomize_enabled)
        ui.builder[state].jitter_small_delay_max:depend(is_antiaim, is_builder, is_state, is_enabled, body_yaw_jitter, jitter_delay_enabled, jitter_delay_randomize_enabled, jitter_small_max_enabled)
        ui.builder[state].jitter_delay_max:depend(is_antiaim, is_builder, is_state, is_enabled, body_yaw_jitter, jitter_delay_enabled, jitter_delay_randomize_enabled, jitter_small_max_enabled)
    end
    
    -- Defensive dependencies for each state
    ui.defensive_state:depend(is_antiaim, is_defensive)
    
    for i, state in ipairs(builder_states) do
        local is_def_state = {ui.defensive_state, state}
        local is_def_enabled = {ui.defensive[state].enable, true}
        local is_pitch_jitter = {ui.defensive[state].pitch_mode, 'Jitter'}
        local is_pitch_static = {ui.defensive[state].pitch_mode, 'Static'}
        local is_pitch_random = {ui.defensive[state].pitch_mode, 'Random'}
        local is_yaw_jitter = {ui.defensive[state].yaw_mode, 'Jitter'}
        local is_yaw_static = {ui.defensive[state].yaw_mode, 'Static'}
        local is_yaw_random = {ui.defensive[state].yaw_mode, 'Random'}
        
        -- Enable checkbox
        ui.defensive[state].enable:depend(is_antiaim, is_defensive, is_def_state)
        
        -- Main settings
        ui.defensive[state].defensive_on:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled)
        ui.defensive[state].defensive_mode:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled)
        
        -- Pitch settings
        ui.defensive[state].pitch_mode:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled)
        ui.defensive[state].pitch:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_pitch_static)
        
        -- Jitter pitch settings
        ui.defensive[state].pitch_first:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_pitch_jitter)
        ui.defensive[state].pitch_second:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_pitch_jitter)
        ui.defensive[state].pitch_delay:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_pitch_jitter)
        
        -- Random pitch settings
        ui.defensive[state].pitch_min:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_pitch_random)
        ui.defensive[state].pitch_max:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_pitch_random)
        ui.defensive[state].pitch_random_delay:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_pitch_random)
        
        -- Yaw settings
        ui.defensive[state].yaw_mode:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled)
        ui.defensive[state].yaw_offset:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_yaw_static)
        
        -- Jitter yaw settings
        ui.defensive[state].yaw_first:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_yaw_jitter)
        ui.defensive[state].yaw_second:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_yaw_jitter)
        ui.defensive[state].yaw_delay:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_yaw_jitter)
        
        -- Random yaw settings
        ui.defensive[state].yaw_min:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_yaw_random)
        ui.defensive[state].yaw_max:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_yaw_random)
        ui.defensive[state].yaw_random_delay:depend(is_antiaim, is_defensive, is_def_state, is_def_enabled, is_yaw_random)
    end
    
    -- Visuals tab
    ui.visuals_label:depend(is_visuals)
    ui.visuals_separator:depend(is_visuals)
    ui.enable_ui:depend(is_visuals)
    ui.ui_elements:depend(is_visuals, {ui.enable_ui, true})
    ui.icon_color_label:depend(is_visuals, {ui.enable_ui, true})
    ui.icon_color:depend(is_visuals, {ui.enable_ui, true})
    ui.background_color_label:depend(is_visuals, {ui.enable_ui, true})
    ui.background_color:depend(is_visuals, {ui.enable_ui, true})
    ui.text_color_label:depend(is_visuals, {ui.enable_ui, true})
    ui.text_color:depend(is_visuals, {ui.enable_ui, true})
    
    ui.crosshair.enable:depend(is_visuals)
    ui.crosshair.type:depend(is_visuals, {ui.crosshair.enable, true})
    ui.crosshair.select:depend(is_visuals, {ui.crosshair.enable, true})
    ui.crosshair.y:depend(is_visuals, {ui.crosshair.enable, true})
    
    ui.aspect_ratio.enable:depend(is_visuals)
    ui.aspect_ratio.value:depend(is_visuals, {ui.aspect_ratio.enable, true})
    
    ui.viewmodel.enable:depend(is_visuals)
    pui.traverse(ui.viewmodel, function(ref)
        if ref ~= ui.viewmodel.enable then
            ref:depend(is_visuals, {ui.viewmodel.enable, true})
        end
    end)
    
    ui.custom_scope.enable:depend(is_visuals)
    pui.traverse(ui.custom_scope, function(ref)
        if ref ~= ui.custom_scope.enable then
            ref:depend(is_visuals, {ui.custom_scope.enable, true})
        end
    end)
    
    ui.sunset_mode.enable:depend(is_visuals)
    ui.sunset_mode.x:depend(is_visuals, {ui.sunset_mode.enable, true})
    ui.sunset_mode.y:depend(is_visuals, {ui.sunset_mode.enable, true})
    
    ui.nade_esp.enable:depend(is_visuals)
    pui.traverse(ui.nade_esp, function(ref)
        if ref ~= ui.nade_esp.enable then
            ref:depend(is_visuals, {ui.nade_esp.enable, true})
        end
    end)
    
    -- Misc tab
    ui.misc_label:depend(is_misc)
    ui.misc_separator:depend(is_misc)
    ui.nickname_changer.enable:depend(is_misc)
    ui.nickname_changer.text:depend(is_misc, {ui.nickname_changer.enable, true})
    
    -- Config tab
    ui.config_label:depend(is_config)
    ui.config_separator:depend(is_config)
    ui.config_name:depend(is_config)
    ui.config_create:depend(is_config)
    ui.config_list:depend(is_config)
    ui.config_save:depend(is_config)
    ui.config_load:depend(is_config)
    ui.config_delete:depend(is_config)
    ui.config_export:depend(is_config)
    ui.config_import:depend(is_config)
end

-- ═══════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════

local function draw_rounded_rect(x, y, w, h, rounding, r, g, b, a)
    if not x or not y or not w or not h then
        return
    end
    
    rounding = rounding or 10
    y = y + rounding
    
    local data_circle = {
        {x + rounding, y, 180},
        {x + w - rounding, y, 90},
        {x + rounding, y + h - rounding * 2, 270},
        {x + w - rounding, y + h - rounding * 2, 0}
    }
    
    local data = {
        {x + rounding, y, w - rounding * 2, h - rounding * 2},
        {x + rounding, y - rounding, w - rounding * 2, rounding},
        {x + rounding, y + h - rounding * 2, w - rounding * 2, rounding},
        {x, y, rounding, h - rounding * 2},
        {x + w - rounding, y, rounding, h - rounding * 2}
    }
    
    for _, circle in pairs(data_circle) do
        renderer.circle(circle[1], circle[2], r, g, b, a, rounding, circle[3], 0.25)
    end
    
    for _, rect in pairs(data) do
        renderer.rectangle(rect[1], rect[2], rect[3], rect[4], r, g, b, a)
    end
end

-- ═══════════════════════════════════════════════════════════
-- WATERMARK
-- ═══════════════════════════════════════════════════════════

local watermark = {
    x = 0,
    y = 10,
    fps = 0,
    last_fps_update = 0
}

local function draw_watermark()
    if not ui.enable_ui:get() then return end
    
    local ui_elements = ui.ui_elements:get()
    local show_watermark = false
    for i = 1, #ui_elements do
        if ui_elements[i] == 'Watermark' then
            show_watermark = true
            break
        end
    end
    
    if not show_watermark then return end
    
    local sx, sy = client.screen_size()
    local icon_r, icon_g, icon_b = ui.icon_color:get()
    local bg_r, bg_g, bg_b, bg_a = ui.background_color:get()
    local text_r, text_g, text_b, text_a = ui.text_color:get()
    
    local current_time = globals.realtime()
    if current_time - watermark.last_fps_update > 0.5 then
        watermark.fps = math.floor(1 / globals.absoluteframetime())
        watermark.last_fps_update = current_time
    end
    
    -- Watermark style matching keybinds
    local item_height = 30
    local rounding = 15  -- Fully rounded (half of height)
    local text_padding = 12
    local box_gap = 8
    
    -- Left box: ASTRUM
    local info_text = 'ASTRUM'
    local left_w = renderer.measure_text('b', info_text)
    
    -- Add icon width if loaded
    if _G.astrum_watermark_icon then
        left_w = left_w + 18 + 2  -- icon size + spacing
    end
    
    local left_box_w = left_w + text_padding * 2
    
    -- Right box: FPS | Ping | Time (all in one box)
    local fps_text = string.format('%d fps', watermark.fps)
    local ping = math.floor(client.latency() * 1000)
    local ping_text = string.format('%d ms', ping)
    local hour, minute = client.system_time()
    local time_text = string.format('%02d:%02d', hour, minute)
    
    local separator = ' | '
    local right_text = fps_text .. separator .. ping_text .. separator .. time_text
    local right_w = renderer.measure_text('b', right_text)
    local right_box_w = right_w + text_padding * 2
    
    -- Calculate total width and position
    local total_w = left_box_w + box_gap + right_box_w
    watermark.x = sx - total_w - 10
    
    local x, y = watermark.x, watermark.y
    
    -- Draw left box (ASTRUM)
    draw_rounded_rect(x, y, left_box_w, item_height, rounding, 255, 255, 255, 38)
    draw_rounded_rect(x + 1, y + 1, left_box_w - 2, item_height - 2, rounding - 1, bg_r, bg_g, bg_b, bg_a)
    
    local text_x = x + text_padding
    
    -- Draw icon if loaded
    if _G.astrum_watermark_icon then
        local icon_size = 18
        local icon_y = y + (item_height - icon_size) / 2
        renderer.texture(_G.astrum_watermark_icon, text_x, icon_y, icon_size, icon_size, icon_r, icon_g, icon_b, 255, 'f')
        text_x = text_x + icon_size + 2
    end
    
    renderer.text(text_x, y + 8, text_r, text_g, text_b, text_a, 'b', 0, info_text)
    
    -- Draw right box (FPS | Ping | Time)
    local right_x = x + left_box_w + box_gap
    draw_rounded_rect(right_x, y, right_box_w, item_height, rounding, 255, 255, 255, 38)
    draw_rounded_rect(right_x + 1, y + 1, right_box_w - 2, item_height - 2, rounding - 1, bg_r, bg_g, bg_b, bg_a)
    
    -- Draw text
    local draw_x = right_x + text_padding
    
    -- FPS text
    local fps_w = renderer.measure_text('b', fps_text)
    renderer.text(draw_x, y + 8, text_r, text_g, text_b, text_a, 'b', 0, fps_text)
    draw_x = draw_x + fps_w
    
    -- Separator
    local sep_w = renderer.measure_text('b', separator)
    local sep_r, sep_g, sep_b = text_r * 0.4, text_g * 0.4, text_b * 0.4
    renderer.text(draw_x, y + 8, sep_r, sep_g, sep_b, text_a, 'b', 0, separator)
    draw_x = draw_x + sep_w
    
    -- Ping text
    local ping_w = renderer.measure_text('b', ping_text)
    renderer.text(draw_x, y + 8, text_r, text_g, text_b, text_a, 'b', 0, ping_text)
    draw_x = draw_x + ping_w
    
    -- Separator
    renderer.text(draw_x, y + 8, sep_r, sep_g, sep_b, text_a, 'b', 0, separator)
    draw_x = draw_x + sep_w
    
    -- Time text
    renderer.text(draw_x, y + 8, text_r, text_g, text_b, text_a, 'b', 0, time_text)
end

-- ═══════════════════════════════════════════════════════════
-- KEYBINDS
-- ═══════════════════════════════════════════════════════════

-- Keybinds state
local keybinds = {
    enabled = false,
    alpha = 0,
    x = 0,
    y = 200,
    dragging = false,
    drag_offset_x = 0,
    drag_offset_y = 0,
    mouse_down_prev = false
}

local keybind_anims = {}


local function update_keybinds_drag()
    if not ui.enable_ui:get() then return end
    
    local ui_elements = ui.ui_elements:get()
    local show_keybinds = false
    for i = 1, #ui_elements do
        if ui_elements[i] == 'Keybinds' then
            show_keybinds = true
            break
        end
    end
    
    if not show_keybinds then return end
    
    local mx, my = ui_api.mouse_position()
    if not mx or not my then return end
    
    local mouse_down = client.key_state(0x01)
    
    local header_w = 100
    local header_h = 32
    
    local sx, sy = client.screen_size()
    
    -- Load position from sliders
    local x = ui.keybinds_x:get()
    local y = ui.keybinds_y:get()
    
    -- Initialize position if needed
    if x == 0 and y == 0 then
        x = sx - 200
        y = 200
        ui.keybinds_x:set(x)
        ui.keybinds_y:set(y)
    end
    
    -- Check if mouse is over header
    local is_hovered = mx >= x and mx <= x + header_w and my >= y and my <= y + header_h
    
    -- Start dragging on click
    if mouse_down and not keybinds.mouse_down_prev and is_hovered then
        keybinds.dragging = true
        keybinds.drag_offset_x = mx - x
        keybinds.drag_offset_y = my - y
    end
    
    -- Update position while dragging
    if keybinds.dragging and mouse_down then
        local new_x = mx - keybinds.drag_offset_x
        local new_y = my - keybinds.drag_offset_y
        
        -- Clamp to screen
        new_x = math.max(0, math.min(new_x, sx - header_w))
        new_y = math.max(0, math.min(new_y, sy - header_h))
        
        -- Save to sliders
        ui.keybinds_x:set(new_x)
        ui.keybinds_y:set(new_y)
    end
    
    -- Stop dragging on release
    if not mouse_down then
        keybinds.dragging = false
    end
    
    keybinds.mouse_down_prev = mouse_down
end

-- ═══════════════════════════════════════════════════════════
-- MANUAL YAW
-- ═══════════════════════════════════════════════════════════

local manual_yaw = {}
do
    local current_dir = nil
    local hotkey_data = {}
    
    local dir_rotations = {
        ['left'] = -90,
        ['right'] = 90,
        ['forward'] = 179
    }
    
    local function get_hotkey_state(old_state, state, mode)
        if mode == 1 or mode == 2 then
            return old_state ~= state
        end
        return false
    end
    
    local function update_hotkey_state(data, state, mode)
        local active = get_hotkey_state(data.state, state, mode)
        data.state = state
        return active
    end
    
    local function update_hotkey_data(id, dir)
        local state, mode = ui_api.get(id)
        
        if hotkey_data[id] == nil then
            hotkey_data[id] = {state = state}
        end
        
        local changed = update_hotkey_state(hotkey_data[id], state, mode)
        
        if not changed then
            return
        end
        
        if current_dir == dir then
            current_dir = nil
        else
            current_dir = dir
        end
    end
    
    function manual_yaw.update()
        -- Always update hotkey states (no enable check needed)
        if ui.manual_yaw and ui.manual_yaw.left and ui.manual_yaw.left.ref then
            update_hotkey_data(ui.manual_yaw.left.ref, 'left')
        end
        if ui.manual_yaw and ui.manual_yaw.right and ui.manual_yaw.right.ref then
            update_hotkey_data(ui.manual_yaw.right.ref, 'right')
        end
        if ui.manual_yaw and ui.manual_yaw.forward and ui.manual_yaw.forward.ref then
            update_hotkey_data(ui.manual_yaw.forward.ref, 'forward')
        end
        if ui.manual_yaw and ui.manual_yaw.reset and ui.manual_yaw.reset.ref then
            update_hotkey_data(ui.manual_yaw.reset.ref, nil)
        end
    end
    
    function manual_yaw.get()
        return current_dir
    end
    
    function manual_yaw.get_offset()
        -- Check if manual yaw is enabled
        if ui.manual_yaw and ui.manual_yaw.enable and not ui.manual_yaw.enable:get() then
            return nil
        end
        return dir_rotations[current_dir]
    end
end

-- ═══════════════════════════════════════════════════════════
-- KEYBINDS
-- ═══════════════════════════════════════════════════════════

local function get_active_keybinds()
    local binds = {}
    
    -- Double tap
    pcall(function()
        if reference.rage.aimbot.double_tap[1] and reference.rage.aimbot.double_tap[1].hotkey then
            if reference.rage.aimbot.double_tap[1].hotkey:get() then
                table.insert(binds, {name = "Double tap", mode = "on"})
            end
        end
    end)
    
    -- Hide shots
    pcall(function()
        if reference.antiaim.other.on_shot_anti_aim[1] and reference.antiaim.other.on_shot_anti_aim[1].hotkey then
            if reference.antiaim.other.on_shot_anti_aim[1].hotkey:get() and not exploits:is_doubletap() then
                table.insert(binds, {name = "Hide shots", mode = "on"})
            end
        end
    end)
    
    -- Ping spike
    pcall(function()
        if reference.rage.ps[1] and reference.rage.ps[1].hotkey then
            if reference.rage.ps[1].hotkey:get() then
                local value = reference.rage.ps[2] and reference.rage.ps[2]:get() or 100
                table.insert(binds, {name = "Ping spike", mode = value})
            end
        end
    end)
    
    -- Fake duck
    pcall(function()
        if reference.rage.other.fake_duck then
            if reference.rage.other.fake_duck:get() then
                table.insert(binds, {name = "Fake duck", mode = "on"})
            end
        end
    end)
    
    -- Quick peek
    pcall(function()
        if reference.rage.other.quickpeek[1] and reference.rage.other.quickpeek[1].hotkey then
            if reference.rage.other.quickpeek[1].hotkey:get() then
                table.insert(binds, {name = "Quick peek", mode = "on"})
            end
        end
    end)
    
    -- Freestanding (from our lua)
    if ui.freestanding.enable:get() then
        table.insert(binds, {name = "Freestanding", mode = "on"})
    end
    
    -- Manual yaw
    if ui.manual_yaw.enable:get() and manual_yaw.get() then
        table.insert(binds, {name = "Manual yaw", mode = manual_yaw.get()})
    end
    
    -- Slow walk
    pcall(function()
        if reference.antiaim.other.slow_motion[1] and reference.antiaim.other.slow_motion[1].hotkey then
            if reference.antiaim.other.slow_motion[1].hotkey:get() then
                table.insert(binds, {name = "Slow walk", mode = "on"})
            end
        end
    end)
    
    -- Force body
    pcall(function()
        if reference.rage.aimbot.force_body then
            if reference.rage.aimbot.force_body:get() then
                table.insert(binds, {name = "Body aim", mode = "on"})
            end
        end
    end)
    
    -- Force safe
    pcall(function()
        if reference.rage.aimbot.force_safe then
            if reference.rage.aimbot.force_safe:get() then
                table.insert(binds, {name = "Safe point", mode = "on"})
            end
        end
    end)
    
    -- Min damage override
    pcall(function()
        if reference.rage.aimbot.minimum_damage_override[1] and reference.rage.aimbot.minimum_damage_override[1].hotkey then
            if reference.rage.aimbot.minimum_damage_override[1].hotkey:get() then
                local dmg = reference.rage.aimbot.minimum_damage_override[2] and reference.rage.aimbot.minimum_damage_override[2]:get() or 0
                if type(dmg) == "number" and dmg > 0 then
                    table.insert(binds, {name = "Min. damage", mode = dmg})
                end
            end
        end
    end)
    
    return binds
end


local function get_bind_icon(name)
    if name == "Double tap" then return ""
    elseif name == "Hide shots" then return ""
    elseif name == "Ping spike" then return ""
    elseif name == "Fake duck" then return ""
    elseif name == "Quick peek" then return ""
    elseif name == "Freestanding" then return ""
    elseif name == "Slow walk" then return ""
    elseif name == "Body aim" then return ""
    elseif name == "Safe point" then return ""
    elseif name == "Min. damage" then return ""
    elseif name == "Manual yaw" then return ""
    else return ""
    end
end


local function draw_keybinds()
    if not ui.enable_ui:get() then return end
    
    local ui_elements = ui.ui_elements:get()
    local show_keybinds = false
    for i = 1, #ui_elements do
        if ui_elements[i] == 'Keybinds' then
            show_keybinds = true
            break
        end
    end
    
    if not show_keybinds then return end
    
    local binds = get_active_keybinds()
    local should_show = client.key_state(0x2D) or #binds > 0  -- INSERT key for menu
    
    keybinds.alpha = animate("keybinds_alpha", should_show and 255 or 0, 20)
    
    if keybinds.alpha < 1 then return end
    
    -- Update bind animations
    for _, bind in ipairs(binds) do
        local key = bind.name
        if not keybind_anims[key] then
            keybind_anims[key] = {alpha = 0, y_offset = 20, target_row = 0, cur_row = 0}
            animations["kb_bind_alpha_" .. key] = 0
            animations["kb_bind_y_" .. key] = 20
            animations["kb_bind_row_" .. key] = 0
        end
        keybind_anims[key].alpha = animate("kb_bind_alpha_" .. key, 1, 15)
        keybind_anims[key].y_offset = animate("kb_bind_y_" .. key, 0, 12)
        keybind_anims[key].mode = bind.mode
        keybind_anims[key].name = bind.name
        keybind_anims[key].active = true
    end
    
    -- Fade out inactive binds
    for key, anim in pairs(keybind_anims) do
        local found = false
        for _, bind in ipairs(binds) do
            if bind.name == key then
                found = true
                break
            end
        end
        if not found then
            keybind_anims[key].alpha = animate("kb_bind_alpha_" .. key, 0, 15)
            keybind_anims[key].y_offset = animate("kb_bind_y_" .. key, -10, 12)
            keybind_anims[key].active = false
        end
    end
    
    -- Build visible binds list and assign rows
    local visible_binds = {}
    local row = 0
    for _, bind in ipairs(binds) do
        local anim = keybind_anims[bind.name]
        if anim and anim.alpha > 0.01 then
            row = row + 1
            anim.target_row = row
            table.insert(visible_binds, anim)
        end
    end
    
    -- Animate row positions smoothly
    for key, anim in pairs(keybind_anims) do
        if anim.active then
            anim.cur_row = animate("kb_bind_row_" .. key, anim.target_row, 18)
        else
            if not anim.cur_row or anim.cur_row == 0 then
                anim.cur_row = anim.target_row
            end
        end
    end
    
    -- Clean up old animations
    for key, anim in pairs(keybind_anims) do
        if not anim.active and anim.alpha < 0.01 then
            keybind_anims[key] = nil
        end
    end
    
    -- Collect all binds to draw (including fading out ones)
    local all_binds = {}
    for key, anim in pairs(keybind_anims) do
        if anim.alpha > 0.01 then
            table.insert(all_binds, anim)
        end
    end
    
    -- Sort by row position
    table.sort(all_binds, function(a, b) return a.cur_row < b.cur_row end)
    
    local sx, sy = client.screen_size()
    
    -- Get position from sliders
    local x = ui.keybinds_x:get()
    local y = ui.keybinds_y:get()
    
    -- Initialize position if needed
    if x == 0 and y == 0 then
        x = sx - 200
        y = 200
        ui.keybinds_x:set(x)
        ui.keybinds_y:set(y)
    end
    
    local alpha = keybinds.alpha
    
    local icon_r, icon_g, icon_b = ui.icon_color:get()
    local bg_r, bg_g, bg_b, bg_a = ui.background_color:get()
    local text_r, text_g, text_b, text_a = ui.text_color:get()
    
    -- Exact dimensions from screenshot
    local item_height = 26
    local item_spacing = 6
    local col_gap = 8
    local rounding = 8
    local text_padding = 8
    local outline_thickness = 1
    
    -- Header "Hotkeys" with icon
    local header_w = 100
    local header_height = 32
    local header_rounding = header_height / 2
    
    -- Blur background
    renderer.blur(x, y, header_w, header_height)
    
    -- White semi-transparent outline
    draw_rounded_rect(x, y, header_w, header_height, header_rounding, 255, 255, 255, alpha * 0.15)
    
    -- Main background (darker)
    draw_rounded_rect(x + 1, y + 1, header_w - 2, header_height - 2, header_rounding - 1, bg_r, bg_g, bg_b, alpha * (bg_a / 255))
    
    -- Keyboard icon SVG
    local keyboard_icon_svg = '<svg t="1650815150236" class="icon" viewBox="0 0 24 24" version="1.1" xmlns="http://www.w3.org/2000/svg" p-id="1757" width="24" height="24"><path fill-rule="evenodd" clip-rule="evenodd" d="M8 5H16C18.8284 5 20.2426 5 21.1213 5.87868C22 6.75736 22 8.17157 22 11V13C22 15.8284 22 17.2426 21.1213 18.1213C20.2426 19 18.8284 19 16 19H8C5.17157 19 3.75736 19 2.87868 18.1213C2 17.2426 2 15.8284 2 13V11C2 8.17157 2 6.75736 2.87868 5.87868C3.75736 5 5.17157 5 8 5ZM6 10C6.55228 10 7 9.55228 7 9C7 8.44772 6.55228 8 6 8C5.44772 8 5 8.44772 5 9C5 9.55228 5.44772 10 6 10ZM6 13C6.55228 13 7 12.5523 7 12C7 11.4477 6.55228 11 6 11C5.44772 11 5 11.4477 5 12C5 12.5523 5.44772 13 6 13ZM9 13C9.55228 13 10 12.5523 10 12C10 11.4477 9.55228 11 9 11C8.44772 11 8 11.4477 8 12C8 12.5523 8.44772 13 9 13ZM9 10C9.55228 10 10 9.55228 10 9C10 8.44772 9.55228 8 9 8C8.44772 8 8 8.44772 8 9C8 9.55228 8.44772 10 9 10ZM12 10C12.5523 10 13 9.55228 13 9C13 8.44772 12.5523 8 12 8C11.4477 8 11 8.44772 11 9C11 9.55228 11.4477 10 12 10ZM12 13C12.5523 13 13 12.5523 13 12C13 11.4477 12.5523 11 12 11C11.4477 11 11 11.4477 11 12C11 12.5523 11.4477 13 12 13ZM15 10C15.5523 10 16 9.55228 16 9C16 8.44772 15.5523 8 15 8C14.4477 8 14 8.44772 14 9C14 9.55228 14.4477 10 15 10ZM15 13C15.5523 13 16 12.5523 16 12C16 11.4477 15.5523 11 15 11C14.4477 11 14 11.4477 14 12C14 12.5523 14.4477 13 15 13ZM18 10C18.5523 10 19 9.55228 19 9C19 8.44772 18.5523 8 18 8C17.4477 8 17 8.44772 17 9C17 9.55228 17.4477 10 18 10ZM18 13C18.5523 13 19 12.5523 19 12C19 11.4477 18.5523 11 18 11C17.4477 11 17 11.4477 17 12C17 12.5523 17.4477 13 18 13ZM17.75 16C17.75 16.4142 17.4142 16.75 17 16.75H7C6.58579 16.75 6.25 16.4142 6.25 16C6.25 15.5858 6.58579 15.25 7 15.25H17C17.4142 15.25 17.75 15.5858 17.75 16Z" fill="#ffffff"></path></svg>'
    local keyboard_icon_loaded = renderer.load_svg(keyboard_icon_svg, 19, 19)
    renderer.texture(keyboard_icon_loaded, x + 14, y + 7, 19, 19, icon_r, icon_g, icon_b, alpha, 'f')
    
    renderer.text(x + 37, y + 10, text_r, text_g, text_b, alpha, "b", 0, "Hotkeys")
    
    -- Draw binds ONLY if there are any
    if #all_binds == 0 then return end
    
    local start_y = y + header_height + item_spacing
    for i, anim in ipairs(all_binds) do
        local bind_alpha = alpha * anim.alpha
        local row_y = start_y + (anim.cur_row - 1) * (item_height + item_spacing) + anim.y_offset
        
        -- Left box (value)
        local value_text = tostring(anim.mode)
        local value_w = 0
        local value_box_w = 0
        
        -- If mode is "on", draw toggle switch instead of text
        if value_text == "on" then
            local toggle_w = 16
            local toggle_h = 12
            local target_width = toggle_w + text_padding * 2
            
            -- Animate width
            if not anim.width then
                anim.width = target_width
            end
            anim.width = animate("kb_bind_width_" .. anim.name, target_width, 12)
            value_box_w = anim.width
            
            -- White semi-transparent outline for value box
            draw_rounded_rect(x, row_y, value_box_w, item_height, rounding, 255, 255, 255, bind_alpha * 0.15)
            -- Inner rectangle
            draw_rounded_rect(x + 1, row_y + 1, value_box_w - 2, item_height - 2, rounding - 1, bg_r, bg_g, bg_b, bind_alpha * (bg_a / 255) * 0.6)
            
            -- Draw toggle switch manually
            local toggle_x = x + text_padding
            local toggle_y = row_y + (item_height - toggle_h) / 2
            
            -- Toggle background (outline only) - white with opacity
            draw_rounded_rect(toggle_x, toggle_y, toggle_w, toggle_h, toggle_h / 2, 255, 255, 255, bind_alpha * 0.3)
            
            -- Toggle circle (on position - right side) - white color
            local circle_size = toggle_h - 6
            local circle_x = toggle_x + toggle_w - circle_size - 3
            local circle_y = toggle_y + 3
            renderer.circle(circle_x + circle_size / 2, circle_y + circle_size / 2, 
                255, 255, 255, bind_alpha, circle_size / 2, 0, 1)
        else
            -- Normal text for numbers and other values
            value_w = renderer.measure_text("", value_text)
            local target_width = value_w + text_padding * 2
            
            -- Animate width
            if not anim.width then
                anim.width = target_width
            end
            anim.width = animate("kb_bind_width_" .. anim.name, target_width, 12)
            value_box_w = anim.width
            
            -- White semi-transparent outline for value box
            draw_rounded_rect(x, row_y, value_box_w, item_height, rounding, 255, 255, 255, bind_alpha * 0.15)
            -- Inner rectangle
            draw_rounded_rect(x + 1, row_y + 1, value_box_w - 2, item_height - 2, rounding - 1, bg_r, bg_g, bg_b, bind_alpha * (bg_a / 255) * 0.6)
            
            local value_x = x + text_padding
            renderer.text(value_x, row_y + 7, text_r, text_g, text_b, bind_alpha, "", 0, value_text)
        end
        
        -- Right box (name)
        local name_x = x + value_box_w + col_gap
        local name_w = renderer.measure_text("", anim.name)
        local name_box_w = name_w + text_padding * 2
        
        -- White semi-transparent outline for name box
        draw_rounded_rect(name_x, row_y, name_box_w, item_height, rounding, 255, 255, 255, bind_alpha * 0.15)
        -- Inner rectangle
        draw_rounded_rect(name_x + 1, row_y + 1, name_box_w - 2, item_height - 2, rounding - 1, bg_r, bg_g, bg_b, bind_alpha * (bg_a / 255) * 0.6)
        
        local name_text_x = name_x + text_padding
        renderer.text(name_text_x, row_y + 7, text_r, text_g, text_b, bind_alpha, "", 0, anim.name)
    end
end

-- ═══════════════════════════════════════════════════════════
-- VIEWMODEL CHANGER (from embertrash)
-- ═══════════════════════════════════════════════════════════

local viewmodel = { fov = 0, x = 0, y = 0, z = 0 }; do
    local function on_paint ()
        if ui.viewmodel.enable:get() then
            viewmodel.fov = lerp('viewmodel_fov', ui.viewmodel.fov:get() * 0.1, 8, 0.001, 'ease_out')
            viewmodel.x = lerp('viewmodel_x', ui.viewmodel.x:get() * 0.1, 8, 0.001, 'ease_out')
            viewmodel.y = lerp('viewmodel_y', ui.viewmodel.y:get() * 0.1, 8, 0.001, 'ease_out')
            viewmodel.z = lerp('viewmodel_z', ui.viewmodel.z:get() * 0.1, 8, 0.001, 'ease_out')
        else
            viewmodel.fov = lerp('viewmodel_fov', 68, 8, 0.001, 'ease_out')
            viewmodel.x = lerp('viewmodel_x', 2.5, 8, 0.001, 'ease_out')
            viewmodel.y = lerp('viewmodel_y', 0, 8, 0.001, 'ease_out')
            viewmodel.z = lerp('viewmodel_z', -1.5, 8, 0.001, 'ease_out')
        end
      
        cvar.viewmodel_fov:set_raw_float(viewmodel.fov)
        cvar.viewmodel_offset_x:set_raw_float(viewmodel.x)
        cvar.viewmodel_offset_y:set_raw_float(viewmodel.y)
        cvar.viewmodel_offset_z:set_raw_float(viewmodel.z)
    end

    client.set_event_callback('paint', on_paint)
end

-- ═══════════════════════════════════════════════════════════
-- ASPECT RATIO (from embertrash)
-- ═══════════════════════════════════════════════════════════

local aspect_ratio do
    local alpha = 0
    local last_value = 0
    local function on_paint ()
        alpha = lerp('aspect_ratio_alpha', ui.aspect_ratio.enable:get() and 255 or 0, 16, 0.001, 'ease_out')
        if alpha == 0 then
            if last_value ~= 0 then
                cvar.r_aspectratio:set_int(0)
                last_value = 0
            end
            return
        end

        local x, y = client.screen_size()
        local init = x / y

        local value = ui.aspect_ratio.value:get()
        local animate = lerp('aspect_ratio_animate', ui.aspect_ratio.enable:get() and value * 0.01 or init, 8, 0.001, 'ease_out')

        if animate == init then
            if last_value ~= 0 then
                cvar.r_aspectratio:set_int(0)
                last_value = 0
            end
            return
        end

        -- Only update if value changed significantly
        if math.abs(animate - last_value) > 0.001 then
            cvar.r_aspectratio:set_float(animate)
            last_value = animate
        end
    end

    client.set_event_callback('paint', on_paint)
end

-- ═══════════════════════════════════════════════════════════
-- CUSTOM SCOPE
-- ═══════════════════════════════════════════════════════════

local function draw_custom_scope()
    if not ui.custom_scope.enable:get() then
        reference.visuals.scope:override()
        return
    end
    
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then
        return
    end
    
    local weapon = entity.get_player_weapon(me)
    if weapon == nil then
        return
    end
    
    reference.visuals.scope:override(false)
    
    local scope_level = entity.get_prop(weapon, 'm_zoomLevel')
    local scoped = entity.get_prop(me, 'm_bIsScoped') == 1
    local resume_zoom = entity.get_prop(me, 'm_bResumeZoom') == 1
    local is_valid = scope_level ~= nil
    local act = is_valid and scope_level > 0 and scoped and not resume_zoom
    
    local alpha = animate('custom_scope', act and 255 or 0, 4, 0.001, 'ease_out')
    local x, y = client.screen_size()
    
    local gap = ui.custom_scope.gap:get()
    local length = ui.custom_scope.size:get()
    local inverted = ui.custom_scope.invert:get()
    
    local r, g, b, a = ui.custom_scope.color:get()
    
    x, y = x / 2, y / 2
    
    -- left
    renderer.gradient(x - gap, y, -length * (alpha / 255), 1, r, g, b, inverted and 0 or alpha, r, g, b, inverted and alpha or 0, true)
    
    -- right
    renderer.gradient(x + gap, y, length * (alpha / 255), 1, r, g, b, inverted and 0 or alpha, r, g, b, inverted and alpha or 0, true)
    
    -- up
    renderer.gradient(x, y - gap, 1, -length * (alpha / 255), r, g, b, inverted and 0 or alpha, r, g, b, inverted and alpha or 0, false)
    
    -- down
    renderer.gradient(x, y + gap, 1, length * (alpha / 255), r, g, b, inverted and 0 or alpha, r, g, b, inverted and alpha or 0, false)
end

local function draw_custom_scope_overlay()
    if ui.custom_scope.enable:get() then
        reference.visuals.scope:override(true)
    end
end

-- ═══════════════════════════════════════════════════════════
-- SUNSET MODE
-- ═══════════════════════════════════════════════════════════

local sunset_x_cvar = cvar.cl_csm_rot_x
local sunset_y_cvar = cvar.cl_csm_rot_y
local sunset_enabled_cvar = cvar.cl_csm_rot_override
local sunset_last_state = false

local function apply_sunset_mode()
    local enabled = ui.sunset_mode.enable:get()
    
    -- Only apply when state changes or when enabled
    if enabled then
        sunset_enabled_cvar:set_int(1)
        
        local x = ui.sunset_mode.x:get()
        local y = ui.sunset_mode.y:get()
        
        sunset_x_cvar:set_float(x)
        sunset_y_cvar:set_float(y)
        
        sunset_last_state = true
    elseif sunset_last_state then
        -- Only reset when transitioning from enabled to disabled
        sunset_enabled_cvar:set_int(0)
        sunset_last_state = false
    end
end

client.set_event_callback('paint', apply_sunset_mode)

-- ═══════════════════════════════════════════════════════════
-- NADE ESP - SVG ICONS
-- ═══════════════════════════════════════════════════════════

-- FPS icon SVG
local fps_svg = '<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" id="Bold" viewBox="0 0 24 24" width="512" height="512"><path d="M5.5,21A2.5,2.5,0,0,1,3,18.5V1.5A1.5,1.5,0,0,0,1.5,0h0A1.5,1.5,0,0,0,0,1.5v17A5.5,5.5,0,0,0,5.5,24h17A1.5,1.5,0,0,0,24,22.5h0A1.5,1.5,0,0,0,22.5,21Z"/><path d="M19.5,18A1.5,1.5,0,0,0,21,16.5v-6a1.5,1.5,0,0,0-3,0v6A1.5,1.5,0,0,0,19.5,18Z"/><path d="M7.5,18A1.5,1.5,0,0,0,9,16.5v-6a1.5,1.5,0,0,0-3,0v6A1.5,1.5,0,0,0,7.5,18Z"/><path d="M13.5,18A1.5,1.5,0,0,0,15,16.5V5.5a1.5,1.5,0,0,0-3,0v11A1.5,1.5,0,0,0,13.5,18Z"/></svg>'
local fps_icon = renderer.load_svg(fps_svg, 14, 14)

-- Ping icon SVG
local ping_svg = '<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" id="Bold" viewBox="0 0 24 24" width="512" height="512"><path d="M12,0A12,12,0,1,0,24,12,12.013,12.013,0,0,0,12,0Zm8.941,11H17.463a18.368,18.368,0,0,0-2.289-7.411A9.013,9.013,0,0,1,20.941,11ZM9.685,14h4.63A16.946,16.946,0,0,1,12,19.9,16.938,16.938,0,0,1,9.685,14Zm-.132-3A16.246,16.246,0,0,1,12,4.1,16.241,16.241,0,0,1,14.447,11ZM8.826,3.589A18.368,18.368,0,0,0,6.537,11H3.059A9.013,9.013,0,0,1,8.826,3.589ZM3.232,14H6.641a18.906,18.906,0,0,0,2.185,6.411A9.021,9.021,0,0,1,3.232,14Zm11.942,6.411A18.884,18.884,0,0,0,17.359,14h3.409A9.021,9.021,0,0,1,15.174,20.411Z"/></svg>'
local ping_icon = renderer.load_svg(ping_svg, 14, 14)

-- Time icon SVG
local time_svg = '<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" id="Bold" viewBox="0 0 24 24" width="512" height="512"><path d="M12,0A12,12,0,1,0,24,12,12.013,12.013,0,0,0,12,0Zm0,21a9,9,0,1,1,9-9A9.01,9.01,0,0,1,12,21Z"/><path d="M10.5,11.055l-2.4,1.5a1.5,1.5,0,0,0-.475,2.068h0a1.5,1.5,0,0,0,2.068.475l2.869-1.8a2,2,0,0,0,.938-1.7V7.772a1.5,1.5,0,0,0-1.5-1.5h0a1.5,1.5,0,0,0-1.5,1.5Z"/></svg>'
local time_icon = renderer.load_svg(time_svg, 14, 14)

-- Smoke grenade SVG icon
local smoke_svg = '<?xml version="1.0" encoding="utf-8"?><!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"><svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px" width="12.333px" height="32px" viewBox="0 0 12.333 32" enable-background="new 0 0 12.333 32" xml:space="preserve"><g id="Selected_Items"><g><g id="Selected_Items_59_"><path fill-rule="evenodd" clip-rule="evenodd" fill="#FFFFFF" d="M8.413,6.784L8.449,6.82v0.073c0,0.025,0.013,0.036,0.036,0.036v0.074h0.037v0.035c0.024,0,0.038,0.013,0.038,0.036v0.11h0.036v0.073h0.036v0.073c0.024,0,0.037,0.012,0.037,0.035v0.11l0.036,0.036v0.072L8.74,7.622v0.036h0.038v0.073l0.036,0.036v0.037c0.025,0,0.036,0.012,0.036,0.036v0.036l0.037,0.037v0.109c0,0.023,0.012,0.036,0.036,0.036v0.037h0.037v0.108h0.036v0.037l0.037,0.036v0.037l0.036,0.035v0.074l0.037,0.036v0.107l0.037,0.038v0.037l0.036,0.035v0.037L9.25,8.789v0.035c0.024,0,0.037,0.014,0.037,0.037l0.035,0.037V9.08L9.36,9.117v0.072l0.038,0.036v0.036l0.035,0.037v0.037L9.47,9.371v0.072h0.036v0.074c0,0.024,0.013,0.036,0.036,0.036v0.108c0.025,0,0.037,0.013,0.037,0.037v0.073c0.024,0,0.037,0.013,0.037,0.037v0.072h0.037v0.036l0.036,0.037v0.036l0.037,0.036v0.037l0.037,0.036v0.146l0.036,0.037v0.072h0.037v0.108h0.037v0.073l0.036,0.037v0.037l0.037,0.036v0.073c0.024,0,0.036,0.011,0.036,0.035v0.073c0,0.024,0.012,0.037,0.037,0.037v0.072l0.036,0.036v0.037h0.038v0.036l0.036,0.037v0.036l0.037,0.036v0.073h0.037v0.108l0.037,0.036v0.037c0,0.023,0.011,0.036,0.036,0.036v0.036l0.037,0.037v0.109l0.072,0.072v0.073l0.037,0.037v0.036h0.036v0.073h0.037c0,0.023,0.012,0.036,0.036,0.036v0.036l0.147,0.146v0.474l0.036,0.035v0.074c0.023,0,0.035,0.012,0.035,0.035l0.039,0.037v0.036l0.035,0.036v0.036h0.037v0.075c0.024,0,0.037,0.011,0.037,0.035l0.036,0.037v0.035h0.036v0.037l0.073,0.073c0,0.023,0.012,0.036,0.037,0.036v0.036h0.037v0.036l0.109,0.146v0.255c0.024,0.025,0.047,0.036,0.073,0.036v0.474c0,0.098,0,0.17,0,0.22c0,0.072,0,0.145,0,0.218v0.184c0,0.071,0,0.144,0,0.218v0.182c0,0.097,0,0.183,0,0.256c0,0.047,0,0.12,0,0.219c0,0.048,0,0.121,0,0.218c0,0.049,0,0.108,0,0.182v0.036c0,0.049,0,0.11,0,0.184c0,0.048,0,0.121,0,0.219c0,0.048,0,0.121,0,0.219c0,0.049,0,0.108,0,0.182c0,0.072,0,0.146,0,0.218c0,0.073,0,0.146,0,0.219c0,0.073,0,0.147,0,0.22c0,0.073,0,0.133,0,0.182c0,0.097,0,0.17,0,0.219c0,0.073,0,0.146,0,0.218c0,0.073,0,0.146,0,0.221c0,0.071,0,0.133,0,0.181c0,0.098,0,0.17,0,0.219c0,0.073,0,0.146,0,0.219c0,0.073,0,0.146,0,0.219c0,0.073,0,0.146,0,0.219s0,0.146,0,0.218c0,0.05,0,0.122,0,0.22c0,0.049,0,0.12,0,0.219c0,0.049,0,0.109,0,0.182c0,0.073,0,0.146,0,0.218c0,0.05,0,0.122,0,0.219c0,0.049,0,0.122,0,0.22c0,0.048,0,0.108,0,0.182s0,0.146,0,0.22c0,0.072,0,0.145,0,0.217c0,0.073,0,0.146,0,0.22s0,0.134,0,0.182c0,0.098,0,0.171,0,0.219c0,0.073,0,0.146,0,0.219c0,0.073,0,0.146,0,0.219c0,0.073,0,0.133,0,0.183c0,0.096,0,0.17,0,0.218c0,0.073,0,0.146,0,0.22c0,0.072,0,0.145,0,0.218s0,0.146,0,0.219c0,0.073,0,0.146,0,0.219c0,0.049,0,0.121,0,0.219c0,0.049,0,0.122,0,0.219c0,0.049,0,0.108,0,0.182c0,0.072,0,0.146,0,0.22c0,0.047,0,0.121,0,0.218c0,0.048,0,0.122,0,0.219c0,0.048,0,0.108,0,0.182c0,0.074,0,0.146,0,0.219c0,0.073,0,0.146,0,0.219c0,0.073,0,0.146,0,0.219c0,0.073,0,0.134,0,0.183c0,0.096,0,0.17,0,0.219c0,0.072,0,0.146,0,0.219c0,0.072,0,0.146,0,0.218c0,0.073,0,0.134,0,0.183c0,0.098,0,0.17,0,0.219c0,0.073,0,0.146,0,0.219c0,0.072,0,0.158,0,0.256v0.072c-0.025,0-0.061,0-0.109,0v0.035c-0.025,0-0.037,0.013-0.037,0.036l-0.036,0.074h-0.074v0.035L11,28.065v0.036h-0.037v0.072c-0.169,0-0.34,0-0.509,0v-0.583l0.072-0.072c0.024,0,0.037-0.014,0.037-0.037h0.036v-0.036h0.036v-0.036h0.038c0-0.073,0-0.135,0-0.183c0-0.072,0-0.121,0-0.146c0-0.073,0-0.145,0-0.218c0-0.072,0-0.147,0-0.22c0-0.071,0-0.146,0-0.219c0-0.072,0-0.146,0-0.218c0-0.049,0-0.123,0-0.219c0-0.049,0-0.109,0-0.184c0-0.072,0-0.145,0-0.219c0-0.072,0-0.146,0-0.218c0-0.048,0-0.121,0-0.219c0-0.048,0-0.108,0-0.182s0-0.146,0-0.219c0-0.072,0-0.146,0-0.22c0-0.071,0-0.145,0-0.219c0-0.072,0-0.133,0-0.181c0-0.098,0-0.171,0-0.219c0-0.097,0-0.171,0-0.219c0-0.073,0-0.146,0-0.22c0-0.071,0-0.133,0-0.181c0-0.098,0-0.171,0-0.22c0-0.097,0-0.17,0-0.218c0-0.073,0-0.146,0-0.22c0-0.072,0-0.145,0-0.219c0-0.072,0-0.145,0-0.219c0-0.072,0-0.145,0-0.218c0-0.048,0-0.122,0-0.219c0-0.049,0-0.109,0-0.182c0-0.073,0-0.146,0-0.219s0-0.146,0-0.219c0-0.049,0-0.121,0-0.22c0-0.049,0-0.108,0-0.182s0-0.146,0-0.219c0-0.097,0-0.17,0-0.218c0-0.074,0-0.146,0-0.22c0-0.072,0-0.133,0-0.182c0-0.097,0-0.17,0-0.219c0-0.097,0-0.17,0-0.218c0-0.073,0-0.146,0-0.219c0-0.073,0-0.135,0-0.183c0-0.097,0-0.182,0-0.256c0-0.072,0-0.145,0-0.218c0-0.05,0-0.122,0-0.219c0-0.049,0-0.109,0-0.182c0-0.073,0-0.146,0-0.22c0-0.072,0-0.145,0-0.218c0-0.049,0-0.121,0-0.218c0-0.051,0-0.11,0-0.184s0-0.146,0-0.219c0-0.072,0-0.146,0-0.22c0-0.071,0-0.144,0-0.218c0-0.072,0-0.133,0-0.182c0-0.098,0-0.17,0-0.22c0-0.097,0-0.169,0-0.218c0-0.073,0-0.146,0-0.218c0-0.073,0-0.135,0-0.183c0-0.097,0-0.171,0-0.219c0-0.097,0-0.171,0-0.219c0-0.073,0-0.146,0-0.219c0-0.073,0-0.146,0-0.218c0-0.073,0-0.146,0-0.22c0-0.072,0-0.145,0-0.218c0-0.049,0-0.122,0-0.22c0-0.048,0-0.108,0-0.182v-0.036c-0.025,0-0.05,0-0.074,0l-0.036-0.037v-0.036l-0.037-0.036V13.78H10.49v-0.036l-0.037-0.036v-0.036l-0.036-0.037v-0.072l-0.037-0.037v-0.036h-0.037v-0.073h-0.036V13.38l-0.037-0.036h-0.036c0-0.025-0.012-0.037-0.037-0.037v-0.072c0-0.025-0.013-0.036-0.037-0.036v-0.037h-0.037v-0.073c-0.023,0-0.036-0.012-0.036-0.035c0-0.025-0.013-0.037-0.038-0.037V12.98h-0.036v-0.037l-0.037-0.074c0-0.023-0.012-0.036-0.036-0.036v-0.036l-0.109-0.072v-0.037H9.797v-0.072c-0.024,0-0.036-0.014-0.036-0.037l-0.037-0.036v-0.037H9.688v-0.036c-0.024-0.024-0.047-0.036-0.072-0.036v-0.037H9.578v-0.036c-0.023,0-0.037-0.013-0.037-0.037V12.25c-0.023,0-0.036-0.013-0.036-0.037L9.47,12.178v-0.036H9.432l-0.11-0.146v-0.036c-0.023,0-0.035-0.013-0.035-0.036H9.25v17.782l-0.146,0.036c-0.048,0.024-0.097,0.061-0.145,0.109H8.923c-0.583,0.315-1.13,0.534-1.64,0.655c-0.608,0.194-1.189,0.316-1.75,0.364c-0.51,0.099-1.008,0.121-1.493,0.073c-0.461-0.049-0.875-0.109-1.239-0.182C2,30.591,1.38,30.385,0.943,30.142c-0.219-0.097-0.389-0.182-0.51-0.254c-0.17-0.074-0.255-0.122-0.255-0.146l-0.109-0.036V11.887c-0.097-0.195-0.061-0.402,0.109-0.621c0-0.023,0.013-0.048,0.036-0.072c0.074-0.023,0.147-0.036,0.219-0.036v-0.036c0.122-0.05,0.279-0.086,0.473-0.109c0.194-0.025,0.474-0.05,0.839-0.073c0.193-0.048,0.4-0.085,0.62-0.109c0.17-0.024,0.291-0.036,0.363-0.036c-0.024-0.219-0.024-0.389,0-0.51c0.048-0.073,0.086-0.134,0.11-0.183l0.109-0.146V8.351H2.91c-0.121,0-0.255-0.011-0.401-0.035c-0.17,0-0.34,0-0.51,0V7.805h0.036V7.768c0.024,0,0.048,0,0.073,0c-0.048-0.072-0.048-0.182,0-0.327c0-0.073,0.048-0.194,0.146-0.365c0.072-0.169,0.195-0.267,0.365-0.291h4.3L7.1,6.856v0.147c0.146-0.293,0.328-0.547,0.547-0.766V6.202c0-0.025,0-0.049,0-0.073c0.025,0,0.06,0,0.11,0c0-0.025,0.011-0.036,0.036-0.036v0.036c0.121,0,0.243,0,0.364,0V6.53l0.037,0.036v0.036c0.047,0,0.109,0,0.182,0v0.036l0.037,0.036V6.784z M8.887,24.858c0-0.025,0-0.062,0-0.109v-0.11c-1.967,0.293-3.341,0.438-4.118,0.438c-0.802,0-2.234-0.145-4.3-0.438c0,0.025,0,0.05,0,0.073c0,0.025,0,0.049,0,0.074v0.51c0,0.024,0,0.049,0,0.072c0,0.024,0,0.049,0,0.072v0.073c0,0.025,0,0.049,0,0.072c0,0.025,0,0.05,0,0.074s0,0.049,0,0.072v0.072c0,0.025,0,0.05,0,0.074s0,0.049,0,0.072v0.037c2.09,0.364,3.546,0.546,4.373,0.546c0.873,0,2.224-0.17,4.045-0.511v-0.4c0-0.023,0-0.048,0-0.072v-0.037c0-0.048,0-0.084,0-0.109c0-0.023,0-0.048,0-0.073v-0.035c0-0.025,0-0.049,0-0.073s0-0.061,0-0.109v-0.037c0-0.024,0-0.049,0-0.072c0-0.024,0-0.049,0-0.072C8.887,24.907,8.887,24.882,8.887,24.858z"/></g></g></g></svg>'
local smoke_icon = renderer.load_svg(smoke_svg, 12, 24)

-- Molotov SVG icon
local molotov_svg = '<?xml version="1.0" encoding="utf-8"?><!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"><svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px" width="18.833px" height="32px" viewBox="0 0 18.833 32" enable-background="new 0 0 18.833 32" xml:space="preserve"><g id="Selected_Items"><g><g id="Selected_Items_58_"><path fill-rule="evenodd" clip-rule="evenodd" fill="#FFFFFF" d="M15.826,7.595c0.05,0.074,0.185,0.259,0.407,0.554c0.172,0.224,0.308,0.285,0.406,0.186c0.099-0.099,0-0.382-0.295-0.851c-0.321-0.493-0.271-1.035,0.148-1.628c0.049,0.247,0.345,0.617,0.888,1.11c0.543,0.518,0.875,1.023,0.999,1.517c0.049,0.246,0.061,0.493,0.037,0.739c-0.049,0.37-0.148,0.666-0.295,0.888c-0.247,0.321-0.382,0.53-0.407,0.63c-0.075,0.173-0.013,0.382,0.185,0.629c0.172,0.245,0.123,0.578-0.148,0.998c-0.173,0.246-0.567,0.715-1.183,1.405c-0.355,0.396-0.879,0.618-1.573,0.666c0.172-0.279,0.351-0.575,0.537-0.887c0.099,0,0.161-0.014,0.186-0.038l1.11-1.517c0.049-0.099-0.014-0.259-0.186-0.48c-0.197-0.222-0.456-0.456-0.776-0.704c-0.32-0.22-0.617-0.381-0.888-0.48c-0.295-0.122-0.469-0.136-0.518-0.036l-1.11,1.517h0.038c-0.024,0.05-0.024,0.123,0,0.221c-0.425,0.508-0.801,0.957-1.128,1.351c-0.036-0.027-0.067-0.059-0.093-0.091c-0.198-0.271-0.382-0.642-0.555-1.11c-0.197-0.666-0.234-1.208-0.111-1.627c0.198-0.371,0.345-0.642,0.444-0.815c0.173-0.345,0.173-0.813,0-1.405l0.407,0.148c0.32,0.173,0.555,0.444,0.702,0.813c0.075,0.124,0.111,0.457,0.111,0.999c0,0.418,0.011,0.555,0.037,0.406c0.295-0.394,0.48-0.801,0.554-1.22c0.025-0.246-0.135-0.629-0.48-1.147c-0.443-0.542-0.714-0.888-0.813-1.035c-0.148-0.223-0.21-0.739-0.186-1.553c0.025-0.839,0.148-1.369,0.37-1.591c0.05,0.518,0.271,0.974,0.666,1.368c0.198,0.196,0.728,0.419,1.59,0.666c0.346,0.099,0.555,0.309,0.629,0.629C15.653,7.262,15.752,7.52,15.826,7.595z"/><path fill-rule="evenodd" clip-rule="evenodd" fill="#FFFFFF" d="M14.975,10.331c0.271,0.1,0.568,0.261,0.888,0.48c0.32,0.248,0.58,0.482,0.776,0.704c0.172,0.222,0.235,0.382,0.186,0.48l-1.11,1.517c-0.025,0.024-0.087,0.038-0.186,0.038c-1.356,2.269-2.158,3.574-2.404,3.92c-0.099,0.122-0.21,0.803-0.334,2.034c-0.147,1.208-0.406,2.084-0.776,2.626L5.58,31.157c-0.197,0.172-0.641,0.185-1.332,0.037c-0.739-0.197-1.455-0.543-2.144-1.037c-0.691-0.491-1.246-1.06-1.666-1.7c-0.37-0.593-0.505-1.011-0.407-1.259l6.437-9.062c0.37-0.544,1.11-1.072,2.22-1.591c0.271-0.123,0.641-0.296,1.109-0.518c0.346-0.173,0.567-0.32,0.667-0.443c0.148-0.224,1.122-1.406,2.922-3.553c-0.024-0.098-0.024-0.171,0-0.221h-0.038l1.11-1.517C14.506,10.195,14.679,10.209,14.975,10.331z"/></g></g></g><g id="guides"></g></svg>'
local molotov_icon = renderer.load_svg(molotov_svg, 12, 24)

-- HE grenade SVG icon  
local he_svg = '<?xml version="1.0" encoding="utf-8"?><!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"><svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px" width="78px" height="128px" viewBox="0 0 78 128" enable-background="new 0 0 78 128" xml:space="preserve"><path fill="#FFFFFF" d="M48 28.4c0 1.1-2.5 1.5-12.1 1.8-11.3.3-12.2.4-14 2.7-2.5 3-1.9 4.7 1.5 4.4l2.6-.2v9.4c0 5.2.4 9.7 1 10s1 2.6 1 5.1c0 3.9-.3 4.4-2.2 4.4-1.3 0-4.7.7-7.7 1.5C7 70.4 1.4 79.9 2.2 94.8c.6 13.5 7.5 22.9 20.1 27.7 7.7 2.9 12.3 3.1 22.1 1 7.8-1.7 14.2-5.1 18.1-9.7 3.6-4.2 7.3-12.8 8.1-18.6.8-6.6-2.9-18.7-6.9-22.4-2.9-2.8-11-5.8-15.4-5.8-2.1 0-2.3-.4-2.3-5v-5h5.9c5.6 0 6.2.2 8.4 3.2 3.4 4.7 6.3 9.5 9.4 15.8 2.8 5.5 2.8 5.6 2.8 26.2 0 16 .3 20.8 1.3 20.8 1.4 0 1.5-2.1 1.2-26l-.2-17.5-3.8-8C56.2 40.2 52.9 33.3 52 31.8c-.6-1-1-2.5-1-3.3s-.7-1.5-1.5-1.5-1.5.6-1.5 1.4"/></svg>'
local he_icon = renderer.load_svg(he_svg, 12, 20)

-- ═══════════════════════════════════════════════════════════
-- NADE ESP
-- ═══════════════════════════════════════════════════════════

local function draw_nade_esp()
    if not ui.nade_esp.enable:get() then return end
    
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then return end
    
    local icon_size = ui.nade_esp.size:get()
    local he_r, he_g, he_b, he_a = ui.nade_esp.he_color:get()
    local smoke_r, smoke_g, smoke_b, smoke_a = ui.nade_esp.smoke_color:get()
    local molotov_r, molotov_g, molotov_b, molotov_a = ui.nade_esp.molotov_color:get()
    
    -- Grenade types
    local grenade_types = {
        {class = "CBaseCSGrenadeProjectile", icon = "HE", color = {he_r, he_g, he_b}},
        {class = "CMolotovProjectile", icon = "ML", color = {molotov_r, molotov_g, molotov_b}},
        {class = "CInferno", icon = "FR", color = {molotov_r, molotov_g, molotov_b}},
        {class = "CSmokeGrenadeProjectile", icon = "SM", color = {smoke_r, smoke_g, smoke_b}}
    }
    
    for _, nade_type in ipairs(grenade_types) do
        local grenades = entity.get_all(nade_type.class)
        
        if grenades and #grenades > 0 then
            for i = 1, #grenades do
                local ent = grenades[i]
                
                -- Get position
                local x, y, z = entity.get_origin(ent)
                
                if x and y and z then
                    -- Convert to screen
                    local sx, sy = renderer.world_to_screen(x, y, z)
                    
                    if sx and sy then
                        local r, g, b = nade_type.color[1], nade_type.color[2], nade_type.color[3]
                        
                        -- Get velocity for trajectory
                        local vx = entity.get_prop(ent, "m_vecVelocity[0]")
                        local vy = entity.get_prop(ent, "m_vecVelocity[1]") 
                        local vz = entity.get_prop(ent, "m_vecVelocity[2]")
                        
                        -- Draw trajectory line
                        if vx and vy and vz then
                            local speed = math.sqrt(vx*vx + vy*vy + vz*vz)
                            if speed > 50 then
                                local steps = 20
                                local prev_sx, prev_sy = sx, sy
                                
                                for step = 1, steps do
                                    local t = step * 0.05
                                    local px = x + vx * t
                                    local py = y + vy * t
                                    local pz = z + vz * t - 400 * t * t  -- Gravity
                                    
                                    local psx, psy = renderer.world_to_screen(px, py, pz)
                                    
                                    if psx and psy and prev_sx and prev_sy then
                                        local alpha = math.max(50, 255 - (step * 10))
                                        renderer.line(prev_sx, prev_sy, psx, psy, r, g, b, alpha)
                                        prev_sx, prev_sy = psx, psy
                                    else
                                        break
                                    end
                                end
                            end
                        end
                        
                        -- Draw grenade icon
                        if nade_type.class == "CSmokeGrenadeProjectile" then
                            -- Draw smoke SVG icon with dynamic size and color
                            local icon_w = icon_size
                            local icon_h = icon_size * 2  -- Keep 1:2 aspect ratio
                            renderer.texture(smoke_icon, sx - icon_w / 2, sy - icon_h / 2, icon_w, icon_h, smoke_r, smoke_g, smoke_b, 255, 'f')
                        elseif nade_type.class == "CMolotovProjectile" or nade_type.class == "CInferno" then
                            -- Draw molotov SVG icon with dynamic size and color
                            local icon_w = icon_size
                            local icon_h = icon_size * 2  -- Keep 1:2 aspect ratio
                            renderer.texture(molotov_icon, sx - icon_w / 2, sy - icon_h / 2, icon_w, icon_h, molotov_r, molotov_g, molotov_b, 255, 'f')
                        elseif nade_type.class == "CBaseCSGrenadeProjectile" then
                            -- Draw HE grenade SVG icon with dynamic size and color
                            -- Check if grenade is still active (not exploded)
                            local is_active = entity.get_prop(ent, "m_nExplodeEffectTickBegin")
                            if is_active == 0 and he_icon then
                                local icon_w = icon_size
                                local icon_h = icon_size * 1.64  -- Match viewBox ratio 78:128
                                renderer.texture(he_icon, sx - icon_w / 2, sy - icon_h / 2, icon_w, icon_h, he_r, he_g, he_b, 255, 'f')
                            elseif is_active == 0 then
                                -- Fallback: draw circle if icon failed to load
                                renderer.circle(sx, sy, 255, 255, 255, 255, 6, 0, 1)
                                renderer.circle_outline(sx, sy, he_r, he_g, he_b, 255, 6, 0, 1, 2)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- RAGEBOT FEATURES
-- ═══════════════════════════════════════════════════════════

-- Unsafe exploit recharge (from embertrash lines 3967-4010)
local unsafe_recharge = { timer = globals.tickcount(), ticks = 15 }; do
    local function on_setup_command ()
        if not ui.unsafe_exploit:get() then
            return
        end
    
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then
            reference.rage.aimbot.enabled[1]:set_hotkey('Always on')
            return
        end
    
        local doubletap_ref = reference.rage.aimbot.double_tap[1]:get() and reference.rage.aimbot.double_tap[1].hotkey:get() and not reference.rage.other.fake_duck:get()
        local osaa_ref = reference.antiaim.other.on_shot_anti_aim[1]:get() and reference.antiaim.other.on_shot_anti_aim[1].hotkey:get() and not reference.rage.other.fake_duck:get()
    
        local weapon = entity.get_player_weapon(me)
        if not weapon then 
            reference.rage.aimbot.enabled[1]:set_hotkey('Always on')
            return
        end
    
        local weapon_id = entity.get_prop(weapon, 'm_iItemDefinitionIndex')
        unsafe_recharge.ticks = (weapon_id == 64) and 17 or 15  -- 64 = Revolver
    
        if (doubletap_ref) or (osaa_ref) then
            if globals.tickcount() >= unsafe_recharge.timer + unsafe_recharge.ticks then
                reference.rage.aimbot.enabled[1]:set_hotkey('Always on')
            else
                reference.rage.aimbot.enabled[1]:set_hotkey('On hotkey')
            end
        else
            unsafe_recharge.timer = globals.tickcount()
    
            reference.rage.aimbot.enabled[1]:set_hotkey('Always On')
        end
    end
    
    client.set_event_callback('setup_command', on_setup_command)
end

-- Predict enemies (from embertrash lines 5123-5148)
local predict_enemies do
    local function on_paint_ui ()
        -- Custom scope overlay removal
        draw_custom_scope_overlay()
        
        -- Update manual yaw
        manual_yaw.update()
        
        if not ui.predict_enemies:get() then
            return
        end

        cvar.cl_interp_ratio:set_int(2)
        cvar.cl_interpolate:set_int(1)
    end

    local function on_pre_render ()
        if not ui.predict_enemies:get() then
            cvar.cl_interpolate:set_int(1)
            cvar.cl_interp_ratio:set_int(2)
            return
        end
      
        cvar.cl_interpolate:set_int(0)
        cvar.cl_interp_ratio:set_int(1)
    end

    client.set_event_callback('paint_ui', on_paint_ui)
    client.set_event_callback('pre_render', on_pre_render)
end

-- Aim punch fix (from embertrash lines 4102-4130)
local aim_punch_fix = { last_health = 100, override_active = false }; do
    local function on_setup_command()
        if not ui.aim_punch_fix:get() then
            if aim_punch_fix.override_active then
                reference.rage.aimbot.minimum_hitchance:override()
                aim_punch_fix.override_active = false
            end
            return
        end
        
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then
            aim_punch_fix.last_health = 100
            if aim_punch_fix.override_active then
                reference.rage.aimbot.minimum_hitchance:override()
                aim_punch_fix.override_active = false
            end
            return
        end

        local current_health = entity.get_prop(me, 'm_iHealth') or 100

        if current_health < aim_punch_fix.last_health then
            reference.rage.aimbot.minimum_hitchance:override(100)
            aim_punch_fix.override_active = true
        elseif aim_punch_fix.override_active then
            reference.rage.aimbot.minimum_hitchance:override()
            aim_punch_fix.override_active = false
        end

        aim_punch_fix.last_health = current_health
    end

    client.set_event_callback('setup_command', on_setup_command)
end

-- ═══════════════════════════════════════════════════════════
-- ANTI-AIM BUILDER
-- ═══════════════════════════════════════════════════════════

-- Set default antiaim settings on load
do
    reference.antiaim.angles.enabled:override(true)
    reference.antiaim.angles.pitch[1]:override('Minimal')
    reference.antiaim.angles.yaw_base:override('At targets')
    reference.antiaim.angles.yaw[1]:override('180')
    reference.antiaim.angles.yaw[2]:override(0)
end

-- Builder state
local builder = {
    side = 1,
    current_tick = 0,
    delay_ticks = { default = 0, defensive = 0 },
    delay_tick_counter = 0,
    state = 'Global'  -- Cached state
}

-- Get current state
local function get_builder_state()
    local state = helpers.get_state()
    
    -- Check if slow motion hotkey is active and state is Run
    if state == 'Run' then
        if reference.antiaim.other.slow_motion[1] and reference.antiaim.other.slow_motion[1].hotkey then
            if reference.antiaim.other.slow_motion[1].hotkey:get() then
                state = 'Walk'
            end
        end
    end
    
    -- Always return state for display, even if not enabled
    return state
end

-- Get current state for antiaim (checks if enabled)
local function get_builder_state_for_aa()
    local state = get_builder_state()
    
    -- Check if state is enabled, if not use Global
    if state ~= 'Global' and ui.builder[state] and not ui.builder[state].enable:get() then
        state = 'Global'
    end
    
    -- Check if Global is enabled, if not return nil
    if state == 'Global' and not ui.builder['Global'].enable:get() then
        return nil
    end
    
    return state
end

-- Inverter function (from aesthetic_skeet logic)
local function inverter(e, state)
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return builder.side end
    
    local condition = ui.builder
    
    if e.chokedcommands == 0 then
        local body_yaw_mode = condition[state].body_yaw:get()
        local delay_enabled = condition[state].jitter_delay_enable:get()
        
        if body_yaw_mode == 'Jitter' and delay_enabled then
            local delay = condition[state].jitter_delay:get()
            
            -- Handle randomize delay
            if condition[state].jitter_delay_randomize:get() then
                local delay_min = condition[state].jitter_delay_min:get()
                local delay_max = condition[state].jitter_delay_max:get()

                if condition[state].jitter_small_delay_min_toggle:get() then
                    delay_min = condition[state].jitter_small_delay_min:get() * 0.2
                end

                if condition[state].jitter_small_delay_max_toggle:get() then
                    delay_max = condition[state].jitter_small_delay_max:get() * 0.2
                end

                math.randomseed(globals.tickcount())
                delay = math.random(delay_min, delay_max)
            end
            
            delay = math.max(1, delay)
            
            -- Increment counter
            builder.delay_tick_counter = builder.delay_tick_counter + 1
            
            -- Check if we should flip
            if builder.delay_tick_counter >= delay then
                builder.side = builder.side == 1 and -1 or 1
                builder.delay_tick_counter = 0
            end
        else
            -- Normal inverter (flip every tick)
            builder.side = builder.side == 1 and -1 or 1
            builder.delay_tick_counter = 0
        end
    end

    return builder.side
end

-- ═══════════════════════════════════════════════════════════
-- DEFENSIVE AA BUILDER
-- ═══════════════════════════════════════════════════════════

-- Defensive jitter state
local defensive_jitter = {
    pitch_last_switch = {},  -- Last tick when pitch switched for each state
    pitch_current = {},      -- Current pitch index (1 or 2) for each state
    pitch_random_last = {},  -- Last tick when random pitch was generated
    pitch_random_value = {}, -- Current random pitch value
    yaw_last_switch = {},    -- Last tick when yaw switched for each state
    yaw_current = {},        -- Current yaw index (1 or 2) for each state
    yaw_random_last = {},    -- Last tick when random yaw was generated
    yaw_random_value = {}    -- Current random yaw value
}

-- Apply defensive AA (simplified - static pitch + 180 yaw with offset)
local function apply_defensive_aa(cmd, state, manual_active, freestanding_active, manual_offset)
    -- Wrap in pcall to catch any errors
    local success, result = pcall(function()
        local settings = ui.defensive[state]
        
        if not settings then
            return false
        end
        
        if not settings.enable then
            return false
        end
        
        if not settings.enable:get() then
            return false
        end
        
        -- Check if defensive is enabled for current exploit
        if not settings.defensive_on then
            return false
        end
        
        local defensive_on_success, defensive_on = pcall(function() return settings.defensive_on:get() end)
        if not defensive_on_success then
            return false
        end
        
        -- Use exploits helper methods instead of direct reference access
        local dt_active = exploits:is_doubletap()
        local hs_active = exploits:is_hideshots()
    
        local should_work = false
        for i = 1, #defensive_on do
            if defensive_on[i] == 'Double tap' and dt_active then
                should_work = true
                break
            elseif defensive_on[i] == 'Hide shots' and hs_active and not dt_active then
                should_work = true
                break
            end
        end
        
        if not should_work then
            return false
        end
        
        -- Check defensive mode and set force defensive
        local defensive_mode = settings.defensive_mode:get()
        
        if defensive_mode == 'On peek' then
            exploits:should_force_defensive(false)
        elseif defensive_mode == 'Always on' then
            exploits:should_force_defensive(true)
        end
        
        -- Check if we're in defensive OR if static AA is active (manual/freestanding)
        local in_def = exploits:in_defensive()
        
        -- Check if Static AA is active
        local static_aa_options = ui.static_aa:get()
        local should_static_aa = false
        
        for i = 1, #static_aa_options do
            local option = static_aa_options[i]
            if option == 'On Manual' and manual_active then
                should_static_aa = true
                break
            elseif option == 'On Freestanding' and freestanding_active and not manual_active then
                should_static_aa = true
                break
            end
        end
        
        -- If static AA is active, disable defensives
        if should_static_aa then
            return false
        end
        
        -- If not in defensive, return false
        if not in_def then
            return false
        end
        
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then return false end
        
        -- Apply pitch based on mode
        local pitch_mode = settings.pitch_mode:get()
        local pitch_value = 89
        
        if pitch_mode == 'Static' then
            pitch_value = settings.pitch:get()
        elseif pitch_mode == 'Jitter' then
            -- Initialize jitter state for this state if needed
            if not defensive_jitter.pitch_last_switch[state] then
                defensive_jitter.pitch_last_switch[state] = globals.tickcount()
                defensive_jitter.pitch_current[state] = 1
            end
            
            local current_tick = globals.tickcount()
            local delay = settings.pitch_delay:get()
            
            -- Check if it's time to switch
            if current_tick - defensive_jitter.pitch_last_switch[state] >= delay then
                defensive_jitter.pitch_last_switch[state] = current_tick
                defensive_jitter.pitch_current[state] = defensive_jitter.pitch_current[state] == 1 and 2 or 1
            end
            
            -- Get current pitch value
            if defensive_jitter.pitch_current[state] == 1 then
                pitch_value = settings.pitch_first:get()
            else
                pitch_value = settings.pitch_second:get()
            end
        elseif pitch_mode == 'Random' then
            -- Initialize random state for this state if needed
            if not defensive_jitter.pitch_random_last[state] then
                defensive_jitter.pitch_random_last[state] = globals.tickcount()
                defensive_jitter.pitch_random_value[state] = client.random_int(settings.pitch_min:get(), settings.pitch_max:get())
            end
            
            local current_tick = globals.tickcount()
            local delay = settings.pitch_random_delay:get()
            
            -- Check if it's time to generate new random value
            if current_tick - defensive_jitter.pitch_random_last[state] >= delay then
                defensive_jitter.pitch_random_last[state] = current_tick
                defensive_jitter.pitch_random_value[state] = client.random_int(settings.pitch_min:get(), settings.pitch_max:get())
            end
            
            pitch_value = defensive_jitter.pitch_random_value[state]
        end
        
        -- Apply yaw based on mode
        local yaw_mode = settings.yaw_mode:get()
        local yaw_value = 0
        
        if yaw_mode == 'Static' then
            yaw_value = settings.yaw_offset:get()
        elseif yaw_mode == 'Jitter' then
            -- Initialize jitter state for this state if needed
            if not defensive_jitter.yaw_last_switch[state] then
                defensive_jitter.yaw_last_switch[state] = globals.tickcount()
                defensive_jitter.yaw_current[state] = 1
            end
            
            local current_tick = globals.tickcount()
            local delay = settings.yaw_delay:get()
            
            -- Check if it's time to switch
            if current_tick - defensive_jitter.yaw_last_switch[state] >= delay then
                defensive_jitter.yaw_last_switch[state] = current_tick
                defensive_jitter.yaw_current[state] = defensive_jitter.yaw_current[state] == 1 and 2 or 1
            end
            
            -- Get current yaw value (just the offset, not 180 + offset)
            if defensive_jitter.yaw_current[state] == 1 then
                yaw_value = settings.yaw_first:get()
            else
                yaw_value = settings.yaw_second:get()
            end
        elseif yaw_mode == 'Random' then
            -- Initialize random state for this state if needed
            if not defensive_jitter.yaw_random_last[state] then
                defensive_jitter.yaw_random_last[state] = globals.tickcount()
                defensive_jitter.yaw_random_value[state] = client.random_int(settings.yaw_min:get(), settings.yaw_max:get())
            end
            
            local current_tick = globals.tickcount()
            local delay = settings.yaw_random_delay:get()
            
            -- Check if it's time to generate new random value
            if current_tick - defensive_jitter.yaw_random_last[state] >= delay then
                defensive_jitter.yaw_random_last[state] = current_tick
                defensive_jitter.yaw_random_value[state] = client.random_int(settings.yaw_min:get(), settings.yaw_max:get())
            end
            
            yaw_value = defensive_jitter.yaw_random_value[state]
        end
        
        -- Calculate angle to closest enemy
        local me = entity.get_local_player()
        local lx, ly, lz = entity.get_prop(me, 'm_vecOrigin')
        
        -- Find closest enemy
        local enemies = entity.get_players(true)
        local closest_enemy = nil
        local closest_dist = math.huge
        
        for i = 1, #enemies do
            local enemy = enemies[i]
            if entity.is_alive(enemy) then
                local ex, ey, ez = entity.get_prop(enemy, 'm_vecOrigin')
                if ex and lx then
                    local dist = math.sqrt((ex - lx)^2 + (ey - ly)^2)
                    if dist < closest_dist then
                        closest_dist = dist
                        closest_enemy = enemy
                    end
                end
            end
        end
        
        -- Calculate yaw to closest enemy
        local target_yaw = 0
        if closest_enemy then
            local ex, ey = entity.get_prop(closest_enemy, 'm_vecOrigin')
            if ex and lx then
                target_yaw = math.deg(math.atan2(ey - ly, ex - lx))
            end
        end
        
        -- Apply yaw offset to target yaw (add 180 to face away from enemy)
        local final_yaw = target_yaw + 180 + yaw_value
        
        -- Normalize yaw to -180..180
        while final_yaw > 180 do final_yaw = final_yaw - 360 end
        while final_yaw < -180 do final_yaw = final_yaw + 360 end
        
        -- Apply directly to cmd for instant response
        cmd.pitch = pitch_value
        cmd.yaw = final_yaw
        
        -- Override antiaim to prevent interference
        reference.antiaim.angles.pitch[1]:override('Custom')
        reference.antiaim.angles.pitch[2]:override(pitch_value)
        reference.antiaim.angles.yaw_base:override('Local view')
        reference.antiaim.angles.yaw[1]:override('Off')
        reference.antiaim.angles.yaw[2]:override(0)
        reference.antiaim.angles.yaw_jitter[1]:override('Off')
        reference.antiaim.angles.body_yaw[1]:override('Off')
        
        return true
    end)
    
    if not success then
        -- Error occurred, return false
        return false
    end
    
    return result
end

-- Apply anti-aim
local function apply_antiaim(cmd)
    local state = get_builder_state_for_aa()
    
    -- Cache state in builder for display (always use actual state)
    builder.state = get_builder_state()
    
    -- Reset pitch to default (will be overridden by defensive or safe_head/static_aa if needed)
    reference.antiaim.angles.pitch[1]:override('Minimal')
    
    -- Если стейт выключен, не применяем антиаимы
    if not state then
        reference.antiaim.angles.yaw[1]:override()
        reference.antiaim.angles.yaw[2]:override()
        reference.antiaim.angles.yaw_jitter[1]:override()
        reference.antiaim.angles.body_yaw[1]:override()
        reference.antiaim.angles.body_yaw[2]:override()
        return
    end
    
    local settings = ui.builder[state]
    
    if not settings then return end
    
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then return end
    
    local tick = globals.tickcount()
    
    -- Get settings
    local yaw = '180'
    local offset = settings.yaw:get()
    local yaw_jitter = settings.yaw_jitter:get()
    local jitter_offset = settings.yaw_jitter_value:get()
    local body_yaw = settings.body_yaw:get()
    local body_yaw_value = settings.body_yaw_value:get()
    local delay_enabled = settings.jitter_delay_enable:get()
    
    -- Get inverted side
    local inverted = inverter(cmd, state)
    
    -- Apply manual yaw
    local manual_offset = manual_yaw.get_offset()
    local manual_active = manual_yaw.get() ~= nil  -- Check if manual is active
    local freestanding_active = ui.freestanding.enable:get()
    
    -- Check if fakeduck is active
    local fakeduck_active = reference.rage.other.fake_duck:get()
    
    -- Try to apply defensive AA first (embertrash logic) - pass manual/freestanding info
    if apply_defensive_aa(cmd, state, manual_active, freestanding_active, manual_offset) then
        return  -- Defensive AA applied, skip normal AA
    end
    
    if manual_offset then
        offset = offset + manual_offset
        -- Force yaw update on manual by disabling jitter
        yaw_jitter = 'Off'
        jitter_offset = 0
        
        -- On fakeduck, apply manual directly to cmd.yaw for instant response
        if fakeduck_active then
            local view_angles = {client.camera_angles()}
            cmd.yaw = view_angles[2] + offset
        end
    end
    
    -- Apply yaw jitter with bounds checking
    local jitter_value = 0
    if yaw_jitter == 'Offset' then
        jitter_value = inverted == 1 and 0 or jitter_offset
    elseif yaw_jitter == 'Center' then
        jitter_value = inverted == 1 and -jitter_offset / 2 or jitter_offset / 2
    elseif yaw_jitter == 'Random' then
        jitter_value = client.random_int(-jitter_offset, jitter_offset)
    end
    
    -- Calculate the final offset with jitter
    local final_offset = offset + jitter_value
    
    -- If final offset exceeds bounds, reduce jitter to fit within bounds
    if final_offset > 180 then
        jitter_value = 180 - offset
    elseif final_offset < -180 then
        jitter_value = -180 - offset
    end
    
    -- Apply the safe jitter value
    offset = offset + jitter_value
    
    -- Apply freestanding (disable if manual is active - manual has priority)
    if ui.freestanding.enable:get() and not manual_active then
        reference.antiaim.angles.freestanding[1]:override(true)
    else
        reference.antiaim.angles.freestanding[1]:override(false)
    end
    
    -- Avoid backstab
    local backstab_active = false
    if ui.avoid_backstab.enable:get() then
        -- Helper function to get eye position
        local function get_eye_position(ent)
            local origin_x, origin_y, origin_z = entity.get_origin(ent)
            local offset_x, offset_y, offset_z = entity.get_prop(ent, 'm_vecViewOffset')
            
            if origin_x == nil or offset_x == nil then
                return nil
            end
            
            return origin_x + offset_x, origin_y + offset_y, origin_z + offset_z
        end
        
        local max_distance = ui.avoid_backstab.distance:get()
        local players = entity.get_players(true)
        for i = 1, #players do
            local enemy = players[i]
            
            if entity.is_alive(enemy) and not entity.is_dormant(enemy) then
                local ex, ey, ez = entity.get_prop(enemy, 'm_vecOrigin')
                local lx, ly, lz = entity.get_prop(me, 'm_vecOrigin')
                
                if ex and lx then
                    local distance = math.sqrt((ex - lx)^2 + (ey - ly)^2)
                    if distance < max_distance then
                        local weapon = entity.get_player_weapon(enemy)
                        if weapon then
                            local weapon_name = entity.get_classname(weapon)
                            if weapon_name == 'CKnife' or weapon_name == 'CKnifeGG' or weapon_name == 'CBayonet' then
                                -- Check line of sight
                                local ex_eye, ey_eye, ez_eye = get_eye_position(enemy)
                                local lx_eye, ly_eye, lz_eye = get_eye_position(me)
                                
                                if ex_eye and lx_eye then
                                    local fraction, entindex_hit = client.trace_line(enemy, ex_eye, ey_eye, ez_eye, lx_eye, ly_eye, lz_eye)
                                    
                                    if entindex_hit == me or fraction == 1 then
                                        -- Calculate angle to enemy
                                        local yaw_to_enemy = math.deg(math.atan2(ey - ly, ex - lx))
                                        
                                        -- Set angles facing away from enemy (180 degrees from enemy)
                                        backstab_active = true
                                        cmd.yaw = yaw_to_enemy + 180
                                        
                                        reference.antiaim.angles.pitch[1]:override('Down')
                                        reference.antiaim.angles.yaw_base:override('Local view')
                                        reference.antiaim.angles.yaw[1]:override('180')
                                        reference.antiaim.angles.yaw[2]:override(0)
                                        reference.antiaim.angles.yaw_jitter[1]:override('Off')
                                        reference.antiaim.angles.yaw_jitter[2]:override(0)
                                        reference.antiaim.angles.body_yaw[1]:override('Static')
                                        reference.antiaim.angles.body_yaw[2]:override(180)
                                        
                                        return  -- Skip normal AA
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Safe head
    if ui.safe_head.enable:get() then
        local conditions = ui.safe_head.conditions:get()
        local should_safe = false
        
        -- Check conditions
        for i = 1, #conditions do
            local condition = conditions[i]
            if condition == 'Standing' and state == 'stand' then
                should_safe = true
            elseif condition == 'Moving' and state == 'run' then
                should_safe = true
            elseif condition == 'Crouch' and (state == 'crouch' or state == 'sneak') then
                should_safe = true
            elseif condition == 'Air' and (state == 'air' or state == 'air+') then
                should_safe = true
            end
        end
        
        if should_safe then
            reference.antiaim.angles.pitch[1]:override('Down')
        end
    end
    
    -- Static Anti-Aim
    local static_aa_options = ui.static_aa:get()
    local should_static_aa = false
    local freestanding_active = ui.freestanding.enable:get()
    
    for i = 1, #static_aa_options do
        local option = static_aa_options[i]
        if option == 'On Manual' and manual_active then
            should_static_aa = true
            break
        elseif option == 'On Freestanding' and freestanding_active and not manual_active then
            should_static_aa = true
            break
        end
    end
    
    if should_static_aa then
        -- Override to static AA: pitch Down, yaw base At targets, yaw 180
        reference.antiaim.angles.pitch[1]:override('Down')
        reference.antiaim.angles.yaw_base:override('At targets')
        reference.antiaim.angles.yaw[1]:override('180')
        
        -- Apply manual offset if active, otherwise 0
        local static_offset = 0
        if manual_offset then
            static_offset = manual_offset
        end
        reference.antiaim.angles.yaw[2]:override(static_offset)
        
        reference.antiaim.angles.yaw_jitter[1]:override('Off')
        reference.antiaim.angles.body_yaw[1]:override('Off')
        reference.antiaim.other.leg_movement:override('Always slide')
        return
    end
    
    -- Calculate angle to closest enemy for at targets behavior
    local lx, ly, lz = entity.get_prop(me, 'm_vecOrigin')
    local enemies = entity.get_players(true)
    local closest_enemy = nil
    local closest_dist = math.huge
    
    for i = 1, #enemies do
        local enemy = enemies[i]
        if entity.is_alive(enemy) then
            local ex, ey, ez = entity.get_prop(enemy, 'm_vecOrigin')
            if ex and lx then
                local dist = math.sqrt((ex - lx)^2 + (ey - ly)^2)
                if dist < closest_dist then
                    closest_dist = dist
                    closest_enemy = enemy
                end
            end
        end
    end
    
    -- Calculate yaw to closest enemy
    local target_yaw = 0
    if closest_enemy then
        local ex, ey = entity.get_prop(closest_enemy, 'm_vecOrigin')
        if ex and lx then
            target_yaw = math.deg(math.atan2(ey - ly, ex - lx))
        end
    end
    
    -- Apply yaw with at targets behavior (180 degrees from enemy + offset)
    local final_yaw = target_yaw + 180 + offset
    
    -- Normalize yaw
    while final_yaw > 180 do final_yaw = final_yaw - 360 end
    while final_yaw < -180 do final_yaw = final_yaw + 360 end
    
    -- Apply directly to cmd
    cmd.pitch = 89  -- Down pitch
    cmd.yaw = final_yaw
    
    -- Apply to game
    reference.antiaim.angles.pitch[1]:override('Minimal')
    reference.antiaim.angles.yaw_base:override('Local view')
    reference.antiaim.angles.yaw[1]:override(yaw)
    reference.antiaim.angles.yaw[2]:override(0)
    reference.antiaim.angles.yaw_jitter[1]:override('Off')
    
    -- Apply body yaw (from aesthetic_skeet logic)
    if body_yaw == 'Off' then
        reference.antiaim.angles.body_yaw[1]:override('Off')
    elseif body_yaw == 'Opposite' then
        reference.antiaim.angles.body_yaw[1]:override('Opposite')
    elseif body_yaw == 'Jitter' then
        -- Convert Jitter to Static with inverted offset
        local offset = body_yaw_value
        if offset == 0 then
            offset = 1
        end
        
        if inverted ~= 1 then
            offset = -offset
        end
        
        reference.antiaim.angles.body_yaw[1]:override('Static')
        reference.antiaim.angles.body_yaw[2]:override(offset)
    elseif body_yaw == 'Static' then
        reference.antiaim.angles.body_yaw[1]:override('Static')
        reference.antiaim.angles.body_yaw[2]:override(inverted * body_yaw_value)
    end
end

client.set_event_callback('setup_command', apply_antiaim)

-- Reset on death
client.set_event_callback('player_death', function(e)
    if not (e.userid and e.attacker) then return end
    local me = entity.get_local_player()
    if me ~= client.userid_to_entindex(e.userid) then return end
    
    builder.side = 1
    builder.delay_tick_counter = 0
end)

-- Reset on map change/disconnect
client.set_event_callback('cs_game_disconnected', function()
    builder.side = 1
    builder.delay_tick_counter = 0
    
    -- Clear all animation states
    for key in pairs(anim_data) do
        anim_data[key] = nil
    end
    
    -- Clear keybind animations
    for key in pairs(keybind_anims) do
        keybind_anims[key] = nil
    end
end)

-- Reset on round start
client.set_event_callback('round_start', function()
    builder.side = 1
    builder.delay_tick_counter = 0
end)

-- ═══════════════════════════════════════════════════════════
-- DEFENSIVE FIX
-- ═══════════════════════════════════════════════════════════

local function vec_3(_x, _y, _z) 
    return { x = _x or 0, y = _y or 0, z = _z or 0 } 
end

local function ticks_to_time()
    return globals.tickinterval() * 16
end 

local function player_will_peek()
    local enemies = entity.get_players(true)
    if not enemies then
        return false
    end
    
    local eye_position = vec_3(client.eye_position())
    local velocity_prop_local = vec_3(entity.get_prop(entity.get_local_player(), "m_vecVelocity"))
    local predicted_eye_position = vec_3(eye_position.x + velocity_prop_local.x * ticks_to_time(predicted), eye_position.y + velocity_prop_local.y * ticks_to_time(predicted), eye_position.z + velocity_prop_local.z * ticks_to_time(predicted))

    for i = 1, #enemies do
        local player = enemies[i]
        
        local velocity_prop = vec_3(entity.get_prop(player, "m_vecVelocity"))
        
        local origin = vec_3(entity.get_prop(player, "m_vecOrigin"))
        local predicted_origin = vec_3(origin.x + velocity_prop.x * ticks_to_time(), origin.y + velocity_prop.y * ticks_to_time(), origin.z + velocity_prop.z * ticks_to_time())
        
        entity.get_prop(player, "m_vecOrigin", predicted_origin)
        
        local head_origin = vec_3(entity.hitbox_position(player, 0))
        local predicted_head_origin = vec_3(head_origin.x + velocity_prop.x * ticks_to_time(), head_origin.y + velocity_prop.y * ticks_to_time(), head_origin.z + velocity_prop.z * ticks_to_time())
        local trace_entity, damage = client.trace_bullet(entity.get_local_player(), predicted_eye_position.x, predicted_eye_position.y, predicted_eye_position.z, predicted_head_origin.x, predicted_head_origin.y, predicted_head_origin.z)
        
        entity.get_prop(player, "m_vecOrigin", origin)
        
        if damage > 0 then
            return true
        end
    end
    
    return false
end

client.set_event_callback("setup_command", function(cmd)
    if not ui.defensive_fix.enable:get() then
        return
    end

    local dt = reference.rage.aimbot.double_tap[1]:get() and reference.rage.aimbot.double_tap[1].hotkey:get()

    if not dt then
        return
    end

    if player_will_peek() then
        cmd.force_defensive = true
    end
end)

-- ═══════════════════════════════════════════════════════════
-- PAINT CALLBACKS
-- ═══════════════════════════════════════════════════════════
client.set_event_callback("paint", function()
    update_keybinds_drag()
    draw_watermark()
    draw_keybinds()
    draw_custom_scope()
    draw_nade_esp()
    draw_crosshair_indicator()
    
    -- Nickname changer
    if ui.nickname_changer.enable:get() then
        local name = ui.nickname_changer.text:get()
        if name and name ~= "" then
            nickname_changer.text = name
            nickname_changer.enabled = true
            set_client_name(name)
        else
            set_client_name(nil)
        end
    else
        nickname_changer.enabled = false
        set_client_name(nil)
    end
end)

-- ═══════════════════════════════════════════════════════════
-- CROSSHAIR INDICATOR
-- ═══════════════════════════════════════════════════════════

local crosshair_alpha = {
    global = 0,
    unique = 0,
    simple = 0,
    states = 0,
    binds = 0
}

local crosshair_drag = {
    dragging = false,
    drag_offset_y = 0,
    mouse_down_prev = false
}

local crosshair_cache = {
    bind_widths = {},
    state_width = 0,
    last_state = ""
}

-- Track bind states for animation
local crosshair_bind_states = {}

local function update_crosshair_drag()
    if not ui.crosshair.enable:get() then return end
    
    local mx, my = ui_api.mouse_position()
    if not mx or not my then return end
    
    local mouse_down = client.key_state(0x01)
    
    local screen_x, screen_y = client.screen_size()
    local center_x = screen_x / 2
    local y = screen_y / 2 + ui.crosshair.y:get()
    
    -- Drag area (around the text)
    local drag_w = 100
    local drag_h = 80
    local drag_x = center_x - drag_w / 2
    local drag_y = y - 10
    
    -- Start dragging
    if mouse_down and not crosshair_drag.mouse_down_prev then
        if mx >= drag_x and mx <= drag_x + drag_w and my >= drag_y and my <= drag_y + drag_h then
            crosshair_drag.dragging = true
            crosshair_drag.drag_offset_y = my - y
        end
    end
    
    -- Update position while dragging
    if crosshair_drag.dragging and mouse_down then
        local new_y = my - crosshair_drag.drag_offset_y
        local center_y = screen_y / 2
        
        -- Calculate offset from center
        local offset = new_y - center_y
        
        -- Clamp to slider bounds (-2160 to 2160)
        offset = math.max(-2160, math.min(offset, 2160))
        
        -- Save to slider
        ui.crosshair.y:set(offset)
    end
    
    -- Stop dragging on release
    if not mouse_down then
        crosshair_drag.dragging = false
    end
    
    crosshair_drag.mouse_down_prev = mouse_down
end

local function get_crosshair_binds()
    local binds = {}
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then 
        -- Reset all bind states when dead
        for key, _ in pairs(crosshair_bind_states) do
            crosshair_bind_states[key] = false
        end
        return binds 
    end
    
    -- Double tap
    local dt_active = false
    if reference.rage.aimbot.double_tap[1] and reference.rage.aimbot.double_tap[1].hotkey then
        if reference.rage.aimbot.double_tap[1].hotkey:get() then
            dt_active = true
            -- Check if DT is in recharge (red) or charged (white)
            local is_charged = not exploits:in_recharge()
            local color = is_charged and {255, 255, 255} or {255, 50, 50}
            table.insert(binds, {name = "dt", display = "dt", color = color, active = true})
        end
    end
    crosshair_bind_states["dt"] = dt_active
    
    -- Hide shots
    local os_active = false
    if reference.antiaim.other.on_shot_anti_aim[1] and reference.antiaim.other.on_shot_anti_aim[1].hotkey then
        if reference.antiaim.other.on_shot_anti_aim[1].hotkey:get() and not exploits:is_doubletap() then
            os_active = true
            table.insert(binds, {name = "os", display = "os", color = {255, 255, 255}, active = true})
        end
    end
    crosshair_bind_states["os"] = os_active
    
    -- Body aim (always white)
    local baim_active = false
    if reference.rage.aimbot.force_body then
        if reference.rage.aimbot.force_body:get() then
            baim_active = true
            table.insert(binds, {name = "baim", display = "baim", color = {255, 255, 255}, active = true})
        end
    end
    crosshair_bind_states["baim"] = baim_active
    
    -- Safe point (always white)
    local safe_active = false
    if reference.rage.aimbot.force_safe then
        if reference.rage.aimbot.force_safe:get() then
            safe_active = true
            table.insert(binds, {name = "safe", display = "safe", color = {255, 255, 255}, active = true})
        end
    end
    crosshair_bind_states["safe"] = safe_active
    
    -- Fake duck
    local fd_active = false
    if reference.rage.other.fake_duck then
        if reference.rage.other.fake_duck:get() then
            fd_active = true
            table.insert(binds, {name = "fd", display = "fd", color = {255, 255, 255}, active = true})
        end
    end
    crosshair_bind_states["fd"] = fd_active
    
    -- Freestanding
    local fs_active = ui.freestanding.enable:get()
    if fs_active then
        table.insert(binds, {name = "fs", display = "fs", color = {255, 255, 255}, active = true})
    end
    crosshair_bind_states["fs"] = fs_active
    
    return binds
end

local function render_bind_text_unique(center_x, y, bind, scope_value, settings_y, alpha_unique, alpha_value, binds_alpha)
    -- Use saved state for animation
    local is_active = crosshair_bind_states[bind.name] or false
    local _bind_alpha = animate('crosshair_bind_alpha_' .. bind.name, is_active and 1 or 0, 6, 0.001, 'ease_out')
    
    if _bind_alpha > 0.01 then
        local measure_binds = renderer.measure_text('cb', bind.display) / 2 + 3
        
        renderer.text(
            center_x + measure_binds * scope_value,
            y,
            bind.color[1], bind.color[2], bind.color[3],
            alpha_unique * alpha_value / 255 * binds_alpha * _bind_alpha,
            'cb', nil, bind.display
        )
    end
    
    return _bind_alpha > 0.01 and 12 or 0
end

local function render_bind_text_simple(center_x, y, bind, scope_value, start_y, alpha_simple, alpha_value, binds_alpha)
    -- Use saved state for animation
    local is_active = crosshair_bind_states[bind.name] or false
    local _bind_alpha = animate('crosshair_bind_alpha_simple_' .. bind.name, is_active and 1 or 0, 6, 0.001, 'ease_out')
    
    if _bind_alpha > 0.01 then
        local measure_binds = renderer.measure_text('c-', bind.display:upper()) / 2 + 3
        
        renderer.text(
            center_x + measure_binds * scope_value,
            y + start_y,
            bind.color[1], bind.color[2], bind.color[3],
            alpha_simple * alpha_value / 255 * binds_alpha * _bind_alpha,
            'c-', nil, bind.display:upper()
        )
    end
    
    local _, h = renderer.measure_text('c-', bind.display:upper())
    return _bind_alpha > 0.01 and (h + 1) or 0
end

local function draw_crosshair_unique(center_x, y, scope_value, alpha_value, alpha_unique, states_alpha, binds_alpha)
    local r, g, b = reference.misc.settings.menu_color:get()
    local measure_name = renderer.measure_text('cb', 'Astrum') / 2 + 3
    
    renderer.text(
        center_x + measure_name * scope_value,
        y + 14,
        r, g, b,
        alpha_unique * alpha_value / 255,
        'cb', nil, 'Astrum'
    )
    
    local settings_add_y = states_alpha > 0 and 12 or 1
    
    if states_alpha > 0 then
        local state = string.lower(builder.state or 'global')
        
        -- Update cache when state changes
        if crosshair_cache.last_state ~= state then
            crosshair_cache.last_state = state
            crosshair_cache.state_width = renderer.measure_text('rb', state) + 1
        end
        
        local measure_state = renderer.measure_text('rb', state) / 2 + 3
        local animated_state = animate('crosshair_state', crosshair_cache.state_width, 7, 1, 'ease_out')
        
        renderer.text(
            center_x + (animated_state / 2) + measure_state * scope_value,
            y + 20,
            255, 255, 255,
            alpha_unique * alpha_value / 255 * states_alpha,
            'rb', animated_state, state
        )
    end
    
    -- Always render all tracked binds (including fading out ones)
    local binds = get_crosshair_binds()
    local height = states_alpha > 0 and 38 or 26  -- Start after state with more spacing
    
    -- Fixed order for binds display
    local bind_order = {"dt", "os", "baim", "safe", "fd", "fs"}
    
    -- Render binds in fixed order
    for _, bind_name in ipairs(bind_order) do
        if crosshair_bind_states[bind_name] ~= nil then
            -- Find bind data from active binds
            local bind_data = nil
            for _, bind in ipairs(binds) do
                if bind.name == bind_name then
                    bind_data = bind
                    break
                end
            end
            
            -- If not active, create minimal bind data for fade-out animation
            if not bind_data then
                bind_data = {name = bind_name, display = bind_name, color = {255, 255, 255}, active = false}
            end
            
            height = height + render_bind_text_unique(
                center_x, y + height, bind_data, scope_value,
                0, alpha_unique, alpha_value, binds_alpha
            )
        end
    end
end

local function draw_crosshair_simple(center_x, y, scope_value, inverted_scope_value, alpha_value, alpha_simple, states_alpha, binds_alpha)
    local r, g, b = reference.misc.settings.menu_color:get()
    local measure_name = renderer.measure_text('c', 'Astrum') / 2 + 3
    
    renderer.text(
        center_x + measure_name * scope_value,
        y + 16,
        r, g, b,
        alpha_simple * alpha_value / 255,
        'c', nil, 'Astrum'
    )
    
    if states_alpha > 0 then
        local state = string.upper(builder.state or 'GLOBAL')
        
        -- Update cache when state changes
        if crosshair_cache.last_state ~= state then
            crosshair_cache.last_state = state
            crosshair_cache.state_width = renderer.measure_text('r-', state) + 1
        end
        
        local measure_state = renderer.measure_text('r-', state) / 2 + 3
        local animated_state = animate('crosshair_state_2', crosshair_cache.state_width, 7, 1, 'ease_out')
        
        renderer.text(
            center_x + (animated_state / 2) + measure_state * scope_value,
            y + 23,
            255, 255, 255,
            alpha_simple * alpha_value / 255 * states_alpha,
            'r-', animated_state, state
        )
    end
    
    -- Always render all tracked binds (including fading out ones)
    local binds = get_crosshair_binds()
    local binds_start_y = states_alpha > 0 and 39 or 28
    local height = 0
    
    -- Fixed order for binds display
    local bind_order = {"dt", "os", "baim", "safe", "fd", "fs"}
    
    -- Render binds in fixed order
    for _, bind_name in ipairs(bind_order) do
        if crosshair_bind_states[bind_name] ~= nil then
            -- Find bind data from active binds
            local bind_data = nil
            for _, bind in ipairs(binds) do
                if bind.name == bind_name then
                    bind_data = bind
                    break
                end
            end
            
            -- If not active, create minimal bind data for fade-out animation
            if not bind_data then
                bind_data = {name = bind_name, display = bind_name, color = {255, 255, 255}, active = false}
            end
            
            local bind_height = render_bind_text_simple(
                center_x, y, bind_data, scope_value,
                binds_start_y + height, alpha_simple, alpha_value, binds_alpha
            )
            height = height + bind_height
        end
    end
end

function draw_crosshair_indicator()
    local me = entity.get_local_player()
    crosshair_alpha.global = animate('crosshair_global', (ui.crosshair.enable:get() and entity.is_alive(me)) and 255 or 0, 10, 0.001, 'ease_out')
    
    if crosshair_alpha.global == 0 then return end
    
    update_crosshair_drag()
    
    local screen_x, screen_y = client.screen_size()
    local center_x = screen_x / 2
    local y = screen_y / 2 + ui.crosshair.y:get()
    
    local is_scoped = entity.get_prop(me, 'm_bIsScoped') == 1
    local scope_value = animate('crosshair_scope', is_scoped and 1 or 0, 10, 0.008, 'ease_out')
    local inverted_scope_value = animate('crosshair_inv_scope', is_scoped and 0 or 1, 10, 0.008, 'ease_out')
    
    local states_enabled = false
    local binds_enabled = false
    for _, v in ipairs(ui.crosshair.select:get()) do
        if v == 'States' then states_enabled = true end
        if v == 'Binds' then binds_enabled = true end
    end
    
    crosshair_alpha.states = animate('crosshair_states', states_enabled and 1 or 0, 10, 0.001, 'ease_out')
    crosshair_alpha.binds = animate('crosshair_binds', binds_enabled and 1 or 0, 10, 0.001, 'ease_out')
    
    local crosshair_type = ui.crosshair.type:get()
    
    crosshair_alpha.unique = animate('crosshair_unique', (crosshair_type == 'Unique') and 255 or 0, 10, 0.001, 'ease_out')
    crosshair_alpha.unique = math.ceil(crosshair_alpha.unique)
    if crosshair_alpha.unique > 0 then
        draw_crosshair_unique(center_x, y, scope_value, crosshair_alpha.global, crosshair_alpha.unique, crosshair_alpha.states, crosshair_alpha.binds)
    end
    
    crosshair_alpha.simple = animate('crosshair_simple', (crosshair_type == 'Simple') and 255 or 0, 10, 0.001, 'ease_out')
    crosshair_alpha.simple = math.ceil(crosshair_alpha.simple)
    if crosshair_alpha.simple > 0 then
        draw_crosshair_simple(center_x, y, scope_value, inverted_scope_value, crosshair_alpha.global, crosshair_alpha.simple, crosshair_alpha.states, crosshair_alpha.binds)
    end
end

-- ═══════════════════════════════════════════════════════════
-- PUI AUTO CONFIG SYSTEM
-- ═══════════════════════════════════════════════════════════

local setup = pui.setup(ui, true)

-- Cleanup on shutdown
client.set_event_callback('shutdown', function()
    -- Reset aspect ratio
    cvar.r_aspectratio:set_int(0)
    
    -- Reset viewmodel
    cvar.viewmodel_fov:set_raw_float(68)
    cvar.viewmodel_offset_x:set_raw_float(2.5)
    cvar.viewmodel_offset_y:set_raw_float(0)
    cvar.viewmodel_offset_z:set_raw_float(-1.5)
    
    -- Reset interpolation
    cvar.cl_interpolate:set_int(1)
    cvar.cl_interp_ratio:set_int(2)
end)

client.log("[ASTRUM] Loaded successfully!")
