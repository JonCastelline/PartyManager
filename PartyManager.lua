--[[
Copyright 2026 Frodobald

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

-- PartyManager Addon for Windower 4
-- Automates invites, trust management, and leveling coordination.

_addon.name = 'PartyManager'
_addon.author = 'Frodobald + Broguypal'
_addon.version = '1.2.0'
_addon.commands = {'partymanager', 'pm'}

require('luau')
local config = require('config')
local packets = require('packets')
local pm_ui = require('partymanager_ui')

-- Default settings - Using strings for trust lists to ensure 100% reliability in persistence
local defaults = {}
defaults.enabled = true
defaults.whitelist = S{}
defaults.password = nil
defaults.max_pcs = 6
defaults.puller = {
    name = nil,
    stop_cmd = '//trust stop',
    start_cmd = '//trust start'
}
defaults.trust_lists = {
    p1 = "", -- 1 PC (solo)
    p2 = "", -- 2 PCs
    p3 = "", -- 3 PCs
    p4 = "", -- 4 PCs
    p5 = ""  -- 5 PCs
}
defaults.sync_mode = 'sender' -- 'sender', 'fixed', 'lowest', or 'none'
defaults.sync_target = nil -- Fixed target name for 'fixed' mode
defaults.reply_msg = "Wait a moment, preparing for invite..."
defaults.auto_level_sync = false
defaults.auto_trust_resummon = false 

local settings = config.load(defaults)

-- State Machine Variables
local states = {
    IDLE = 0,
    REPLYING = 1,
    STOPPING_PULLER = 2,
    WAITING_FOR_COMBAT = 3,
    DISMISSING_TRUSTS = 4,
    INVITING = 5,
    WAITING_FOR_JOIN = 6,
    TARGETING_FOR_SYNC = 7,
    SYNCING = 8,
    SUMMONING_TRUSTS = 9,
    STARTING_PULLER = 10
}

local current_state = states.IDLE
local state_names = {}
for k, v in pairs(states) do state_names[v] = k end

local target_player = nil
local last_action_time = 0
local trust_summon_initial = true
local trust_summon_index = 1
local last_status = 0
local initial_pc_count = 1
local invite_time = 0
local trust_summon_attempt_time = 0
local last_pc_count = 1

-- Party member data tracking
local party_data = {}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

local function clean(s)
    if not s then return '' end
    return s:gsub('%z', ''):trim()
end

local function normalize(name)
    if not name or name == '' then return nil end
    return name:lower():ucfirst()
end

local function get_pc_count()
    local party = windower.ffxi.get_party()
    if not party then return 0 end
    local count = 0
    for i = 0, 5 do
        local m = party['p' .. i]
        if m and m.name and m.name ~= '' then
            if not m.mob or not m.mob.is_npc then
                count = count + 1
            end
        end
    end
    return count
end

local function is_party_in_combat()
    local party = windower.ffxi.get_party()
    if not party then return false end
    
    local party_ids = {}
    for i = 0, 5 do
        local m = party['p' .. i]
        if m and m.id and m.id ~= 0 then
            party_ids[m.id] = m.name
            -- Check if anyone is actively engaged (weapons out)
            if m.mob and m.mob.status == 1 then
                return true
            end
        end
    end
    
    local mob_array = windower.ffxi.get_mob_array()
    for _, mob in pairs(mob_array) do
        -- Only count as combat if mob is alive and claimed by our party
        if mob.hpp > 0 and mob.claim_id ~= 0 and party_ids[mob.claim_id] then
            return true
        end
    end
    return false
end

local function send_puller_cmd(cmd)
    local player = windower.ffxi.get_player()
    if not player then return end
    
    local player_name = player.name:lower()
    local puller_name = settings.puller.name and settings.puller.name:lower() or player_name
    
    if puller_name == player_name then
        windower.send_command(cmd)
    else
        local clean_cmd = cmd:gsub('^/+', '')
        windower.send_command('input /console send ' .. settings.puller.name .. ' ' .. clean_cmd)
    end
end

local function are_trusts_out()
    local party = windower.ffxi.get_party()
    if not party then return false end
    for i = 1, 5 do
        local m = party['p' .. i]
        if m and m.mob and m.mob.is_npc then
            return true
        end
    end
    return false
end

local function is_trust_in_party(name)
    local party = windower.ffxi.get_party()
    if not party then return false end
    local base_name = name:gsub(' %(.+%)$', ''):gsub(' II$', ''):gsub(' III$', ''):lower()
    for i = 1, 5 do
        local m = party['p' .. i]
        if m and m.name then
            local party_member_name = m.name:lower()
            if party_member_name == base_name or party_member_name == name:lower() then
                return true
            end
        end
    end
    return false
end

local function get_trust_list(pc_count)
    local key = 'p' .. tostring(pc_count)
    local str = settings.trust_lists[key]
    if not str or str == "" then return {} end
    
    local list = str:split(',')
    local clean_list = {}
    for _, n in ipairs(list) do
        local name = n:trim()
        if name ~= "" then
            table.insert(clean_list, name)
        end
    end
    return clean_list
end

local function get_lowest_ml_pc()
    local party = windower.ffxi.get_party()
    if not party then return nil end
    
    local lowest_ml = 999
    local lowest_name = nil
    
    for i = 0, 5 do
        local m = party['p' .. i]
        if m and m.name and m.name ~= '' then
            -- If mob info is available, check if it's an NPC (trust).
            if not m.mob or not m.mob.is_npc then
                local data = party_data[m.name]
                if data and data.master_level and data.master_level >= 0 then
                    if data.master_level < lowest_ml then
                        lowest_ml = data.master_level
                        lowest_name = m.name
                    end
                end
            end
        end
    end
    
    return lowest_name
end

-- UI INITIALIZATION
----------------------------------------------------------------------
pm_ui.init(
    settings,
    function()
        return {
            name = state_names[current_state] or 'UNKNOWN',
            target = target_player,
        }
    end,
    get_pc_count,
    function() return windower.ffxi.get_party() end,
    party_data
)

----------------------------------------------------------------------
-- COMMAND HANDLER
----------------------------------------------------------------------

windower.register_event('addon command', function(command, ...)
    command = command and command:lower() or 'status'
    local args = {...}

    if command == 'on' then
        settings.enabled = true
        settings:save()
        windower.add_to_chat(200, 'PartyManager: Enabled.')
        pm_ui.update()
    elseif command == 'off' then
        settings.enabled = false
        settings:save()
        windower.add_to_chat(200, 'PartyManager: Disabled.')
        pm_ui.update()
    elseif command == 'whitelist' then
        local sub = args[1] and args[1]:lower()
        local name = normalize(args[2])
        if sub == 'add' and name then
            settings.whitelist:add(name)
            settings:save()
            windower.add_to_chat(200, 'PartyManager: Added ' .. name .. ' to whitelist.')
            pm_ui.update()
        elseif sub == 'rm' and name then
            settings.whitelist:remove(name)
            settings:save()
            windower.add_to_chat(200, 'PartyManager: Removed ' .. name .. ' from whitelist.')
            pm_ui.update()
        end
    elseif command == 'puller' then
        local sub = args[1] and args[1]:lower()
        local val = args[2]
        if sub == 'name' then
            settings.puller.name = val
            settings:save()
            windower.add_to_chat(200, 'PartyManager: Puller set to ' .. (val or 'Self') .. '.')
            pm_ui.update()
        elseif sub == 'stop' then
            settings.puller.stop_cmd = val
            settings:save()
            windower.add_to_chat(200, 'PartyManager: Puller stop command set to ' .. val .. '.')
            pm_ui.update()
        elseif sub == 'start' then
            settings.puller.start_cmd = val
            settings:save()
            windower.add_to_chat(200, 'PartyManager: Puller start command set to ' .. val .. '.')
            pm_ui.update()
        end
    elseif command == 'sync' then
        local sub = args[1] and args[1]:lower()
        if sub == 'mode' then
            local mode = args[2] and args[2]:lower()
            if mode == 'sender' or mode == 'fixed' or mode == 'lowest' or mode == 'none' then
                settings.sync_mode = mode
                settings:save()
                windower.add_to_chat(200, 'PartyManager: Sync mode set to ' .. mode .. '.')
                pm_ui.update()
            else
                windower.add_to_chat(200, 'PartyManager: Invalid sync mode. Use sender, fixed, lowest, or none.')
            end
        elseif sub == 'target' then
            local target = normalize(args[2])
            if target then
                settings.sync_target = target
                settings:save()
                windower.add_to_chat(200, 'PartyManager: Sync target set to ' .. target .. '.')
                pm_ui.update()
            else
                windower.add_to_chat(200, 'PartyManager: Please specify a sync target name.')
            end
        end
    elseif command == 'limit' then
        local val = tonumber(args[1])
        if val and val >= 1 and val <= 6 then
            settings.max_pcs = val
            settings:save()
            windower.add_to_chat(200, 'PartyManager: Max PCs set to ' .. val .. '.')
            pm_ui.update()
        else
            windower.add_to_chat(200, 'PartyManager: Invalid limit. Use 1-6.')
        end
    elseif command == 'password' then
        local val = args[1]
        settings.password = val
        settings:save()
        windower.add_to_chat(200, 'PartyManager: Password set to ' .. (val or '(none)') .. '.')
        pm_ui.update()
    elseif command == 'trust' then
        local pc_count_num = tonumber(args[1])
        local sub = args[2] and args[2]:lower()
        local name = args[3]
        
        if pc_count_num then
            local key = 'p' .. tostring(pc_count_num)
            local list = get_trust_list(pc_count_num)
            
            if sub == 'add' and name then
                if pc_count_num + #list < 6 then
                    table.insert(list, name)
                    settings.trust_lists[key] = table.concat(list, ',')
                    settings:save()
                    windower.add_to_chat(200, 'PartyManager: Added ' .. name .. ' to trust set for ' .. pc_count_num .. ' PCs.')
                    pm_ui.update()
                else
                    windower.add_to_chat(200, 'PartyManager: Error - Limit reached (Max ' .. (6 - pc_count_num) .. ').')
                end
            elseif sub == 'clear' then
                settings.trust_lists[key] = ""
                settings:save()
                windower.add_to_chat(200, 'PartyManager: Cleared trust set for ' .. pc_count_num .. ' PCs.')
                pm_ui.update()
            elseif sub == 'list' then
                if #list > 0 then
                    windower.add_to_chat(200, 'PartyManager: Trusts for ' .. pc_count_num .. ' PCs: ' .. table.concat(list, ", "))
                else
                    windower.add_to_chat(200, 'PartyManager: No trusts defined for ' .. pc_count_num .. ' PCs.')
                end
            end
        elseif not args[1] or args[1]:lower() == 'list' then
            windower.add_to_chat(200, 'PartyManager: Current Trust Sets:')
            for i = 1, 5 do
                local list = get_trust_list(i)
                if #list > 0 then
                    windower.add_to_chat(200, '  ' .. i .. ' PCs: ' .. table.concat(list, ", "))
                end
            end
        end
    elseif command == 'resummon' then
        local val = args[1] and args[1]:lower()
        if val == 'on' then
            settings.auto_trust_resummon = true
        elseif val == 'off' then
            settings.auto_trust_resummon = false
        end
        settings:save()
        windower.add_to_chat(200, 'PartyManager: Auto Trust Resummon: ' .. (settings.auto_trust_resummon and 'ON' or 'OFF'))
    elseif command == 'reset' then
        current_state = states.IDLE
        target_player = nil
        trust_summon_initial = true
        windower.add_to_chat(200, 'PartyManager: Reset to IDLE.')
    elseif command == 'status' then
        windower.add_to_chat(200, 'PartyManager Status: ' .. (settings.enabled and 'Enabled' or 'Disabled'))
        windower.add_to_chat(200, 'Current State: ' .. (state_names[current_state] or 'UNKNOWN'))
    elseif command == 'ui' then
        pm_ui.toggle('main')
    elseif command == 'ui_refresh' then
        pm_ui.request_refresh()
    elseif command == 'puller_stop_now' then
        send_puller_cmd(settings.puller.stop_cmd)
        windower.add_to_chat(200, 'PartyManager: Puller stop sent.')
    elseif command == 'puller_start_now' then
        send_puller_cmd(settings.puller.start_cmd)
        windower.add_to_chat(200, 'PartyManager: Puller start sent.')
    else
        windower.add_to_chat(200, 'PartyManager: Unknown command. Options: on, off, whitelist add/rm, password, puller name/stop/start, status, reset, trust <pc> add/clear/list.')
    end
end)

local function send_level_sync_packet(target_name)
    -- Use raw injection for 0x077 (Party Settings/Level Sync).
    -- 1-2: Header Placeholder (will be overwritten by inject_outgoing)
    -- 3-4: Filler/Sequence (matches 1B 30 from successful capture)
    local payload = string.char(0, 0, 0x1B, 0x30)
    
    -- 5-20: Name (16 bytes)
    local name_part = target_name:sub(1, 16)
    payload = payload .. name_part .. string.char(0):rep(16 - #name_part)
    
    -- 21-24: Command Tail (0x06 at offset 21)
    payload = payload .. string.char(0, 0x06, 0, 0)
    
    windower.packets.inject_outgoing(0x077, payload)
    return true
end

----------------------------------------------------------------------
-- STATE MACHINE
----------------------------------------------------------------------

windower.register_event('incoming chunk', function(id, data)
    -- Packet 0x0DD: Party Member Update (contains Master Level)
    if id == 0x0DD then
        local p = packets.parse('incoming', data)
        if p and p.Name then
            local name = p.Name
            party_data[name] = party_data[name] or {}
            party_data[name].master_level = p['Master Level']
            party_data[name].main_level = p['Main job level']
            party_data[name].main_job = p['Main job']
            pm_ui.update() -- Refresh UI with new data
        end
    end

    if id == 0x017 and settings.enabled and current_state == states.IDLE then
        local p = packets.parse('incoming', data)
        local mode = p['Mode'] or p['mode']
        if mode == 3 then
            local sender = normalize(clean(p['Sender Name'] or p['sender_name']))
            local msg = clean(p['Message'] or p['message'])
            if settings.whitelist:contains(sender) then
                local has_password = settings.password and settings.password ~= ''
                local password_match = not has_password or msg:lower():contains(settings.password:lower())
                if password_match then
                    local party = windower.ffxi.get_party()
                    local already_in_party = false
                    if party then
                        for i = 1, 5 do
                            local m = party['p' .. i]
                            if m and normalize(m.name) == sender then already_in_party = true break end
                        end
                    end
                    if already_in_party then
                        windower.send_command('input /t ' .. sender .. ' You are already in the party.')
                    elseif get_pc_count() < settings.max_pcs then
                        target_player = sender
                        initial_pc_count = get_pc_count()
                        current_state = states.REPLYING
                    else
                        windower.send_command('input /t ' .. sender .. ' Sorry, the party is full.')
                    end
                end
            end
        end
    end
end)

windower.register_event('prerender', function()
    pm_ui.tick()
    
    local now = os.clock()
    local current_pc_count = get_pc_count()
    
    -- Background monitoring for PC departures
    if settings.enabled then
        if current_pc_count < last_pc_count then
            if settings.auto_trust_resummon and current_state == states.IDLE then
                windower.add_to_chat(200, 'PartyManager: Player left the party. Initiating reconfiguration.')
                target_player = nil -- Ensure we know it's a resummon
                current_state = states.STOPPING_PULLER
                last_action_time = now
                -- Default to skipping cooldown; will be reset if we sync
                invite_time = os.time() - 120
            end
        end
        -- Always update last_pc_count to keep it in sync with the current party state
        last_pc_count = current_pc_count
    end

    if not settings.enabled or current_state == states.IDLE then return end
    if now - last_action_time < 2 then return end
    local player = windower.ffxi.get_player()
    if not player then return end

    if current_state == states.REPLYING then
        if not settings.puller.name or settings.puller.name == '' then
            windower.add_to_chat(200, 'PartyManager: Error - Puller name not set. Resetting.')
            current_state = states.IDLE
            target_player = nil
            return
        end
        windower.add_to_chat(200, 'PartyManager: Replying to ' .. target_player .. '.')
        windower.send_command('input /t ' .. target_player .. ' ' .. settings.reply_msg)
        current_state = states.STOPPING_PULLER
        last_action_time = now

    elseif current_state == states.STOPPING_PULLER then
        windower.add_to_chat(200, 'PartyManager: Stopping puller.')
        send_puller_cmd(settings.puller.stop_cmd)
        current_state = states.WAITING_FOR_COMBAT
        last_action_time = now

    elseif current_state == states.WAITING_FOR_COMBAT then
        windower.add_to_chat(200, 'PartyManager: Waiting for combat..')
        if not is_party_in_combat() then
            windower.add_to_chat(200, 'Not in combat.')
            current_state = states.DISMISSING_TRUSTS
            last_action_time = now
        end

    elseif current_state == states.DISMISSING_TRUSTS then
        if are_trusts_out() then
            windower.add_to_chat(200, 'PartyManager: Dismissing trusts.')
            windower.send_command('input /returntrust all')
            last_action_time = now + 3
        else
            if target_player then
                current_state = states.INVITING
            else
                -- If target_player is nil, it's a resummon from a departure.
                -- Check if we should re-sync.
                if settings.auto_level_sync then
                    current_state = states.TARGETING_FOR_SYNC
                else
                    current_state = states.SUMMONING_TRUSTS
                    windower.add_to_chat(200, 'PartyManager: Summoning trusts.')
                    trust_summon_index = 1
                    trust_summon_attempt_time = 0
                    trust_summon_initial = false
                end
            end
            last_action_time = now
        end

    elseif current_state == states.INVITING then
        windower.add_to_chat(200, 'PartyManager: Sending invite to ' .. target_player .. '.')
        windower.send_command('input /pcmd add ' .. target_player)
        invite_time = os.time()
        current_state = states.WAITING_FOR_JOIN
        last_action_time = now

    elseif current_state == states.WAITING_FOR_JOIN then
        local party = windower.ffxi.get_party()
        local in_party = false
        local in_range = false
        
        for i = 1, 5 do
            local m = party['p' .. i]
            if m and normalize(m.name) == target_player then
                in_party = true
                if m.mob then
                    in_range = true
                end
                break
            end
        end

        if in_range then
            windower.add_to_chat(200, 'PartyManager: '.. target_player .. ' has joined and is in range.')
            if settings.auto_level_sync then
                current_state = states.TARGETING_FOR_SYNC
            else
                current_state = states.SUMMONING_TRUSTS
                windower.add_to_chat(200, 'PartyManager: Auto-sync disabled. Skipping to trusts.')
            end
            last_action_time = now
        else
            local elapsed = os.time() - invite_time
            
            -- Scenario 1: Not in party after 3 minutes
            if not in_party and elapsed > 180 then
                windower.add_to_chat(200, 'PartyManager: ' .. target_player .. ' failed to accept invite within 3 minutes. Giving up.')
                target_player = nil
                current_state = states.SUMMONING_TRUSTS
                last_action_time = now
            
            -- Scenario 2: In party but not in range after 10 minutes
            elseif in_party and elapsed > 600 then
                windower.add_to_chat(200, 'PartyManager: ' .. target_player .. ' failed to arrive within 10 minutes. Kicking and resuming.')
                windower.send_command('input /pcmd kick ' .. target_player)
                target_player = nil
                current_state = states.SUMMONING_TRUSTS
                last_action_time = now + 2
                
            -- Periodic status updates
            elseif math.fmod(elapsed, 60) == 0 and elapsed > 0 then
                local reason = in_party and "arrive" or "accept invite"
                local limit = in_party and 600 or 180
                local remaining = limit - elapsed
                if remaining >= 0 then
                    windower.add_to_chat(200, 'PartyManager: Still waiting for ' .. target_player .. ' to ' .. reason .. ' (' .. remaining .. 's remaining).')
                end
            end
        end

    elseif current_state == states.TARGETING_FOR_SYNC then
        local sync_target_name = nil
        if settings.sync_mode == 'sender' then
            sync_target_name = target_player
        elseif settings.sync_mode == 'fixed' then
            sync_target_name = settings.sync_target
        elseif settings.sync_mode == 'lowest' then
            sync_target_name = get_lowest_ml_pc()
        end

        if sync_target_name then
            windower.add_to_chat(200, 'PartyManager: Targeting ' .. sync_target_name .. ' for level sync.')
            windower.send_command('input /target ' .. sync_target_name)
            current_state = states.SYNCING
            last_action_time = now + 1.5 -- Give it time to target
        else
            windower.add_to_chat(200, 'PartyManager: Sync mode set to none or no valid target found. Skipping sync.')
            current_state = states.SUMMONING_TRUSTS
            last_action_time = now
        end

    elseif current_state == states.SYNCING then
        local sync_target_name = nil
        if settings.sync_mode == 'sender' then
            sync_target_name = target_player
        elseif settings.sync_mode == 'fixed' then
            sync_target_name = settings.sync_target
        elseif settings.sync_mode == 'lowest' then
            sync_target_name = get_lowest_ml_pc()
        end

        if sync_target_name then
            windower.add_to_chat(200, 'PartyManager: Injecting Level Sync packet (0x077) for ' .. sync_target_name .. '.')
            send_level_sync_packet(sync_target_name)
            -- Syncing resets the trust cooldown timer!
            invite_time = os.time()
        else
            windower.add_to_chat(200, 'PartyManager: Sync mode set to none or no valid target found. Skipping sync.')
        end
        
        current_state = states.SUMMONING_TRUSTS
        windower.add_to_chat(200, 'PartyManager: Summoning trusts.')
        trust_summon_index = 1
        trust_summon_attempt_time = 0
        last_action_time = now

    elseif current_state == states.SUMMONING_TRUSTS then
        if player.status == 4 then last_status = 4 return end
        if last_status == 4 then last_status = 0 last_action_time = now + 4 return end

        if trust_summon_initial then
            windower.add_to_chat(200, 'PartyManager: There is a 2 minute cooldown for Trusts after party changes. Starting timer.')
            trust_summon_initial = false
        end
        local elapsed = os.time() - invite_time
        if elapsed < 120 then
            if math.fmod(elapsed, 30) == 0 then
                windower.add_to_chat(200, 'PartyManager: Waiting for trust cooldown (' .. (120 - elapsed) .. 's remaining).')
            end
            last_action_time = now + 5
            return
        end

        local pc_count = get_pc_count()
        local trust_list = get_trust_list(pc_count)
        local slots_available = 6 - pc_count
        
        local current_trusts = 0
        local party = windower.ffxi.get_party()
        for i = 1, 5 do
            local m = party['p' .. i]
            if m and m.mob and m.mob.is_npc then current_trusts = current_trusts + 1 end
        end

        if trust_summon_index <= #trust_list and current_trusts < slots_available then
            local trust_name = trust_list[trust_summon_index]
            if is_trust_in_party(trust_name) then
                trust_summon_index = trust_summon_index + 1
                trust_summon_attempt_time = 0
                last_action_time = now
                return
            end
            if trust_summon_attempt_time == 0 or (os.time() - trust_summon_attempt_time > 8) then
                windower.add_to_chat(200, 'PartyManager: Attempting to summon ' .. trust_name .. ' (PC Count: ' .. pc_count .. ').')
                windower.send_command('input /ma "' .. trust_name .. '" <me>')
                trust_summon_attempt_time = os.time()
                last_action_time = now
            end
        else
            if #trust_list == 0 then windower.add_to_chat(200, 'PartyManager: Warning - No trusts defined for PC count ' .. pc_count .. '.') end
            windower.add_to_chat(200, 'PartyManager: Trust summoning complete.')
            current_state = states.STARTING_PULLER
            trust_summon_initial = true
            last_action_time = now
        end

    elseif current_state == states.STARTING_PULLER then
        windower.add_to_chat(200, 'PartyManager: Starting puller.')
        send_puller_cmd(settings.puller.start_cmd)
        current_state = states.IDLE
        target_player = nil
        last_action_time = now
        windower.add_to_chat(200, 'PartyManager: Process complete.')
    end
end)

windower.register_event('unload', function()
    pm_ui.shutdown()
end)
