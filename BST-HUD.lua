--[[
Copyright © 2025, Nalfey of Asura
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of bst_hud nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Nalfey BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

_addon.name = 'BST-HUD'
_addon.author = 'Nalfey (pet art by Eiffel, Falkirk, and Nalfey)'
_addon.version = '1.1' 
_addon.command = 'bsthud'

config = require('config')
texts = require('texts')
res = require 'resources'
packets = require('packets')
images = require('images')

-- BST HUD Settings
display_settings = {
    pos = {
        x = -250,
        y = 500
    },
    text = {
        font = 'Arial',
        size = 11,
        stroke = {
            width = 2,
            alpha = 255,
            red = 0,
            green = 38,
            blue = 62
        }
    },
    flags = {
        right = true,
        bold = false,
        draggable = true,
        italic = false
    },
    bg = {
        visible = false,
        alpha = 128
    },
    padding = 10
}

-- Initialize global variables
showabilities = true
debug_mode = false
equip_reduction = 0
charges = 0
next_ready_recast = 0
expect_ready_move = false
pet = nil
abilitylist = nil
merits = 0
jobpoints = 0
self = nil
petname = nil
mypet_idx = nil
current_hp = 0
max_hp = 0
current_mp = 0
max_mp = 0
current_hp_percent = 0
current_mp_percent = 0
current_tp_percent = 0
petactive = false
verbose = false
superverbose = false
timercountdown = 0
pet_image = nil

-- BST ability IDs
local CALL_BEAST_ID = 81
local BESTIAL_LOYALTY_ID = 83

-- Load settings
settings = config.load(display_settings)
bst_display = texts.new('${value}', settings)
bst_display:pos(settings.pos.x, settings.pos.y)
bst_display:text('')  -- Initialize with empty text
bst_display:hide()    -- Start hidden
bst_display:update()  -- Force initial update

-- Initialize path to images directory
local images_path = windower.addon_path..'images/'

-- Bar settings
local bar_settings = {
    width = 100,    -- Keep original width for calculations
    height = 10,     -- Keep original height for calculations
    bar_scale = {   -- Add scaling factors for the colored bars
        width = 1,  -- Make colored bar 96% of texture width
        height = 1   -- Make colored bar half the texture height
    },
    spacing = 30,  
    offset = {
        x = -15,
        y = 38   
    },
    numbers_offset = {
        x = 0,
        y = 20
    },
    anim_speed = 0.1,
    bg_path = images_path..'BarBG.png',
    fg_path = images_path..'BarFG.png',
    glow_mid_path = images_path..'BarGlowMid.png',
    glow_sides_path = images_path..'BarGlowSides.png',
    hp = {
        bg_color = '#FF9597A0',  -- Reduced alpha for background
        fg_color = '#FF9597FF',
        glow_color = '#FF959730'  -- Very transparent for subtle glow
    },
    tp = {
        bg_color = '#8EB4F9A0',  -- Reduced alpha for background
        fg_color = '#8EB4F9FF',
        glow_color = '#8EB4F930'  -- Very transparent for subtle glow
    },
    priority = {
        background = 0,
        foreground = 1,
        glow = 2
    }
}

-- Bar objects
local bars = {
    hp = {
        bg = nil,
        fg = nil,
        glow_mid = nil,
        glow_sides = nil,
        current_value = 0,
        target_value = 0,
        width = 0  -- Add initial width
    },
    tp = {
        bg = nil,
        fg = nil,
        glow_mid = nil,
        glow_sides = nil,
        current_value = 0,
        target_value = 0,
        width = 0  -- Add initial width
    }
}

-- State tracking for display updates
local display_state = {
    last_state = nil,
    last_text = nil,
    pet_was_present = false  -- Track if we had a pet before
}

-- Add at the top with other global variables
local stored_tp = 0
local last_valid_tp_time = 0

-- Function to convert hex color to RGB values
function hex_to_rgb(hex)
    local r = tonumber(hex:sub(2,3), 16)
    local g = tonumber(hex:sub(4,5), 16)
    local b = tonumber(hex:sub(6,7), 16)
    local a = tonumber(hex:sub(8,9), 16)
    return r, g, b, a
end

-- Function to create color tag
function create_color_tag(current, max, type)
    -- Handle nil values
    current = current or 0
    max = max or 1
    
    if type == 'hp' then
        local percent = current / max * 100
        if percent > 75 then
            return '\\cs(240,255,255)' -- Normal color
        elseif percent > 50 then
            return '\\cs(243,243,124)' -- Yellow
        elseif percent > 25 then
            return '\\cs(248,186,128)' -- Orange
        else
            return '\\cs(252,129,130)' -- Red
        end
    elseif type == 'tp' then
        if current and current >= 1000 then
            return '\\cs(80,180,250)' -- TP full color
        else
            return '\\cs(240,255,255)' -- Normal color
        end
    end
    return '\\cs(240,255,255)' -- Default to normal color
end

-- Function to create a bar
function create_bar(bar, x, y, is_hp)
    -- Initialize values first
    bar.current_value = 0
    bar.target_value = 0
    bar.width = 0  -- Start with zero width
    
    -- Calculate correct position for right-aligned text
    local screen_width = windower.get_windower_settings().ui_x_res
    local actual_x = x
    
    if settings.flags.right then
        actual_x = screen_width + x - bar_settings.width * 2 - bar_settings.spacing
        if not is_hp then
            actual_x = actual_x + bar_settings.width + bar_settings.spacing
        end
    else
        if not is_hp then
            actual_x = actual_x + bar_settings.width + bar_settings.spacing
        end
    end

    if settings.flags.right then
        actual_x = actual_x + bar_settings.offset.x
    end
    
    local bar_colors = is_hp and bar_settings.hp or bar_settings.tp
    
    -- Background (bottom layer)
    bar.bg = images.new({
        texture = {path = bar_settings.bg_path, fit = true},
        pos = {x = actual_x, y = y},
        size = {width = 100, height = 8},  -- Full size for texture
        draggable = false,
        priority = bar_settings.priority.background
    })
    bar.bg:show()
    
    -- Foreground (above background)
    bar.fg = images.new({
        color = {alpha = 255},
        pos = {x = actual_x + 4, y = y + 4},  -- Offset to center the smaller bar
        size = {width = 0, height = 8},
        draggable = false,
        priority = bar_settings.priority.foreground
    })
    local r, g, b, a = hex_to_rgb(bar_colors.fg_color)
    bar.fg:color(r, g, b, a)
    bar.fg:show()
    
    -- Glow sides (above foreground)
    bar.glow_sides = images.new({
        color = {alpha = 0},  -- Start invisible
        texture = {path = bar_settings.glow_sides_path, fit = true},
        pos = {x = actual_x - 3, y = y - (32 - bar_settings.height) / 2},
        size = {width = 0, height = 32},
        draggable = false,
        priority = bar_settings.priority.glow
    })
    r, g, b, a = hex_to_rgb(bar_colors.glow_color)
    bar.glow_sides:color(r, g, b, a)
    bar.glow_sides:show()
    
    -- Glow middle (top layer)
    bar.glow_mid = images.new({
        color = {alpha = 0},  -- Start invisible
        texture = {path = bar_settings.glow_mid_path, fit = true},
        pos = {x = actual_x, y = y - (32 - bar_settings.height) / 2},
        size = {width = 0, height = 32},
        draggable = false,
        priority = bar_settings.priority.glow
    })
    r, g, b, a = hex_to_rgb(bar_colors.glow_color)
    bar.glow_mid:color(r, g, b, a)
    bar.glow_mid:show()
    
    -- Force initial visibility
    set_bar_visible(bar, true)
end

-- Function to update bar value with animation
function update_bar(bar, current, max)
    if not bar then return end
    
    -- Calculate target percentage (0 to 1)
    local target_percent
    if max == 100 then
        -- For HP bar, current is already a percentage
        target_percent = math.min(100, math.max(0, current)) / 100
    else
        -- For TP bar, calculate percentage
        target_percent = math.min(100, math.max(0, (current or 0) / (max or 1) * 100)) / 100
    end
    
    bar.target_value = target_percent
    
    -- If no current_value exists, initialize it
    if not bar.current_value then
        bar.current_value = target_percent  -- Initialize to target value
    end
    
    local diff = bar.target_value - bar.current_value
    if math.abs(diff) > 0.001 then
        bar.current_value = bar.current_value + (diff * bar_settings.anim_speed)
        
        -- Calculate new width using full bar width
        local new_width = math.floor(bar_settings.width * bar.current_value)
        bar.width = new_width
        
        -- Update foreground width
        if bar.fg then
            bar.fg:size(new_width, 3)  -- Keep height at 3
        end
        
        -- Update glow effects
        if math.abs(target_percent - bar.current_value) > 0.01 then
            local glow_width = bar_settings.width * math.abs(target_percent - bar.current_value)
            
            if bar.glow_mid then
                bar.glow_mid:size(glow_width, 32)
                bar.glow_mid:alpha(48)
            end
            
            if bar.glow_sides then
                bar.glow_sides:alpha(48)
            end
        else
            if bar.glow_mid then bar.glow_mid:alpha(0) end
            if bar.glow_sides then bar.glow_sides:alpha(0) end
        end
    end
end

-- Function to show/hide bar
function set_bar_visible(bar, visible)
    if not bar then return end
    if bar.bg then 
        bar.bg:visible(visible)
        if visible then
            bar.bg:show()
        end
    end
    if bar.fg then 
        bar.fg:visible(visible)
        if visible then
            bar.fg:show()
        end
    end
    if bar.glow_mid then 
        bar.glow_mid:visible(visible)
        if visible then
            bar.glow_mid:show()
        end
    end
    if bar.glow_sides then 
        bar.glow_sides:visible(visible)
        if visible then
            bar.glow_sides:show()
        end
    end
end

-- Function to update display
function update_display()
    if verbose then
        windower.add_to_chat(8, 'Update Display - Pet: ' .. (pet and 'exists' or 'nil') .. 
            ', PetActive: ' .. tostring(petactive) .. 
            ', PetName: ' .. (petname or 'nil') ..
            ', TP: ' .. tostring(current_tp_percent))
    end

    -- Always try to get pet if we don't have one
    if not pet then
        pet = windower.ffxi.get_mob_by_target('pet')
    end

    if pet then
        local list = ""
        
        -- Pet name with proper formatting and extra spacing
        list = list .. (petname or pet.name) .. '\n\n'
        
        -- Add HP and TP values with proper spacing and colors
        local hp_color = create_color_tag(current_hp_percent, 100, 'hp')
        local tp_color = create_color_tag(current_tp_percent or 0, 1000, 'tp')
        
        -- Format HP and TP values with fixed spacing
        -- Use %4d to ensure TP always takes up 4 spaces (handles 0 to 3000)
        local hp_text = hp_color .. string.format("%15s%4s", "", current_hp_percent .. "%") .. "\\cr"
        local tp_text = tp_color .. string.format("%15s%4d", "", current_tp_percent or 0) .. "\\cr"
        
        -- Add values with spacing between HP and TP (increased middle padding)
        list = list .. string.format("%-25s%10s%-25s", hp_text, "", tp_text) .. '\n'
        
        -- Ready Moves section with extra spacing
        list = list .. '\n' .. "Ready Moves - Charges: " .. charges .. " - " .. next_ready_recast .. "\n"
        
        -- Add Ready moves with proper coloring
        if type(abilitylist) == 'table' then
            for key,ability in pairs(abilitylist) do
                if type(ability) == 'number' and res.job_abilities[ability] then
                    local ability_data = res.job_abilities[ability]
                    if ability_data.type == 'Monster' and ability_data.targets and ability_data.targets.Self then
                        local ability_charges = ability_data.mp_cost or 0
                        if charges >= ability_charges then 
                            list = list .. '\\cs(0,255,0)' .. ability_data.en .. '\\cr\n'
                        else
                            list = list .. '\\cs(150,150,150)' .. ability_data.en .. '\\cr\n'
                        end
                    end
                end
            end
        end
        
        -- Update HP bar
        if bars.hp then
            update_bar(bars.hp, current_hp_percent, 100)
            set_bar_visible(bars.hp, true)
        end
        
        -- Update TP bar only if we have a valid TP value
        if bars.tp and current_tp_percent then
            update_bar(bars.tp, current_tp_percent, 1000)
            set_bar_visible(bars.tp, true)
        end
        
        bst_display:text(list)
        bst_display:visible(true)
        display_state.pet_was_present = true
    else
        -- Hide bars when no pet
        set_bar_visible(bars.hp, false)
        set_bar_visible(bars.tp, false)
        
        if verbose and display_state.pet_was_present then
            windower.add_to_chat(8, 'Pet despawned, hiding display')
            display_state.last_state = nil
            display_state.last_text = nil
            display_state.pet_was_present = false
        end
        bst_display:visible(false)
        if pet_image then
            pet_image:destroy()
            pet_image = nil
        end
    end
end

-- Event Handlers
windower.register_event('time change', function()
    if timercountdown == 0 then
        return
    elseif petactive then
        if superverbose then windower.add_to_chat(8, 'SCAN: Pet appeared between scans!') end
        timercountdown = 0
    else
        timercountdown = timercountdown - 1
        if update_pet('scan') == true then
            if superverbose then windower.add_to_chat(8, 'SCAN: Found a pet!') end
            timercountdown = 0
            make_visible()
            update_display()
        elseif timercountdown == 0 then
            if superverbose then windower.add_to_chat(8, 'SCAN: No pet found in 5 ticks') end
        end
    end
end)

windower.register_event('prerender', function()
    if self then
        if self.main_job == 'BST' then
            duration = windower.ffxi.get_ability_recasts()[102]
            if duration then 
                chargebase = (30 - merits - jobpoints - equip_reduction)
                charges = math.floor(((chargebase * 3) - duration) / chargebase)
                next_ready_recast = math.floor(math.fmod(duration,chargebase))
                update_display()
            end
        end
    end
end)

windower.register_event('outgoing chunk',function(id,data)
    if id == 0x01A then
        local packet = packets.parse('outgoing', data)
        local ability_used = packet.Param
        local category = packet.Category
        if res.job_abilities[ability_used] then 
            local ability_name = res.job_abilities[ability_used].en
            -- Check for Ready moves
            if res.job_abilities[ability_used].type == 'Monster' and category == 9 then
                expect_ready_move = true
            end
            -- Check for BST summon abilities by name
            if (ability_name == "Call Beast" or ability_name == "Bestial Loyalty") and category == 9 then
                if verbose then 
                    windower.add_to_chat(8, 'BST pet summoning ability detected: ' .. ability_name)
                end
                -- Reset pet tracking and start scanning
                petactive = false
                mypet_idx = nil
                timercountdown = 15
                -- Force a check after a short delay to allow for animation
                coroutine.schedule(function()
                    local pet = windower.ffxi.get_mob_by_target('pet')
                    if pet then
                        make_visible()
                        update_display()
                    end
                end, 3)
            end
        end
    end
end)

windower.register_event('incoming chunk',function(id,data)
    -- Add specific pet spawn packet detection
    if id == 0x0E then
        local packet = packets.parse('incoming', data)
        local player = windower.ffxi.get_player()
        if packet and player and packet['Owner Index'] == player.index then
            if verbose then windower.add_to_chat(8, 'Pet spawn detected') end
            coroutine.schedule(function()
                local pet = windower.ffxi.get_mob_by_target('pet')
                if pet then
                    make_visible()
                    update_display()
                end
            end, 1)
        end
    end
    
    -- Keep existing packet handlers
    if id == 0x119 and expect_ready_move then
        local gear = windower.ffxi.get_items()
        local mainweapon = res.items[windower.ffxi.get_items(gear.equipment.main_bag, gear.equipment.main).id].en
        local subweapon = res.items[windower.ffxi.get_items(gear.equipment.sub_bag, gear.equipment.sub).id].en
        local legs = res.items[windower.ffxi.get_items(gear.equipment.legs_bag, gear.equipment.legs).id].en
    
        equip_reduction = 0
        if mainweapon == "Charmer's Merlin" or subweapon == "Charmer's Merlin" then 
            equip_reduction = equip_reduction + 5
        end
        if legs == "Desultor Tassets" then
            equip_reduction = equip_reduction + 5
        end
        expect_ready_move = false
    end

    -- PetTP packet handling
    if id == 0x44 then
        if data:unpack('C', 0x05) == 0x12 then    -- puppet update
            local new_current_hp, new_max_hp, new_current_mp, new_max_mp = data:unpack('HHHH', 0x069)
            if (not petactive) or (petname == nil) or (petname == "") or (new_current_hp ~= current_hp) or (new_max_hp ~= max_hp) or (new_current_mp ~= current_mp) or (new_max_mp ~= max_mp) then
                if petactive or new_current_hp > 0 then  -- Check if pet is active or has HP
                    local new_petname = data:unpack('z', 0x59)
                    if petname == nil or petname == "" or petname ~= new_petname then
                        petname = new_petname
                        if not petactive then
                            make_visible()
                        end
                        update_pet_image()
                    end
                    current_hp = new_current_hp
                    max_hp = new_max_hp
                    current_mp = new_current_mp
                    max_mp = new_max_mp
                    if max_hp ~= 0 then
                        current_hp_percent = math.floor(100*current_hp/max_hp)
                    else
                        current_hp_percent = 0
                    end
                    if max_mp ~= 0 then
                        current_mp_percent = math.floor(100*current_mp/max_mp)
                    else
                        current_mp_percent = 0
                    end
                    update_display()
                end
            end
        end
    elseif id == 0x67 or id == 0x068 then
        local packet = packets.parse('incoming', data)
        local msg_type = packet['Message Type']
        local msg_len = packet['Message Length']
        pet_idx = packet['Pet Index']
        own_idx = packet['Owner Index']

        if (msg_type == 0x04) and id == 0x067 then
            pet_idx, own_idx = own_idx, pet_idx
        end

        if (msg_type == 0x04) then
            if (pet_idx == 0) then
                if verbose then windower.add_to_chat(8, 'Pet died/despawned') end
                make_invisible()
            else
                local newpet = false
                if not petactive then
                    petactive = true
                    if update_pet('0x67-0x*4',pet_idx,own_idx) == true then
                        make_visible()
                        newpet = true
                    else
                        if superverbose then windower.add_to_chat(8, 'Pet not found') end
                        make_invisible()
                    end
                end
                local new_hp_percent = packet['Current HP%']
                local new_mp_percent = packet['Current MP%']
                local new_tp_percent = packet['Pet TP']
                
                -- Only update TP if it's a valid new value and different from current
                if new_tp_percent and new_tp_percent >= 0 and new_tp_percent ~= current_tp_percent then
                    if verbose then 
                        windower.add_to_chat(8, 'TP Update - Old: ' .. tostring(current_tp_percent) .. ' New: ' .. tostring(new_tp_percent))
                    end
                    current_tp_percent = new_tp_percent
                end
                
                if newpet or (new_hp_percent ~= current_hp_percent) or (new_mp_percent ~= current_mp_percent) then
                    current_hp_percent = new_hp_percent
                    current_mp_percent = new_mp_percent
                    update_display()
                end
            end
        elseif not petactive and (msg_type == 0x03) and (own_idx == windower.ffxi.get_player().index) then
            if update_pet('0x67-0x03',pet_idx,own_idx) == true then
                make_visible()
                update_display()
            else
                timercountdown = 5
                if superverbose then windower.add_to_chat(8, 'Starting to scan for a pet...') end
            end
        end
    end
end)

windower.register_event('addon command', function(command)
    if command == 'save' then
        save_settings()
    elseif command == 'reset' then
        settings.pos.x = display_settings.pos.x
        settings.pos.y = display_settings.pos.y
        bst_display:pos(settings.pos.x, settings.pos.y)
        save_settings()
        windower.add_to_chat(207, 'BST_HUD: Position reset to default.')
    elseif command == 'pos' then
        windower.add_to_chat(207, string.format('Current position: x=%d, y=%d', bst_display:pos_x(), bst_display:pos_y()))
    elseif command == 'jp' then
        for i,v in pairs(self.merits) do
            print (i,v)
        end
    elseif command == 'debug' then
        debug_mode = not debug_mode
        update_display()
        windower.add_to_chat(207, 'BST_HUD Debug Mode: ' .. (debug_mode and 'ON' or 'OFF'))
    elseif command == 'verbose' then
        verbose = not verbose
        windower.add_to_chat(121,'BST_HUD: Verbose Mode flipped! - '..tostring(verbose))
    elseif command == 'superverbose' then
        superverbose = not superverbose
        windower.add_to_chat(121,'BST_HUD: SuperVerbose Mode flipped! - '..tostring(superverbose))
    elseif command == 'help' then
        print('   :::   BST_HUD ('.._addon.version..')   :::')
        print('Commands:')
        print(' 1. debug        --- Toggle debug mode')
        print(' 2. verbose      --- Toggle verbose mode')
        print(' 3. superverbose --- Toggle super verbose mode')
        print(' 4. save         --- Save current settings')
        print(' 5. reset        --- Reset position to default')
        print(' 6. pos          --- Show current position')
        print(' 7. jp           --- Show job point information')
        print(' 8. help         --- Show this help menu')
    end
end)

windower.register_event('load', function()
    if windower.ffxi.get_player() then 
        coroutine.sleep(2) 
        self = windower.ffxi.get_player()
        if self.job_points.bst.jp_spent >= 100 then
            jobpoints = 5
        else
            jobpoints = 0
        end    
    end
    if self.merits.sic_recast == 5 then
        merits = 10
    elseif self.merits.sic_recast == 4 then
        merits = 8
    elseif self.merits.sic_recast == 3 then
        merits = 6
    elseif self.merits.sic_recast == 2 then
        merits = 4
    elseif self.merits.sic_recast == 1 then
        merits = 2
    else
        merits = 0
    end

    -- Initialize PetTP
    if superverbose then
        windower.add_to_chat(8, 'Player index: '..windower.ffxi.get_player().index)
        if windower.ffxi.get_mob_by_target('pet') then
            windower.add_to_chat(8, 'Pet index: '..windower.ffxi.get_mob_by_target('pet').index)
        end
    end

    -- Create bars at the correct position
    local text_x = bst_display:pos_x()
    local text_y = bst_display:pos_y()
    
    -- Create both bars at the same Y position
    create_bar(bars.hp, text_x, text_y + bar_settings.offset.y, true)  -- HP bar on left
    create_bar(bars.tp, text_x, text_y + bar_settings.offset.y, false) -- TP bar on right

    -- Check for pet and get initial values
    if windower.ffxi.get_player() then
        local pet = windower.ffxi.get_mob_by_target('pet')
        if pet then
            -- Get initial TP value directly from pet data
            current_tp_percent = pet.tp
            if verbose then 
                windower.add_to_chat(8, 'Initial pet TP: ' .. tostring(current_tp_percent))
            end
            if update_pet('load') then
                make_visible()
                update_display()
            end
        end
    end
end)

windower.register_event('login', function()
    coroutine.sleep(2)
    self = windower.ffxi.get_player()
    if self.job_points.bst.jp_spent >= 100 then
        jobpoints = 5
    else
        jobpoints = 0
    end    
    if self.merits.sic_recast == 5 then
        merits = 10
    elseif self.merits.sic_recast == 4 then
        merits = 8
    elseif self.merits.sic_recast == 3 then
        merits = 6
    elseif self.merits.sic_recast == 2 then
        merits = 4
    elseif self.merits.sic_recast == 1 then
        merits = 2
    else
        merits = 0
    end

    -- PetTP login handling
    mypet_idx = nil
    if update_pet('login') == true then
        if verbose then windower.add_to_chat(8, 'Found pet after logging in...') end
        make_visible()
        update_display()
    elseif petactive then
        make_invisible()
        if verbose then windower.add_to_chat(8, 'Lost pet after logging in...') end
    end
end)

windower.register_event('zone change', function()
    coroutine.sleep(2)
    bst_display:pos(settings.pos.x, settings.pos.y)
    self = windower.ffxi.get_player()
    if self.job_points.bst.jp_spent >= 100 then
        jobpoints = 5
    else
        jobpoints = 0
    end    
    if self.merits.sic_recast == 5 then
        merits = 10
    elseif self.merits.sic_recast == 4 then
        merits = 8
    elseif self.merits.sic_recast == 3 then
        merits = 6
    elseif self.merits.sic_recast == 2 then
        merits = 4
    elseif self.merits.sic_recast == 1 then
        merits = 2
    else
        merits = 0
    end

    -- PetTP zone change handling
    mypet_idx = nil
    if update_pet('zone') == true then
        if verbose then windower.add_to_chat(8, 'Found pet after zoning...') end
        make_visible()
        update_display()
    elseif petactive then
        make_invisible()
        if verbose then windower.add_to_chat(8, 'Lost pet after zoning...') end
    end
end)

windower.register_event('job change', function()
    coroutine.sleep(2)
    self = windower.ffxi.get_player()
    if self.job_points.bst.jp_spent >= 100 then
        jobpoints = 5
    else
        jobpoints = 0
    end    
    if self.merits.sic_recast == 5 then
        merits = 10
    elseif self.merits.sic_recast == 4 then
        merits = 8
    elseif self.merits.sic_recast == 3 then
        merits = 6
    elseif self.merits.sic_recast == 2 then
        merits = 4
    elseif self.merits.sic_recast == 1 then
        merits = 2
    else
        merits = 0
    end

    -- PetTP job change handling
    make_invisible()
end)

-- Function to validate pet
function valid_pet(source,pet_idx_in, own_idx_in)
    local player = windower.ffxi.get_player()
    if superverbose then windower.add_to_chat(8, 'valid_pet('..source..'): petactive: '..tostring(petactive)..', mypet_idx: '..(mypet_idx or 'nil')..', pet_idx_in: '..(pet_idx_in or 'nil')..', own_idx_in: '..(own_idx_in or 'nil')..', player.index '..player.index) end
    if player.vitals.hp == 0 then
        if superverbose then windower.add_to_chat(8, 'valid_pet() : false : Player is dead') end
        timercountdown = 0
        return
    end

    if petactive then 
        if mypet_idx then
            if not pet_idx_in or mypet_idx == pet_idx_in then
                if superverbose then windower.add_to_chat(8, 'valid_pet() : true : using mypet_idx') end
                return mypet_idx
            end
        elseif own_idx_in and player.index == own_idx_in then
            if superverbose then windower.add_to_chat(8, 'valid_pet() : true : using pet_idx_in') end
            mypet_idx = pet_idx_in
            return mypet_idx
        end
    end
    
    local pet = windower.ffxi.get_mob_by_target('pet')    
    if pet_idx_in and pet and pet_idx_in ~= pet.index then
        if superverbose then windower.add_to_chat(8, 'valid_pet() : false : pet.index ~= pet_idx_in '..pet.index..' vs. '..pet_idx_in) end
        return
    elseif pet_idx_in and player.mob and player.mob.pet_index and pet_idx_in ~= player.mob.pet_index then
        if superverbose then windower.add_to_chat(8, 'valid_pet() : false : player.mob.pet_index ~= pet_idx_in '..player.mob.pet_index..' vs. '..pet_idx_in) end
        return
    elseif pet then
        if superverbose then windower.add_to_chat(8, 'valid_pet() : true : Using pet.index') end
        mypet_idx = pet.index
        return mypet_idx
    elseif player.mob and player.mob.pet_index then
        if superverbose then windower.add_to_chat(8, 'valid_pet() : true : Using player.mob.pet_index') end
        mypet_idx = player.mob.pet_index    
        return mypet_idx
    end
    if superverbose then windower.add_to_chat(8, 'valid_pet() : false : No pet found') end
    return
end

-- Function to update pet information
function update_pet(source,pet_idx_in,own_idx_in)
    pet_idx = valid_pet(source,pet_idx_in,own_idx_in)

    if pet_idx == nil then
        if superverbose then windower.add_to_chat(8, 'update_pet() : false : pet_idx == nil, pet_idx_in: '..(pet_idx_in or 'nil')..', own_idx_in: '..(own_idx_in or 'nil')) end
        return false
    end

    local pet_table = windower.ffxi.get_mob_by_index(pet_idx)
    if pet_table == nil then
        if petactive then
            if superverbose then windower.add_to_chat(8, 'update_pet() : true : pet_table == nil, pet_idx: '..(pet_idx or 'nil')..', '..(own_idx_in or 'nil')) end
            return true
        end
        if superverbose then windower.add_to_chat(8, 'update_pet() : false: pet_table == nil, pet_idx: '..(pet_idx or 'nil')..', '..(own_idx_in or 'nil')) end
        make_invisible()
        return false
    end

    local old_petname = petname
    petname = pet_table['name']
    if old_petname ~= petname then
        update_pet_image()
    end
    
    if superverbose then windower.add_to_chat(8, 'update_pet() : Updating PetName: '..petname) end
    current_hp_percent = pet_table['hpp']
    
    -- Update TP only if we have a valid new value
    if pet_table['tp'] and pet_table['tp'] >= 0 then
        local new_tp = pet_table['tp']
        local current_time = os.time()
        
        -- Only accept the new TP value if:
        -- 1. It's higher than stored TP (pet gained TP)
        -- 2. More than 3 seconds have passed since last valid TP update
        -- 3. Stored TP is 0 (initial state)
        if new_tp > stored_tp or 
           (current_time - last_valid_tp_time) > 3 or 
           stored_tp == 0 then
            
            if verbose then 
                windower.add_to_chat(8, string.format('TP Update - Old: %d, New: %d, Time since last: %d', 
                    stored_tp, new_tp, current_time - last_valid_tp_time))
            end
            
            stored_tp = new_tp
            current_tp_percent = new_tp
            last_valid_tp_time = current_time
        else
            -- Keep using stored TP
            current_tp_percent = stored_tp
            if verbose then 
                windower.add_to_chat(8, string.format('Keeping stored TP: %d (rejected new value: %d)', 
                    stored_tp, new_tp))
            end
        end
    end
    
    if not petactive and current_hp_percent == 0 then
        if superverbose then windower.add_to_chat(8, 'update_pet() : Picked up a likely dead pet') end
        make_invisible()
        return false
    end
    
    pet = pet_table
    if superverbose then 
        windower.add_to_chat(8, string.format('update_pet() : true : Picked up a pet: %s, hp%%: %d, tp: %d, pet_idx: %d',
            petname, current_hp_percent, current_tp_percent, pet_idx))
    end
    return true
end

-- Add spell cast handler
windower.register_event('action', function(act)
    if act.actor_id ~= windower.ffxi.get_player().id then return end
    
    if act.category == 6 then  -- Job Ability
        local ability = act.param
        if res.job_abilities[ability] then
            local ability_name = res.job_abilities[ability].en
            -- Reset TP when pet is released or dies
            if ability_name == 'Release' then
                reset_stored_tp()
            end
        end
    end
end)

-- Function to make display visible
function make_visible()
    -- Set pet variable first
    pet = windower.ffxi.get_mob_by_target('pet')
    if pet then
        petactive = true
        petname = pet.name
        -- Add nil checks for all pet stats
        current_hp = pet.hp or 0
        current_hp_percent = pet.hpp or 0
        max_hp = (pet.hpp and pet.hpp > 0 and pet.hp) and math.floor(pet.hp * 100 / pet.hpp) or 0
        
        -- Only update TP if it's actually 0 or nil (preserve existing TP value)
        if not current_tp_percent or current_tp_percent == 0 then
            current_tp_percent = pet.tp or 0
            if verbose then 
                windower.add_to_chat(8, 'Pet TP initialized in make_visible: ' .. tostring(current_tp_percent))
            end
        else
            if verbose then 
                windower.add_to_chat(8, 'Preserving existing TP value: ' .. tostring(current_tp_percent))
            end
        end
        
        current_mp = pet.mp or 0
        current_mp_percent = pet.mpp or 0
        max_mp = (pet.mpp and pet.mpp > 0 and pet.mp) and math.floor(pet.mp * 100 / pet.mpp) or 0
        
        -- Get abilities
        local abilities = windower.ffxi.get_abilities()
        abilitylist = abilities and abilities.job_abilities or {}
        
        -- Update display first
        update_display()
        
        -- Then update image if text is visible
        if bst_display:visible() and #(bst_display:text() or '') > 0 then
            update_pet_image()
        end
        
        if verbose then 
            windower.add_to_chat(8, 'Display Visible')
            windower.add_to_chat(8, 'Text content: ' .. (#(bst_display:text() or '') > 0 and 'Has content' or 'Empty'))
        end
    end
end

-- Function to make display invisible
function make_invisible()
    if petactive then
        bst_display:text('')
        bst_display:visible(false)
        if pet_image then
            pet_image:hide()
            pet_image:destroy()
            pet_image = nil
        end
        if verbose then windower.add_to_chat(8, 'Display Invisible') end
    end
    
    -- Reset all variables except stored_tp
    petactive = false
    mypet_idx = nil
    petname = nil
    pet = nil
    abilitylist = nil
    current_hp = 0
    max_hp = 0
    current_mp = 0
    max_mp = 0
    current_hp_percent = 0
    current_mp_percent = 0
    -- Keep stored_tp and current_tp_percent as is
    timercountdown = 5
end

-- Function to update pet image
function update_pet_image()
    if pet_image then
        pet_image:destroy()
        pet_image = nil
    end
    
    if petactive and petname then
        -- Always try lowercase version of filename first
        local image_name = string.lower(petname:gsub("%s+", ""):gsub("[^%w]", ""))
        local image_path = images_path..image_name..'.png'
        
        -- Check if file exists, if not use default
        if not windower.file_exists(image_path) then
            image_path = images_path..'BraveHeroGlenn.png'
            -- Check if default image exists
            if not windower.file_exists(image_path) then
                windower.add_to_chat(8, 'Default image not found: '..image_path)
                windower.add_to_chat(8, 'Please ensure the image exists in: '..images_path)
                return
            end
        end
        
        -- Get screen dimensions
        local screen_width = windower.get_windower_settings().ui_x_res
        local screen_height = windower.get_windower_settings().ui_y_res
        
        -- Get text position
        local text_x = bst_display:pos_x()
        local text_y = bst_display:pos_y()
        
        -- For right-aligned text, calculate position from the right edge of screen
        local image_x
        if settings.flags.right then
            -- Position image 250 pixels to the left of the text for right-aligned display
            image_x = math.abs(text_x) + 235
            if image_x < 0 then image_x = 0 end
            -- Convert to absolute screen position from right edge
            image_x = screen_width - image_x - 120
        else
            -- For left-aligned text, position image to the right
            image_x = text_x + 40
        end
        
        -- Ensure y position stays within bounds
        local image_y = math.max(0, math.min(screen_height - 120, text_y))
        image_y = image_y 
        
        -- Create image object with absolute positioning
        pet_image = images.new({
            pos = {
                x = image_x,
                y = image_y
            },
            size = {
                width = 100,
                height = 100
            },
            texture = {
                path = image_path,
                fit = false
            },
            repeatable = false,
            draggable = false,
            visible = true
        })
        
        if not pet_image then
            return
        end
        
        -- Force show and position
        pet_image:show()
        
        -- Try setting position again after a short delay
        coroutine.schedule(function()
            if pet_image then
                pet_image:pos(image_x, image_y)
                pet_image:show()
            end
        end, 0.1)
    end
end

-- Function to save settings
function save_settings()
    settings.pos.x = bst_display:pos_x()
    settings.pos.y = bst_display:pos_y()
    config.save(settings)
    
    -- Update pet image position when text position changes
    if pet_image then
        local screen_width = windower.get_windower_settings().ui_x_res
        local screen_height = windower.get_windower_settings().ui_y_res
        local text_x = bst_display:pos_x()
        local text_y = bst_display:pos_y()
        
        local image_x
        if settings.flags.right then
            image_x = math.abs(text_x) - 40
            if image_x < 0 then image_x = 0 end
            image_x = screen_width - image_x - 120
        else
            image_x = text_x + 40
        end
        
        local image_y = math.max(0, math.min(screen_height - 120, text_y))
        pet_image:pos(image_x, image_y)
    end
    windower.add_to_chat(207, string.format('Saved position: x=%d, y=%d', settings.pos.x, settings.pos.y))
end

-- Function to load positions
function load_positions()
    bst_display:pos(settings.pos.x, settings.pos.y)
end

-- Update drag handler for consistent bar positioning
bst_display:register_event('drag', function(text, x, y)
    settings.pos.x = x
    settings.pos.y = y
    
    -- Update bar positions when dragging
    local screen_width = windower.get_windower_settings().ui_x_res
    local actual_x = x
    
    if settings.flags.right then
        actual_x = screen_width + x - bar_settings.width * 2 - bar_settings.spacing + bar_settings.offset.x
    end
    
    -- Update HP bar position (left)
    if bars.hp.bg then bars.hp.bg:pos(actual_x, y + bar_settings.offset.y) end
    if bars.hp.fg then bars.hp.fg:pos(actual_x, y + bar_settings.offset.y) end
    if bars.hp.glow_mid then bars.hp.glow_mid:pos(actual_x, y + bar_settings.offset.y) end
    if bars.hp.glow_sides then bars.hp.glow_sides:pos(actual_x, y + bar_settings.offset.y) end
    
    -- Update TP bar position (right)
    local tp_x = actual_x + bar_settings.width + bar_settings.spacing
    if bars.tp.bg then bars.tp.bg:pos(tp_x, y + bar_settings.offset.y) end
    if bars.tp.fg then bars.tp.fg:pos(tp_x, y + bar_settings.offset.y) end
    if bars.tp.glow_mid then bars.tp.glow_mid:pos(tp_x, y + bar_settings.offset.y) end
    if bars.tp.glow_sides then bars.tp.glow_sides:pos(tp_x, y + bar_settings.offset.y) end
    
    -- Update pet image position
    if pet_image then
        local image_x
        if settings.flags.right then
            image_x = math.abs(x) - 40
            if image_x < 0 then image_x = 0 end
            image_x = screen_width - image_x - 120
        else
            image_x = x + 40
        end
        
        local image_y = math.max(0, math.min(screen_width - 120, y))
        pet_image:pos(image_x, image_y)
    end
    save_settings()
end)

-- Add a function to reset stored TP (call this when pet dies or is released)
function reset_stored_tp()
    stored_tp = 0
    current_tp_percent = 0
    last_valid_tp_time = 0
    if verbose then windower.add_to_chat(8, 'Reset stored TP values') end
end


