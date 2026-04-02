-- partymanager_ui.lua

local texts = require('texts')
local M = {}

---------------------------------------------------------------------------
-- Layout constants
---------------------------------------------------------------------------
local UI = {
    x = 20, y = 100,
    padding = 8, gap = 4, btn_h = 20,
    width = 320,
    header_h = 20,
    font = 'Consolas', font_size = 10,
    picker_width = 360,
    items_per_page = 10,
    picker_btn_h = 18,
    party_row_h = 16,

    panel_bg       = {20, 22, 30, 230},
    panel_border   = {0, 0, 0, 255},
    picker_bg      = {18, 20, 40, 240},
    picker_border  = {0, 0, 0, 255},

    btn_bg         = {50, 50, 55, 210},
    btn_on         = {35, 110, 55, 220},
    btn_off        = {110, 45, 45, 220},
    btn_equip      = {40, 60, 100, 220},
    btn_expand     = {60, 60, 80, 220},
    btn_picker_bg  = {45, 45, 55, 210},
    btn_picker_sel = {40, 100, 55, 220},
    btn_picker_add = {40, 60, 110, 220},
    btn_picker_manual = {60, 50, 80, 220},
    picker_nav     = {50, 50, 65, 210},
    picker_close_c = {110, 45, 45, 220},
    btn_open       = {45, 55, 80, 220},
    btn_warn       = {140, 100, 30, 220},
    btn_sync       = {50, 70, 110, 220},
    btn_puller     = {55, 50, 85, 220},
    btn_password   = {70, 60, 70, 220},

    text_color     = {255, 255, 255, 255},
    muted_color    = {180, 180, 180, 255},
    on_color       = {130, 255, 155, 255},
    off_color      = {255, 140, 140, 255},
    gold_color     = {255, 220, 120, 255},
    title_color    = {120, 200, 255, 255},
    state_color    = {200, 180, 255, 255},
    add_color      = {140, 200, 255, 255},
    manual_color   = {220, 190, 120, 255},
    info_bg        = {35, 35, 50, 200},
    party_color    = {200, 220, 255, 255},
    trust_color    = {160, 180, 220, 255},
    empty_color    = {80, 80, 90, 255},
}
local HOVER_BOOST = 25

---------------------------------------------------------------------------
-- Position persistence
---------------------------------------------------------------------------
local POS_FILE = windower.addon_path .. 'data/pm_ui_pos.lua'
local function load_saved_pos()
    local ok, t = pcall(dofile, POS_FILE)
    if ok and type(t) == 'table' and t.x and t.y then return t.x, t.y end
    return nil, nil
end
local function save_pos(x, y)
    windower.create_dir(windower.addon_path .. 'data')
    local f = io.open(POS_FILE, 'w+')
    if f then f:write(('return { x = %d, y = %d }\n'):format(x, y)); f:close() end
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local ref_settings    -- reference to PartyManager settings table
local ref_state_fn    -- function() returning { name, target }
local ref_pc_count_fn -- function() returning current PC count
local ref_party_fn    -- function() returning windower.ffxi.get_party()

local built = false
local expanded = true
local picker_open = false
local picker_type = nil     -- 'whitelist','trust_p0'..'trust_p4','puller'
local picker_page = 1
local picker_data = {}
local hovering = {}
local dragging, drag_dx, drag_dy = false, 0, 0
local needs_refresh = true

local saved_x, saved_y = load_saved_pos()
local px, py = saved_x or UI.x, saved_y or UI.y

---------------------------------------------------------------------------
-- Prim / text name tables
---------------------------------------------------------------------------
local prims = {
    panel_bg = 'pm_panel_bg',
    panel_border = 'pm_panel_border',
    picker_bg = 'pm_picker_bg',
    picker_border = 'pm_picker_border',
    btns = {},
    btn_borders = {},
}

local BTN_KEYS = {
    'toggle', 'expand',
    'puller_btn', 'sync_mode',
    'password_btn',
    'reset', 'puller_stop', 'puller_start',
    'whitelist_btn',
    'trust_p0', 'trust_p1', 'trust_p2', 'trust_p3', 'trust_p4',
    'auto_sync', 'auto_trust',
    'picker_close', 'picker_prev', 'picker_next',
}
for i = 0, 9 do BTN_KEYS[#BTN_KEYS + 1] = 'pick_' .. i end

for _, key in ipairs(BTN_KEYS) do
    prims.btns[key] = 'pm_btn_' .. key
    prims.btn_borders[key] = 'pm_btnb_' .. key
end

-- Info rows (non-clickable): state + 6 fixed party slots
local INFO_KEYS = {'info_state', 'info_p0', 'info_p1', 'info_p2', 'info_p3', 'info_p4', 'info_p5'}
local info_prims, info_borders, info_txts = {}, {}, {}
for _, key in ipairs(INFO_KEYS) do
    info_prims[key] = 'pm_info_' .. key
    info_borders[key] = 'pm_infob_' .. key
end

local txt_labels = {}
local txt_header = nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function rgba(c) return c[1], c[2], c[3], c[4] end
local function hit(mx, my, rx, ry, rw, rh)
    return mx >= rx and mx <= (rx + rw) and my >= ry and my <= (ry + rh)
end
local function set_prim(n, x, y, w, h, c)
    windower.prim.set_position(n, x, y)
    windower.prim.set_size(n, w, h)
    windower.prim.set_color(n, rgba(c))
end
local function set_vis(n, v) windower.prim.set_visibility(n, v and true or false) end
local function fw() return UI.width - 2 * UI.padding end
local function safe_send(cmd) windower.send_command(cmd) end

local function prefill_chat(text)
    windower.send_command('keyboard_type / ')
    coroutine.schedule(function() windower.chat.set_input(text) end, 0.1)
end

---------------------------------------------------------------------------
-- Build once
---------------------------------------------------------------------------
local function build_once()
    if built then return end
    built = true

    windower.prim.create(prims.panel_bg)
    windower.prim.create(prims.panel_border)
    windower.prim.create(prims.picker_bg)
    windower.prim.create(prims.picker_border)
    set_vis(prims.picker_bg, false)
    set_vis(prims.picker_border, false)

    for _, key in ipairs(BTN_KEYS) do
        windower.prim.create(prims.btns[key])
        windower.prim.create(prims.btn_borders[key])
        set_vis(prims.btns[key], false)
        set_vis(prims.btn_borders[key], false)
        hovering[key] = false
    end

    local function new_txt(sz)
        sz = sz or UI.font_size
        return texts.new('', {
            pos = {x = 0, y = 0},
            text = {font = UI.font, size = sz, alpha = 255, red = 255, green = 255, blue = 255,
                    stroke = {width = 1, alpha = 180, red = 0, green = 0, blue = 0}},
            bg = {alpha = 0},
            flags = {draggable = false},
        })
    end

    txt_header = new_txt()
    txt_header:show()

    for _, key in ipairs(BTN_KEYS) do
        txt_labels[key] = new_txt(key:sub(1, 5) == 'pick_' and 9 or UI.font_size)
    end

    for _, key in ipairs(INFO_KEYS) do
        windower.prim.create(info_prims[key])
        windower.prim.create(info_borders[key])
        set_vis(info_prims[key], false)
        set_vis(info_borders[key], false)
        info_txts[key] = new_txt(key:sub(1, 6) == 'info_p' and 9 or UI.font_size)
    end
end

---------------------------------------------------------------------------
-- Show / hide a single button
---------------------------------------------------------------------------
local function show_btn(key, rc, bg_color, label, label_color)
    if not rc then
        set_vis(prims.btns[key], false)
        set_vis(prims.btn_borders[key], false)
        if txt_labels[key] then txt_labels[key]:hide() end
        return
    end
    local c = bg_color
    if hovering[key] then
        c = {math.min(255, c[1]+HOVER_BOOST), math.min(255, c[2]+HOVER_BOOST),
             math.min(255, c[3]+HOVER_BOOST), c[4]}
    end
    set_prim(prims.btn_borders[key], rc.x - 1, rc.y - 1, rc.w + 2, rc.h + 2, {0, 0, 0, 200})
    set_prim(prims.btns[key], rc.x, rc.y, rc.w, rc.h, c)
    set_vis(prims.btns[key], true)
    set_vis(prims.btn_borders[key], true)
    if txt_labels[key] then
        txt_labels[key]:text(label or '')
        txt_labels[key]:pos(rc.x + 6, rc.y + 2)
        txt_labels[key]:color(rgba(label_color or UI.text_color))
        txt_labels[key]:show()
    end
end

---------------------------------------------------------------------------
-- Show / hide info rows (supports custom height)
---------------------------------------------------------------------------
local function show_info_h(key, iy, h, label, lcolor)
    local w = fw(); local bx = px + UI.padding
    set_prim(info_borders[key], bx - 1, iy - 1, w + 2, h + 2, {0, 0, 0, 150})
    set_prim(info_prims[key], bx, iy, w, h, UI.info_bg)
    set_vis(info_prims[key], true); set_vis(info_borders[key], true)
    info_txts[key]:text(label); info_txts[key]:pos(bx + 6, iy + 1)
    info_txts[key]:color(rgba(lcolor)); info_txts[key]:show()
end
local function show_info(key, iy, label, lcolor)
    show_info_h(key, iy, UI.btn_h, label, lcolor)
end
local function hide_info(key)
    set_vis(info_prims[key], false); set_vis(info_borders[key], false)
    if info_txts[key] then info_txts[key]:hide() end
end

---------------------------------------------------------------------------
-- Party scanning helpers
---------------------------------------------------------------------------

local function get_party_pcs()
    local pcs = {}
    if not ref_party_fn then return pcs end
    local party = ref_party_fn()
    if not party then return pcs end
    for i = 0, 5 do
        local m = party['p' .. i]
        if m and m.name and m.name ~= '' then
            if not m.mob or not m.mob.is_npc then
                pcs[#pcs+1] = m.name
            end
        end
    end
    return pcs
end

local function get_party_trusts()
    local trusts = {}
    if not ref_party_fn then return trusts end
    local party = ref_party_fn()
    if not party then return trusts end
    for i = 1, 5 do
        local m = party['p' .. i]
        if m and m.name and m.name ~= '' then
            if m.mob and m.mob.is_npc then
                trusts[#trusts+1] = m.name
            end
        end
    end
    return trusts
end

-- Get structured party slot data for display
local function get_party_slots()
    local slots = {}
    for i = 0, 5 do
        slots[i] = {name = nil, is_trust = false}
    end
    if not ref_party_fn then return slots end
    local party = ref_party_fn()
    if not party then return slots end
    for i = 0, 5 do
        local m = party['p' .. i]
        if m and m.name and m.name ~= '' then
            local is_npc = m.mob and m.mob.is_npc or false
            slots[i] = {name = m.name, is_trust = is_npc}
        end
    end
    return slots
end

---------------------------------------------------------------------------
-- Picker data builders
---------------------------------------------------------------------------

local function build_puller_data()
    local items = {}
    local current_puller = ref_settings and ref_settings.puller and ref_settings.puller.name or nil
    local pcs = get_party_pcs()
    for _, name in ipairs(pcs) do
        local is_cur = current_puller and name:lower() == current_puller:lower()
        items[#items+1] = {
            type = 'select', name = name,
            is_current = is_cur,
            info = is_cur and 'current' or '',
        }
    end
    return items
end

local function build_whitelist_data()
    local items = {}
    local in_list = {}

    if ref_settings and ref_settings.whitelist then
        for name in ref_settings.whitelist:it() do
            items[#items+1] = {
                type = 'remove', name = name,
                info = '',
            }
            in_list[name:lower()] = true
        end
        table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)
    end

    -- Party PCs not already whitelisted (exclude self)
    local pcs = get_party_pcs()
    local player = windower.ffxi.get_player()
    local self_name = player and player.name or nil
    for _, name in ipairs(pcs) do
        if not in_list[name:lower()] and (not self_name or name:lower() ~= self_name:lower()) then
            items[#items+1] = {
                type = 'add', name = name,
                info = 'in party',
            }
        end
    end

    -- Manual add entry at the bottom
    items[#items+1] = {
        type = 'manual_add', name = '+ Type Name to Add...',
        info = '',
    }

    return items
end

local function build_trust_data(pc_count)
    local items = {}
    local in_list = {}

    if not ref_settings then return items end
    -- For trust set key: p0 = solo (0 extra PCs besides you, 5 trust slots)
    -- p1 = 1 PC in party (you), p2 = 2 PCs, etc.
    local key = 'p' .. tostring(pc_count)
    local str = ref_settings.trust_lists and ref_settings.trust_lists[key] or ""

    if str ~= "" then
        local idx = 0
        for n in str:gmatch('[^,]+') do
            local name = n:match('^%s*(.-)%s*$')
            if name ~= "" then
                idx = idx + 1
                items[#items+1] = {
                    type = 'remove', name = name,
                    info = ('#%d'):format(idx),
                }
                in_list[name:lower()] = true
            end
        end
    end

    -- Party trusts not already in this list
    local trusts = get_party_trusts()
    local max_trusts
    if pc_count == 0 then
        max_trusts = 5  -- solo: 5 trust slots
    else
        max_trusts = 5 - pc_count  -- e.g. 2 PCs = 3 trust slots
    end
    local current_count = #items
    for _, name in ipairs(trusts) do
        if not in_list[name:lower()] and current_count < max_trusts then
            items[#items+1] = {
                type = 'add', name = name,
                info = 'in party',
            }
        end
    end
    return items
end

---------------------------------------------------------------------------
-- Refresh picker data
---------------------------------------------------------------------------
local function refresh_picker_data()
    picker_data = {}
    if picker_type == 'puller' then
        picker_data = build_puller_data()
    elseif picker_type == 'whitelist' then
        picker_data = build_whitelist_data()
    elseif picker_type and picker_type:sub(1, 7) == 'trust_p' then
        local pc = tonumber(picker_type:sub(8))
        if pc then
            picker_data = build_trust_data(pc)
        end
    end
end

---------------------------------------------------------------------------
-- Open / close picker
---------------------------------------------------------------------------
local function open_picker(ptype)
    picker_type = ptype; picker_page = 1; picker_open = true
    refresh_picker_data()
end
local function close_picker()
    picker_open = false; picker_type = nil; picker_data = {}
end

---------------------------------------------------------------------------
-- Compute main panel rects
---------------------------------------------------------------------------
local function compute_rects()
    local r = {}
    local bx = px + UI.padding
    local w = fw()
    local cur_y = py + UI.padding + UI.header_h + UI.gap

    -- Row 1: [Toggle ON/OFF] [+/-]
    local tw = math.floor(w * 0.78)
    local ew = w - tw - UI.gap
    r['toggle'] = {x = bx, y = cur_y, w = tw, h = UI.btn_h}
    r['expand'] = {x = bx + tw + UI.gap, y = cur_y, w = ew, h = UI.btn_h}
    cur_y = cur_y + UI.btn_h + UI.gap

    if expanded then
        -- Info: State
        r['_info_state'] = cur_y; cur_y = cur_y + UI.btn_h + 2

        -- Party slots (6 fixed rows, smaller height)
        for i = 0, 5 do
            r['_info_p' .. i] = cur_y; cur_y = cur_y + UI.party_row_h + 1
        end
        cur_y = cur_y + UI.gap

        -- Row: [Puller: Name] [Sync: mode]
        local hw = math.floor((w - UI.gap) / 2)
        r['puller_btn'] = {x = bx, y = cur_y, w = hw, h = UI.btn_h}
        r['sync_mode']  = {x = bx + hw + UI.gap, y = cur_y, w = hw, h = UI.btn_h}
        cur_y = cur_y + UI.btn_h + UI.gap

        -- Row: [Password: ****]
        r['password_btn'] = {x = bx, y = cur_y, w = w, h = UI.btn_h}
        cur_y = cur_y + UI.btn_h + UI.gap

        -- Row: [Reset] [Puller Stop] [Puller Start]
        local tw3 = math.floor((w - 2 * UI.gap) / 3)
        r['reset']        = {x = bx, y = cur_y, w = tw3, h = UI.btn_h}
        r['puller_stop']  = {x = bx + tw3 + UI.gap, y = cur_y, w = tw3, h = UI.btn_h}
        r['puller_start'] = {x = bx + 2*(tw3 + UI.gap), y = cur_y, w = tw3, h = UI.btn_h}
        cur_y = cur_y + UI.btn_h + UI.gap

        -- Row: [Whitelist (N)]
        r['whitelist_btn'] = {x = bx, y = cur_y, w = w, h = UI.btn_h}
        cur_y = cur_y + UI.btn_h + UI.gap

        -- Row: [0PC] [1PC] [2PC] [3PC] [4PC]
        local qw = math.floor((w - 4 * UI.gap) / 5)
        for i = 0, 4 do
            r['trust_p' .. i] = {x = bx + i*(qw + UI.gap), y = cur_y, w = qw, h = UI.btn_h}
        end
        cur_y = cur_y + UI.btn_h + UI.gap

        -- Row: [AutoSync: OFF] [AutoTrust: OFF]
        r['auto_sync']  = {x = bx, y = cur_y, w = hw, h = UI.btn_h}
        r['auto_trust'] = {x = bx + hw + UI.gap, y = cur_y, w = hw, h = UI.btn_h}
        cur_y = cur_y + UI.btn_h + UI.gap
    else
        -- Collapsed
        r['_info_state'] = cur_y; cur_y = cur_y + UI.btn_h + 2
    end

    return r, cur_y
end

---------------------------------------------------------------------------
-- Compute picker rects
---------------------------------------------------------------------------
local function compute_picker_rects()
    if not picker_open then return {} end
    local r = {}
    local total_pages = math.max(1, math.ceil(#picker_data / UI.items_per_page))
    local ppx = px + UI.width + 4
    local ppy = py
    local pbx = ppx + UI.padding
    local pfw = UI.picker_width - 2 * UI.padding
    local cur_y = ppy + UI.padding + UI.header_h + UI.gap

    r['picker_close'] = {x = ppx + UI.picker_width - UI.padding - 40, y = ppy + UI.padding, w = 40, h = UI.header_h}

    local start_idx = (picker_page - 1) * UI.items_per_page + 1
    local end_idx = math.min(start_idx + UI.items_per_page - 1, #picker_data)
    for i = start_idx, end_idx do
        local slot = i - start_idx
        r['pick_' .. slot] = {x = pbx, y = cur_y, w = pfw, h = UI.picker_btn_h}
        cur_y = cur_y + UI.picker_btn_h + 2
    end

    cur_y = cur_y + UI.gap
    local nw = math.floor((pfw - UI.gap) / 2)
    r['picker_prev'] = {x = pbx, y = cur_y, w = nw, h = UI.btn_h}
    r['picker_next'] = {x = pbx + nw + UI.gap, y = cur_y, w = nw, h = UI.btn_h}
    r._ppx = ppx; r._ppy = ppy; r._bottom = cur_y + UI.btn_h + UI.padding
    return r
end

---------------------------------------------------------------------------
-- Full layout pass
---------------------------------------------------------------------------
local function apply_layout()
    if not built then return end
    local rects, panel_bottom = compute_rects()

    local is_enabled = ref_settings and ref_settings.enabled or false
    local state_info = ref_state_fn and ref_state_fn() or {name = 'IDLE', target = nil}
    local pc_count = ref_pc_count_fn and ref_pc_count_fn() or 0

    -- Panel background
    local panel_h = (panel_bottom - py) + UI.padding
    set_prim(prims.panel_border, px - 1, py - 1, UI.width + 2, panel_h + 2, UI.panel_border)
    set_prim(prims.panel_bg, px, py, UI.width, panel_h, UI.panel_bg)
    set_vis(prims.panel_bg, true)
    set_vis(prims.panel_border, true)

    -- Title
    txt_header:pos(px + UI.padding, py + UI.padding)
    txt_header:text('PartyManager')
    txt_header:color(rgba(UI.title_color))

    -- Toggle
    show_btn('toggle', rects['toggle'],
        is_enabled and UI.btn_on or UI.btn_off,
        is_enabled and 'PM: ON' or 'PM: OFF',
        is_enabled and UI.on_color or UI.off_color)

    -- Expand
    show_btn('expand', rects['expand'], UI.btn_expand,
        expanded and '[-]' or '[+]', UI.text_color)

    if expanded then
        -- Info: State
        local state_label = 'State: ' .. (state_info.name or 'IDLE')
        if state_info.target then state_label = state_label .. ' (' .. state_info.target .. ')' end
        local state_c = state_info.name == 'IDLE' and UI.muted_color or UI.state_color
        show_info('info_state', rects['_info_state'], state_label, state_c)

        -- Party slots (6 fixed rows)
        local slots = get_party_slots()
        for i = 0, 5 do
            local slot = slots[i]
            local skey = 'info_p' .. i
            local sy = rects['_info_p' .. i]
            if slot.name then
                local prefix = (i == 0) and 'P0' or ('P' .. i)
                local suffix = slot.is_trust and ' (Trust)' or ''
                local label = ('%s: %s%s'):format(prefix, slot.name, suffix)
                local color = slot.is_trust and UI.trust_color or UI.party_color
                show_info_h(skey, sy, UI.party_row_h, label, color)
            else
                show_info_h(skey, sy, UI.party_row_h, ('P%d: ---'):format(i), UI.empty_color)
            end
        end

        -- Puller button
        local puller_name = ref_settings and ref_settings.puller and ref_settings.puller.name or nil
        local puller_label = puller_name and ('Puller: %s'):format(puller_name) or 'Puller: (set)'
        local is_puller_open = picker_open and picker_type == 'puller'
        show_btn('puller_btn', rects['puller_btn'],
            is_puller_open and UI.btn_open or UI.btn_puller,
            puller_label,
            puller_name and UI.on_color or UI.muted_color)

        -- Sync mode button
        local sync_mode = ref_settings and ref_settings.sync_mode or 'sender'
        show_btn('sync_mode', rects['sync_mode'], UI.btn_sync,
            'Sync: ' .. sync_mode, UI.text_color)

        -- Password button
        local pw = ref_settings and ref_settings.password
        local pw_display = (pw and pw ~= '') and '****' or '(none)'
        show_btn('password_btn', rects['password_btn'], UI.btn_password,
            'Password: ' .. pw_display .. '  (click to set)', UI.muted_color)

        -- Reset / Puller Stop / Puller Start
        local is_idle = (state_info.name == 'IDLE')
        show_btn('reset', rects['reset'],
            is_idle and UI.btn_bg or UI.btn_warn,
            'Reset', is_idle and UI.muted_color or UI.off_color)

        show_btn('puller_stop', rects['puller_stop'], UI.btn_off,
            'Pull Stop', UI.off_color)
        show_btn('puller_start', rects['puller_start'], UI.btn_on,
            'Pull Start', UI.on_color)

        -- Whitelist button
        local wl_count = 0
        if ref_settings and ref_settings.whitelist then
            for _ in ref_settings.whitelist:it() do wl_count = wl_count + 1 end
        end
        local is_wl_open = picker_open and picker_type == 'whitelist'
        show_btn('whitelist_btn', rects['whitelist_btn'],
            is_wl_open and UI.btn_open or UI.btn_equip,
            ('Whitelist (%d)'):format(wl_count), wl_count > 0 and UI.on_color or UI.text_color)

        -- Trust list buttons 0PC..4PC
        for i = 0, 4 do
            local tkey = 'trust_p' .. i
            local pkey = 'p' .. tostring(i)
            local str = ref_settings and ref_settings.trust_lists and ref_settings.trust_lists[pkey] or ""
            local count = 0
            if str ~= "" then
                for _ in str:gmatch('[^,]+') do count = count + 1 end
            end
            local is_active = picker_open and picker_type == tkey
            local label
            if i == 0 then
                label = ('Solo(%d)'):format(count)
            else
                label = ('%dPC(%d)'):format(i, count)
            end
            show_btn(tkey, rects[tkey],
                is_active and UI.btn_open or UI.btn_equip,
                label,
                count > 0 and UI.on_color or UI.muted_color)
        end

        -- Future toggles
        local auto_sync_on = ref_settings and ref_settings.auto_level_sync or false
        show_btn('auto_sync', rects['auto_sync'],
            auto_sync_on and UI.btn_on or UI.btn_bg,
            auto_sync_on and 'AutoSync: ON' or 'AutoSync: OFF',
            auto_sync_on and UI.on_color or UI.muted_color)

        local auto_trust_on = ref_settings and ref_settings.auto_trust_resummon or false
        show_btn('auto_trust', rects['auto_trust'],
            auto_trust_on and UI.btn_on or UI.btn_bg,
            auto_trust_on and 'AutoTrust: ON' or 'AutoTrust: OFF',
            auto_trust_on and UI.on_color or UI.muted_color)
    else
        -- Collapsed
        local state_label = 'State: ' .. (state_info.name or 'IDLE')
        if state_info.target then state_label = state_label .. ' > ' .. state_info.target end
        show_info('info_state', rects['_info_state'], state_label, UI.muted_color)

        -- Hide party slots
        for i = 0, 5 do hide_info('info_p' .. i) end

        for _, key in ipairs({'puller_btn','sync_mode','password_btn',
            'reset','puller_stop','puller_start',
            'whitelist_btn','trust_p0','trust_p1','trust_p2','trust_p3','trust_p4',
            'auto_sync','auto_trust'}) do
            show_btn(key, nil)
        end
        set_vis(prims.picker_bg, false); set_vis(prims.picker_border, false)
        show_btn('picker_close', nil); show_btn('picker_prev', nil); show_btn('picker_next', nil)
        for s = 0, 9 do show_btn('pick_' .. s, nil) end
        return
    end

    -- ==== PICKER PANEL ====
    local prects = compute_picker_rects()
    if picker_open and prects._ppx then
        local ppx_v = prects._ppx
        local ppy_v = prects._ppy
        local ph = prects._bottom - ppy_v
        local total_pages = math.max(1, math.ceil(#picker_data / UI.items_per_page))

        set_prim(prims.picker_border, ppx_v - 1, ppy_v - 1, UI.picker_width + 2, ph + 2, UI.picker_border)
        set_prim(prims.picker_bg, ppx_v, ppy_v, UI.picker_width, ph, UI.picker_bg)
        set_vis(prims.picker_bg, true); set_vis(prims.picker_border, true)

        show_btn('picker_close', prects['picker_close'], UI.picker_close_c, '[X]', UI.text_color)

        local start_idx = (picker_page - 1) * UI.items_per_page + 1
        for slot = 0, 9 do
            local key = 'pick_' .. slot
            local idx = start_idx + slot
            local rc = prects[key]
            if rc and idx <= #picker_data then
                local item = picker_data[idx]
                local bg, label, lcolor
                local info_str = item.info and item.info ~= '' and ('  [%s]'):format(item.info) or ''

                if item.type == 'select' then
                    local marker = item.is_current and '>> ' or '   '
                    label = marker .. item.name .. info_str
                    bg = item.is_current and UI.btn_picker_sel or UI.btn_picker_bg
                    lcolor = item.is_current and UI.on_color or UI.text_color
                elseif item.type == 'remove' then
                    label = '[x] ' .. item.name .. info_str
                    bg = UI.btn_picker_sel
                    lcolor = UI.on_color
                elseif item.type == 'add' then
                    label = '[+] ' .. item.name .. info_str
                    bg = UI.btn_picker_add
                    lcolor = UI.add_color
                elseif item.type == 'manual_add' then
                    label = item.name
                    bg = UI.btn_picker_manual
                    lcolor = UI.manual_color
                else
                    label = item.name .. info_str
                    bg = UI.btn_picker_bg
                    lcolor = UI.text_color
                end
                show_btn(key, rc, bg, label, lcolor)
            else
                show_btn(key, nil)
            end
        end

        local page_str = ('Page %d/%d'):format(picker_page, total_pages)
        show_btn('picker_prev', prects['picker_prev'], UI.picker_nav,
            picker_page > 1 and '< Prev' or '', UI.muted_color)
        show_btn('picker_next', prects['picker_next'], UI.picker_nav,
            picker_page < total_pages and ('Next >   %s'):format(page_str) or page_str, UI.muted_color)
    else
        set_vis(prims.picker_bg, false); set_vis(prims.picker_border, false)
        show_btn('picker_close', nil)
        show_btn('picker_prev', nil); show_btn('picker_next', nil)
        for s = 0, 9 do show_btn('pick_' .. s, nil) end
    end
end

---------------------------------------------------------------------------
-- Click handlers
---------------------------------------------------------------------------
local function handle_click(key)
    if key == 'toggle' then
        local enabled = ref_settings and ref_settings.enabled
        if enabled then safe_send('pm off') else safe_send('pm on') end

    elseif key == 'expand' then
        expanded = not expanded
        if not expanded then close_picker() end

    elseif key == 'puller_btn' then
        if picker_open and picker_type == 'puller' then close_picker()
        else open_picker('puller') end

    elseif key == 'sync_mode' then
        local current = ref_settings and ref_settings.sync_mode or 'sender'
        local next_mode
        if current == 'sender' then next_mode = 'self'
        elseif current == 'self' then next_mode = 'none'
        else next_mode = 'sender'
        end
        if ref_settings then
            ref_settings.sync_mode = next_mode
            ref_settings:save()
            windower.add_to_chat(200, 'PartyManager: Sync mode set to ' .. next_mode .. '.')
        end

    elseif key == 'password_btn' then
        prefill_chat('//pm password ')

    elseif key == 'reset' then
        safe_send('pm reset')

    elseif key == 'puller_stop' then
        safe_send('pm puller_stop_now')

    elseif key == 'puller_start' then
        safe_send('pm puller_start_now')

    elseif key == 'whitelist_btn' then
        if picker_open and picker_type == 'whitelist' then close_picker()
        else open_picker('whitelist') end

    elseif key:sub(1, 7) == 'trust_p' and key:len() == 8 then
        local ptype = key
        if picker_open and picker_type == ptype then close_picker()
        else open_picker(ptype) end

    elseif key == 'auto_sync' then
        if ref_settings then
            ref_settings.auto_level_sync = not (ref_settings.auto_level_sync or false)
            ref_settings:save()
            local s = ref_settings.auto_level_sync and 'ON' or 'OFF'
            windower.add_to_chat(200, 'PartyManager: Auto Level Sync (lowest) ' .. s .. '. (Feature coming soon)')
        end

    elseif key == 'auto_trust' then
        if ref_settings then
            ref_settings.auto_trust_resummon = not (ref_settings.auto_trust_resummon or false)
            ref_settings:save()
            local s = ref_settings.auto_trust_resummon and 'ON' or 'OFF'
            windower.add_to_chat(200, 'PartyManager: Auto Trust Resummon ' .. s .. '. (Feature coming soon)')
        end

    elseif key == 'picker_close' then
        close_picker()

    elseif key == 'picker_prev' then
        if picker_page > 1 then picker_page = picker_page - 1 end

    elseif key == 'picker_next' then
        local total = math.max(1, math.ceil(#picker_data / UI.items_per_page))
        if picker_page < total then picker_page = picker_page + 1 end

    elseif key:sub(1, 5) == 'pick_' then
        local slot = tonumber(key:sub(6))
        local idx = (picker_page - 1) * UI.items_per_page + 1 + slot
        local item = picker_data[idx]
        if not item then return end

        -- === PULLER PICKER ===
        if picker_type == 'puller' then
            if ref_settings then
                ref_settings.puller.name = item.name
                ref_settings:save()
                windower.add_to_chat(200, 'PartyManager: Puller set to ' .. item.name .. '.')
            end
            refresh_picker_data()

        -- === WHITELIST PICKER ===
        elseif picker_type == 'whitelist' then
            if item.type == 'remove' then
                safe_send('pm whitelist rm ' .. item.name)
                coroutine.schedule(function() refresh_picker_data(); needs_refresh = true end, 0.6)
            elseif item.type == 'add' then
                safe_send('pm whitelist add ' .. item.name)
                coroutine.schedule(function() refresh_picker_data(); needs_refresh = true end, 0.6)
            elseif item.type == 'manual_add' then
                prefill_chat('//pm whitelist add ')
            end

        -- === TRUST PICKER ===
        elseif picker_type and picker_type:sub(1, 7) == 'trust_p' then
            local pc = tonumber(picker_type:sub(8))
            if not pc or not ref_settings then return end
            local pkey = 'p' .. tostring(pc)

            if item.type == 'remove' then
                local str = ref_settings.trust_lists[pkey] or ""
                local list = {}
                for n in str:gmatch('[^,]+') do
                    local name = n:match('^%s*(.-)%s*$')
                    if name ~= "" then list[#list+1] = name end
                end
                local new_list = {}
                local removed = false
                for _, n in ipairs(list) do
                    if not removed and n:lower() == item.name:lower() then
                        removed = true
                    else
                        new_list[#new_list+1] = n
                    end
                end
                ref_settings.trust_lists[pkey] = table.concat(new_list, ',')
                ref_settings:save()
                windower.add_to_chat(200, ('PartyManager: Removed %s from %s trust set.'):format(item.name, pc == 0 and 'Solo' or pc .. 'PC'))

            elseif item.type == 'add' then
                local str = ref_settings.trust_lists[pkey] or ""
                local list = {}
                if str ~= "" then
                    for n in str:gmatch('[^,]+') do
                        local name = n:match('^%s*(.-)%s*$')
                        if name ~= "" then list[#list+1] = name end
                    end
                end
                local max_trusts = pc == 0 and 5 or (5 - pc)
                if #list < max_trusts then
                    list[#list+1] = item.name
                    ref_settings.trust_lists[pkey] = table.concat(list, ',')
                    ref_settings:save()
                    windower.add_to_chat(200, ('PartyManager: Added %s to %s trust set.'):format(item.name, pc == 0 and 'Solo' or pc .. 'PC'))
                else
                    windower.add_to_chat(200, ('PartyManager: %s trust set full (max %d).'):format(pc == 0 and 'Solo' or pc .. 'PC', max_trusts))
                end
            end
            refresh_picker_data()
        end
    end
    needs_refresh = true
end

---------------------------------------------------------------------------
-- Mouse
---------------------------------------------------------------------------
windower.register_event('mouse', function(mtype, x, y, delta, blocked)
    if blocked or not built then return false end

    local main_rects = compute_rects()
    local prects = compute_picker_rects()
    local all = {}
    for _, key in ipairs(BTN_KEYS) do
        if main_rects[key] then all[key] = main_rects[key] end
        if prects[key] then all[key] = prects[key] end
    end

    local hdr = {x = px, y = py, w = UI.width, h = UI.header_h + UI.padding}
    local _, pb = compute_rects()
    local panel_h = (pb - py) + UI.padding

    if mtype == 0 then
        if dragging then px = x - drag_dx; py = y - drag_dy; apply_layout(); return true end
        local over_any = false
        for key, rc in pairs(all) do
            if type(rc) == 'table' and rc.w then
                local over = hit(x, y, rc.x, rc.y, rc.w, rc.h)
                if hovering[key] ~= over then hovering[key] = over; needs_refresh = true end
                if over then over_any = true end
            end
        end
        if hit(x, y, hdr.x, hdr.y, hdr.w, hdr.h) then over_any = true end
        if hit(x, y, px, py, UI.width, panel_h) then over_any = true end
        if picker_open and prects._ppx then
            if hit(x, y, prects._ppx, prects._ppy, UI.picker_width, prects._bottom - prects._ppy) then over_any = true end
        end
        return over_any
    end

    if mtype == 1 then
        for _, key in ipairs(BTN_KEYS) do
            local rc = all[key]
            if rc and rc.w and hit(x, y, rc.x, rc.y, rc.w, rc.h) then return true end
        end
        if hit(x, y, hdr.x, hdr.y, hdr.w, hdr.h) then
            dragging = true; drag_dx = x - px; drag_dy = y - py; return true
        end
        if hit(x, y, px, py, UI.width, panel_h) then return true end
        if picker_open and prects._ppx then
            if hit(x, y, prects._ppx, prects._ppy, UI.picker_width, prects._bottom - prects._ppy) then return true end
        end
        return false
    end

    if mtype == 2 then
        if dragging then dragging = false; save_pos(px, py); return true end
        for _, key in ipairs(BTN_KEYS) do
            local rc = all[key]
            if rc and rc.w and hit(x, y, rc.x, rc.y, rc.w, rc.h) then
                handle_click(key); return true
            end
        end
        if hit(x, y, px, py, UI.width, panel_h) then return true end
        if picker_open and prects._ppx then
            if hit(x, y, prects._ppx, prects._ppy, UI.picker_width, prects._bottom - prects._ppy) then return true end
        end
        if picker_open then close_picker(); needs_refresh = true end
        return false
    end

    return false
end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
local function destroy_all()
    pcall(function()
        if txt_header then txt_header:hide() end
        for _, t in pairs(txt_labels) do t:hide() end
        for _, t in pairs(info_txts) do t:hide() end
        windower.prim.delete(prims.panel_bg)
        windower.prim.delete(prims.panel_border)
        windower.prim.delete(prims.picker_bg)
        windower.prim.delete(prims.picker_border)
        for _, key in ipairs(BTN_KEYS) do
            windower.prim.delete(prims.btns[key])
            windower.prim.delete(prims.btn_borders[key])
        end
        for _, key in ipairs(INFO_KEYS) do
            windower.prim.delete(info_prims[key])
            windower.prim.delete(info_borders[key])
        end
    end)
    built = false
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function M.init(settings_ref, state_fn, pc_count_fn, party_fn)
    ref_settings    = settings_ref
    ref_state_fn    = state_fn
    ref_pc_count_fn = pc_count_fn
    ref_party_fn    = party_fn
end

function M.request_refresh()
    needs_refresh = true
end

function M.tick()
    build_once()
    if needs_refresh then
        needs_refresh = false
        apply_layout()
    end
end

function M.update()
    needs_refresh = true
    if built then apply_layout() end
end

function M.toggle(panel_name)
    if panel_name == 'main' then
        expanded = not expanded
        if not expanded then close_picker() end
    elseif panel_name == 'whitelist' or panel_name == 'puller' then
        if picker_open and picker_type == panel_name then close_picker()
        else open_picker(panel_name) end
    elseif panel_name and panel_name:sub(1, 7) == 'trust_p' then
        if picker_open and picker_type == panel_name then close_picker()
        else open_picker(panel_name) end
    end
    needs_refresh = true
end

function M.show()
    build_once()
    needs_refresh = true
    apply_layout()
end

function M.hide()
    if built then
        set_vis(prims.panel_bg, false)
        set_vis(prims.panel_border, false)
        set_vis(prims.picker_bg, false)
        set_vis(prims.picker_border, false)
        if txt_header then txt_header:hide() end
        for _, key in ipairs(BTN_KEYS) do show_btn(key, nil) end
        for _, key in ipairs(INFO_KEYS) do hide_info(key) end
    end
end

function M.shutdown()
    destroy_all()
end

return M
