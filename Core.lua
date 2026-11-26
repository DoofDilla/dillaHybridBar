-- dillaHybridBar 0.3.11 - WoW Forever (Interface 16001)
-- Independent secure buttons. Never reads or changes Blizzard action slots/gamepad bindings.
local ADDON = ...
local MAX_SLOTS, BUTTON_SIZE, GAP = 60, 38, 3
local db, frame, optionsPanel, refreshOptions, minimapButton, bindingOwner, bindingPanel, bindingInput, bindingText
local openOptions
local buttons, bindingOverlays = {}, {}
local bindingMode, selectedBindingSlot = false, nil
local MINIMAP_RADIUS = 102 -- Outer edge of the native Forever minimap ring.
local DEFAULT = { x = 0, y = -235, scale = 1, locked = false, slots = {}, slotCount = 12, columns = 12, rows = 1, gap = 3, opacity = 0.9, minimapAngle = 220, minimapHidden = false, keybinds = {} }

local function say(message)
    print('|cff79c6ffdillaHybridBar:|r ' .. message)
end
local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end
local function spellInfo(id)
    if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(id) end
end
local function spellIcon(id)
    local info = spellInfo(id)
    if info and info.iconID then return info.iconID end
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
end
local function itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
end
local function mountInfo(id)
    if C_MountJournal and C_MountJournal.GetMountInfoByID then
        return C_MountJournal.GetMountInfoByID(id)
    end
end
local function getMacroIcon(id)
    if GetMacroInfo then
        local _, icon = GetMacroInfo(id)
        return icon
    end
end
local function updateIcon(i)
    local button = buttons[i]
    local slot = db.slots[i]
    if not button then return end
    local icon
    if slot then
        if slot.kind == 'spell' then icon = spellIcon(slot.id)
        elseif slot.kind == 'item' then icon = itemIcon(slot.id)
        elseif slot.kind == 'macro' then icon = getMacroIcon(slot.id)
        elseif slot.kind == 'mount' then
            local _, _, mountIcon = mountInfo(slot.id)
            icon = mountIcon
        end
    end
    button.icon:SetTexture(icon or 'Interface\\Buttons\\UI-Quickslot2')
    button.icon:SetDesaturated(not slot)
    button.empty:SetShown(not slot)
end
-- Show how many copies of a dragged item are carried in bags.
-- Uses the item ID (not a specific bag slot), so stacks in multiple bags
-- are counted together; bank contents are deliberately excluded.
local function updateCounts()
    if not db then return end
    for i, button in ipairs(buttons) do
        local slot = db.slots[i]
        local countText = ''
        if slot and slot.kind == 'item' and C_Item and C_Item.GetItemCount then
            local count = C_Item.GetItemCount(slot.id, false)
            -- Forever can mark some API results secret. Never branch on them.
            if type(count) == 'number' and not (issecretvalue and issecretvalue(count)) then
                if count ~= 1 then countText = tostring(count) end
            end
        end
        button.count:SetText(countText)
    end
end
-- Forever's cooldown start/duration can be secret in combat. Never pass
-- those numbers to SetCooldown from addon code. Spell cooldowns use Blizzard's
-- secret-safe duration objects instead.
local function updateCooldowns()
    if not db then return end
    for i, button in ipairs(buttons) do
        local slot = db.slots[i]
        local id, kind
        if slot then
            kind, id = slot.kind, slot.id
            if kind == 'mount' then
                if slot.spellID then kind, id = 'spell', slot.spellID end
            end
            if kind == 'macro' then
                if GetMacroSpell then
                    local spell = GetMacroSpell(id)
                    if spell then kind, id = 'spell', spell end
                end
                if kind == 'macro' and GetMacroItem then
                    local item = GetMacroItem(id)
                    if item then kind, id = 'item', item end
                end
            end
        end
        if kind == 'spell' and C_Spell and C_Spell.GetSpellCooldownDuration
            and button.cooldown.SetCooldownFromDurationObject then
            local durationObject = C_Spell.GetSpellCooldownDuration(id)
            if durationObject then
                button.cooldown:SetCooldownFromDurationObject(durationObject)
            else
                button.cooldown:Clear()
            end
        elseif kind == 'item' and C_Item and C_Item.GetItemCooldown then
            -- Unlike spell cooldowns, C_Item.GetItemCooldown does not return
            -- a duration object. Use the legacy call only for public numbers.
            local startTime, duration = C_Item.GetItemCooldown(id)
            local secretStart = startTime ~= nil and issecretvalue and issecretvalue(startTime)
            local secretDuration = duration ~= nil and issecretvalue and issecretvalue(duration)
            if startTime and duration and not secretStart and not secretDuration then
                button.cooldown:SetCooldown(startTime, duration)
            else
                button.cooldown:Clear()
            end
        else
            button.cooldown:Clear()
        end
    end
end
local function applySlot(i)
    local button, slot = buttons[i], db.slots[i]
    if not button or inCombat() then return end
    button:SetAttribute('type', nil)
    button:SetAttribute('spell', nil)
    button:SetAttribute('item', nil)
    button:SetAttribute('macro', nil)
    if slot then
        if slot.kind == 'spell' then
            button:SetAttribute('type', 'spell')
            button:SetAttribute('spell', slot.id)
        elseif slot.kind == 'item' then
            button:SetAttribute('type', 'item')
            button:SetAttribute('item', 'item:' .. slot.id)
        elseif slot.kind == 'macro' then
            button:SetAttribute('type', 'macro')
            button:SetAttribute('macro', slot.id)
        end
        -- Mount slots deliberately have no secure spell action: they use
        -- C_MountJournal.SummonByID directly from the user's button click.
        -- Other secure button types are entirely unchanged.
    end
    updateIcon(i)
end
-- Bindings are temporary Blizzard overrides, stored permanently in our own DB.
-- Never replace an existing binding silently, and never change overrides in combat.
local function keyForSlot(i)
    return db.keybinds and db.keybinds[i]
end
local function refreshHotkeys()
    for i, button in ipairs(buttons) do
        if button.hotkey then
            local key = keyForSlot(i)
            button.hotkey:SetText(key and (GetBindingText and GetBindingText(key, 'KEY_') or key) or '')
        end
    end
end
local function applyBindings()
    if not bindingOwner or not db or inCombat() then return end
    ClearOverrideBindings(bindingOwner)
    for i = 1, math.min(db.slotCount, MAX_SLOTS) do
        local key = keyForSlot(i)
        if key and buttons[i] then
            -- Preexisting normal bindings are not removed; they are overridden
            -- only for keys that the user explicitly assigned to this addon.
            SetOverrideBindingClick(bindingOwner, false, key, buttons[i]:GetName(), 'LeftButton')
        end
    end
    refreshHotkeys()
end
local function stopBindingCapture()
    selectedBindingSlot = nil
    if bindingInput then
        bindingInput:ClearFocus()
        bindingInput:Hide()
    end
    if bindingText then bindingText:SetText('Click a highlighted slot to assign a key. ESC cancels key capture; X closes binding mode.') end
end
local setBindingMode
local function bindingStatus(message)
    if bindingText then bindingText:SetText(message) end
end
local function captureBinding(key)
    local slot = selectedBindingSlot
    if not slot or inCombat() or not key then return end
    if key == 'ESCAPE' then stopBindingCapture(); return end
    if key == 'LSHIFT' or key == 'RSHIFT' or key == 'LCTRL' or key == 'RCTRL'
        or key == 'LALT' or key == 'RALT' or key == 'SHIFT' or key == 'CTRL' or key == 'ALT' then return end
    if key == 'BACKSPACE' or key == 'DELETE' then
        db.keybinds[slot] = nil
        applyBindings()
        stopBindingCapture()
        bindingStatus('Slot ' .. slot .. ' cleared. Click another slot, or ESC to close.')
        return
    end
    if IsShiftKeyDown() then key = 'SHIFT-' .. key end
    if IsControlKeyDown() then key = 'CTRL-' .. key end
    if IsAltKeyDown() then key = 'ALT-' .. key end
    local existing = GetBindingAction and GetBindingAction(key, true) or ''
    if existing and existing ~= '' and key ~= db.keybinds[slot] then
        -- GetBindingAction may describe another addon or a normal game binding.
        bindingStatus(key .. ' is already in use (' .. existing .. '). Choose another key.')
        return
    end
    for i, bound in pairs(db.keybinds) do
        if i ~= slot and bound == key then
            bindingStatus(key .. ' is already assigned to slot ' .. i .. '. Choose another key.')
            return
        end
    end
    db.keybinds[slot] = key
    applyBindings()
    stopBindingCapture()
    bindingStatus('Slot ' .. slot .. ': ' .. key .. '. Click another slot, or ESC to close.')
end
local function chooseBindingSlot(i)
    if not bindingMode or inCombat() then return end
    selectedBindingSlot = i
    bindingStatus('Slot ' .. i .. ': press a key (Shift/Ctrl/Alt allowed); Backspace clears; ESC cancels.')
    bindingInput:Show()
    bindingInput:SetFocus()
end
setBindingMode = function(enabled)
    if inCombat() then say('Keybinding mode is unavailable in combat.'); return end
    bindingMode = enabled and true or false
    stopBindingCapture()
    if bindingPanel then bindingPanel:SetShown(bindingMode) end
    for i, overlay in ipairs(bindingOverlays) do
        overlay:SetShown(bindingMode and i <= db.slotCount)
    end
    if bindingMode then say('Keybinding mode enabled: click a slot, then press a key. X closes the mode.') end
end
local function createBindingUI()
    bindingOwner = CreateFrame('Frame', 'dillaHybridBarBindingOwner', UIParent)
    bindingPanel = CreateFrame('Frame', 'dillaHybridBarBindingPanel', UIParent, 'BackdropTemplate')
    bindingPanel:SetSize(390, 86)
    bindingPanel:SetPoint('TOP', UIParent, 'TOP', 0, -130)
    bindingPanel:SetFrameStrata('DIALOG')
    bindingPanel:SetBackdrop({ bgFile='Interface\\Buttons\\WHITE8X8', edgeFile='Interface\\Tooltips\\UI-Tooltip-Border', edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
    bindingPanel:SetBackdropColor(.03,.04,.06,.95)
    bindingPanel:Hide()
    bindingText = bindingPanel:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    bindingText:SetPoint('TOPLEFT', 12, -14)
    bindingText:SetPoint('RIGHT', -55, 0)
    bindingText:SetJustifyH('LEFT')
    bindingText:SetText('Click a highlighted slot to assign a key. ESC closes binding mode.')
    local close = CreateFrame('Button', nil, bindingPanel, 'UIPanelCloseButton')
    close:SetPoint('TOPRIGHT', 1, 1)
    close:SetScript('OnClick', function() setBindingMode(false) end)
    bindingInput = CreateFrame('EditBox', 'dillaHybridBarBindingInput', bindingPanel, 'InputBoxTemplate')
    bindingInput:SetSize(200, 20)
    bindingInput:SetPoint('BOTTOM', 0, 8)
    bindingInput:SetAutoFocus(false)
    bindingInput:SetMaxLetters(0)
    bindingInput:EnableKeyboard(true)
    bindingInput:SetScript('OnKeyDown', function(_, key) captureBinding(key) end)
    bindingInput:SetScript('OnEscapePressed', function() stopBindingCapture() end)
    bindingInput:Hide()
    for i, button in ipairs(buttons) do
        local overlay = CreateFrame('Button', nil, frame)
        overlay:SetAllPoints(button)
        overlay:SetFrameLevel(button:GetFrameLevel() + 15)
        local shade = overlay:CreateTexture(nil, 'OVERLAY')
        shade:SetAllPoints()
        shade:SetColorTexture(.1,.45,.85,.28)
        local label = overlay:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
        label:SetPoint('CENTER')
        label:SetText('BIND')
        overlay:SetScript('OnClick', function() chooseBindingSlot(i) end)
        overlay:Hide()
        bindingOverlays[i] = overlay
    end
    applyBindings()
end

local function updateAll()
    for i = 1, MAX_SLOTS do applySlot(i) end
    updateCooldowns()
    updateCounts()
end
local function assignCursor(i)
    if inCombat() then say('Belegung im Kampf gesperrt.'); return end
    local kind, cursorId, bookType, spellId = GetCursorInfo()
    if kind ~= 'spell' and kind ~= 'item' and kind ~= 'macro' and kind ~= 'mount' then return end
    local id = kind == 'spell' and spellId or cursorId
    local mountSpellID
    if kind == 'mount' then
        -- Keep the journal mount ID for native summoning. The summoning spell
        -- ID is metadata only (cooldowns); it cannot reliably be cast as a
        -- regular spell in Forever.
        if type(cursorId) ~= 'number' or (issecretvalue and issecretvalue(cursorId)) then
            say('Could not read mount ID; slot unchanged.')
            return
        end
        local mountName
        mountName, mountSpellID = mountInfo(cursorId)
        if not mountName then
            say('Could not resolve Mount Collection entry; slot unchanged.')
            return
        end
    end
    if kind == 'spell' and (type(id) ~= 'number' or id <= 0) then
        -- Prefer the actual spell ID; never accidentally save a book index.
        if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and type(cursorId) == 'number' then
            local info = C_SpellBook.GetSpellBookItemInfo(cursorId, bookType or BOOKTYPE_SPELL)
            if info and info.spellID then id = info.spellID end
        end
    end
    if type(id) ~= 'number' then
        say('Dieser Cursor-Typ liefert keine numerische ID. Slot wurde nicht geaendert.')
        return
    end
    db.slots[i] = { kind = kind, id = id, spellID = mountSpellID }
    applySlot(i)
    updateCooldowns()
    updateCounts()
    ClearCursor()
end
local function tooltip(button)
    if not db then return end
    local slot = db.slots[button.index]
    GameTooltip:SetOwner(button, 'ANCHOR_RIGHT')
    if not slot then
        GameTooltip:AddLine('Leerer Slot')
        GameTooltip:AddLine('Zauber, Item, Makro oder Mount hierher ziehen.', .8, .8, .8)
    elseif slot.kind == 'spell' then
        GameTooltip:SetSpellByID(slot.id)
    elseif slot.kind == 'item' then
        GameTooltip:SetHyperlink('item:' .. slot.id)
    elseif slot.kind == 'macro' then
        local name = GetMacroInfo(slot.id)
        GameTooltip:AddLine(name or ('Makro #' .. slot.id))
        GameTooltip:AddLine('Makro (Index ' .. slot.id .. ')', .7, .7, .7)
    elseif slot.kind == 'mount' then
        local name = mountInfo(slot.id)
        GameTooltip:AddLine(name or 'Mount')
    end
    GameTooltip:AddLine('Shift + Rechtsklick: Slot leeren', .5, .8, 1)
    GameTooltip:Show()
end
local function clearSlot(i)
    if inCombat() then say('Belegung im Kampf gesperrt.'); return end
    db.slots[i] = nil
    applySlot(i)
    updateCooldowns()
    updateCounts()
end
local function makeButton(i)
    local button = CreateFrame('Button', 'dillaHybridBarButton' .. i, frame, 'SecureActionButtonTemplate')
    button.index = i
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetPoint('TOPLEFT', frame, 'TOPLEFT', 7 + (i - 1) * (BUTTON_SIZE + GAP), -7)
    -- WoW's secure action dispatch may be configured to run on button DOWN.
    -- Register both, but explicitly execute on UP (not twice).
    button:RegisterForClicks('AnyUp', 'AnyDown')
    button:SetAttribute('useOnKeyDown', false)
    button:RegisterForDrag('LeftButton')
    local bg = button:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints()
    bg:SetColorTexture(.05, .06, .08, .95)
    local icon = button:CreateTexture(nil, 'ARTWORK')
    icon:SetPoint('TOPLEFT', 2, -2)
    icon:SetPoint('BOTTOMRIGHT', -2, 2)
    button.icon = icon
    local empty = button:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    empty:SetPoint('CENTER')
    empty:SetText(tostring(i))
    button.empty = empty
    local count = button:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
    count:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', -3, 3)
    count:SetJustifyH('RIGHT')
    count:SetText('')
    button.count = count
    local hotkey = button:CreateFontString(nil, 'OVERLAY', 'NumberFontNormalSmall')
    hotkey:SetPoint('TOPRIGHT', button, 'TOPRIGHT', -3, -3)
    hotkey:SetJustifyH('RIGHT')
    button.hotkey = hotkey
    local cooldown = CreateFrame('Cooldown', nil, button, 'CooldownFrameTemplate')
    cooldown:SetAllPoints(icon)
    button.cooldown = cooldown
    -- Secure actions still handle spells/items/macros. Mounts use the
    -- native journal summoning API when a mouse click or binding clicks this
    -- same button. Do not duplicate the call on mouse-down.
    button:HookScript('OnClick', function(self, mouseButton, down)
        if mouseButton ~= 'LeftButton' or down then return end
        local slot = db and db.slots[self.index]
        if slot and slot.kind == 'mount' and C_MountJournal
            and C_MountJournal.SummonByID and not inCombat() then
            C_MountJournal.SummonByID(slot.id)
        end
    end)
    button:SetScript('OnReceiveDrag', function(self) assignCursor(self.index) end)
    button:HookScript('OnMouseUp', function(self, mouseButton)
        if mouseButton == 'RightButton' and IsShiftKeyDown() then
            clearSlot(self.index)
        elseif mouseButton == 'LeftButton' and GetCursorInfo() then
            assignCursor(self.index)
        end
    end)
    button:SetScript('OnEnter', tooltip)
    button:SetScript('OnLeave', function() GameTooltip:Hide() end)
    buttons[i] = button
end
local function applyLayout()
    if not frame or not db or inCombat() then return end
    local count = math.max(1, math.min(MAX_SLOTS, tonumber(db.slotCount) or 12))
    local columns = math.max(1, math.min(count, tonumber(db.columns) or count))
    local rows = math.ceil(count / columns)
    local gap = math.max(0, math.min(12, tonumber(db.gap) or 3))
    db.slotCount, db.columns, db.rows, db.gap = count, columns, rows, gap
    local width = 14 + columns * BUTTON_SIZE + (columns - 1) * gap
    local height = 14 + rows * BUTTON_SIZE + (rows - 1) * gap
    frame:SetSize(width, height)
    frame:SetBackdropColor(.025, .03, .04, db.opacity or .9)
    for i, button in ipairs(buttons) do
        if i <= count then
            local column = (i - 1) % columns
            local row = math.floor((i - 1) / columns)
            button:ClearAllPoints()
            button:SetPoint('TOPLEFT', frame, 'TOPLEFT', 7 + column * (BUTTON_SIZE + gap), -7 - row * (BUTTON_SIZE + gap))
            button:Show()
        else
            button:Hide()
        end
    end
    if bindingMode then
        for i, overlay in ipairs(bindingOverlays) do overlay:SetShown(i <= count) end
    end
    if bindingOwner then applyBindings() end
end
local function updateLock()
    if not frame then return end
    frame.handle:SetShown(not db.locked)
end
-- Store the exact anchor returned by WoW after dragging, rather than
-- converting frame centers between unrelated effective scale spaces.
-- StartMoving/StopMovingOrSizing can also set the engine's user-placed flag;
-- turn it off so the engine does not compete with our SavedVariables.
local function placeFrame()
    frame:SetUserPlaced(false)
    frame:SetScale(db.scale)
    frame:ClearAllPoints()
    local point = db.positionPoint or 'CENTER'
    local relativePoint = db.positionRelativePoint or 'CENTER'
    if db.positionPoint then
        if db.positionScreenAnchor then
            frame:SetPoint(point, nil, relativePoint, db.x or 0, db.y or 0)
        else
            frame:SetPoint(point, UIParent, relativePoint, db.x or 0, db.y or 0)
        end
    else
        -- Pre-0.3.6 data: use existing offsets until the first move.
        frame:SetPoint('CENTER', UIParent, 'CENTER', db.x or 0, db.y or 0)
    end
end
local function savePosition()
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    if not point or type(x) ~= 'number' or type(y) ~= 'number' then return end
    -- StartMoving usually anchors to the screen (nil); StopMovingOrSizing
    -- chooses the nearest screen point. Reproduce that same anchor on reload.
    db.positionPoint = point
    db.positionRelativePoint = relativePoint or point
    db.positionScreenAnchor = relativeTo == nil
    db.x, db.y = x, y
    frame:SetUserPlaced(false)
    placeFrame()
end
-- Small standalone minimap launcher, no LibDBIcon or external dependencies.
local function updateMinimapPosition()
    if not minimapButton or not Minimap or not db then return end
    local angle = math.rad(db.minimapAngle or 220)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint('CENTER', Minimap, 'CENTER', math.cos(angle) * MINIMAP_RADIUS, math.sin(angle) * MINIMAP_RADIUS)
end
local function createMinimapButton()
    if not Minimap then return end
    local button = CreateFrame('Button', 'dillaHybridBarMinimapButton', Minimap)
    minimapButton = button
    button:SetSize(32, 32)
    button:SetFrameStrata('MEDIUM')
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    button:RegisterForDrag('LeftButton')
    button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
    local border = button:CreateTexture(nil, 'OVERLAY')
    border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
    border:SetSize(54, 54)
    border:SetPoint('TOPLEFT', 0, 0)
    local icon = button:CreateTexture(nil, 'BACKGROUND')
    icon:SetTexture('Interface\\Icons\\Trade_Engineering')
    icon:SetSize(20, 20)
    icon:SetPoint('CENTER', 0, 0)
    button:SetScript('OnClick', function(_, mouse)
        if mouse == 'LeftButton' and IsControlKeyDown() then
            setBindingMode(not bindingMode)
        elseif mouse == 'RightButton' then
            if inCombat() then say('Leiste im Kampf nicht sperren/entsperren.'); return end
            db.locked = not db.locked
            updateLock()
            if refreshOptions then refreshOptions() end
            say(db.locked and 'Leiste gesperrt (Griff ausgeblendet).' or 'Leiste entsperrt (am MOVE-Griff ziehen).')
        elseif mouse == 'LeftButton' and IsShiftKeyDown() then
            if inCombat() then say('Leiste im Kampf nicht ein-/ausblenden.'); return end
            frame:SetShown(not frame:IsShown())
        else
            openOptions()
        end
    end)
    button:SetScript('OnDragStart', function(self) self.dragging = true end)
    button:SetScript('OnDragStop', function(self) self.dragging = false end)
    button:SetScript('OnUpdate', function(self)
        if not self.dragging then return end
        local x, y = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local mx, my = Minimap:GetCenter()
        if not x or not mx then return end
        local angle = math.deg(math.atan2(y / scale - my, x / scale - mx))
        db.minimapAngle = angle
        updateMinimapPosition()
    end)
    button:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
        GameTooltip:AddLine('dillaHybridBar')
        GameTooltip:AddLine('Left click: Options', .8, .8, .8)
        GameTooltip:AddLine('Right click: Lock/unlock bar', .8, .8, .8)
        GameTooltip:AddLine('Shift + left click: Show/hide bar', .8, .8, .8)
        GameTooltip:AddLine('Ctrl + Left-click: Bind Keys', .8, .8, .8)
        GameTooltip:AddLine('Drag: Move minimap button', .8, .8, .8)
        GameTooltip:Show()
    end)
    button:SetScript('OnLeave', function() GameTooltip:Hide() end)
    updateMinimapPosition()
    button:SetShown(not db.minimapHidden)
end
-- Simple native options panel: no external libraries and no protected UI modifications.
local function createOptions()
    optionsPanel = CreateFrame('Frame', 'dillaHybridBarOptions', UIParent)
    optionsPanel.name = 'dillaHybridBar'
    local heading = optionsPanel:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
    heading:SetPoint('TOPLEFT', 20, -20)
    heading:SetText('dillaHybridBar')
    local intro = optionsPanel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
    intro:SetPoint('TOPLEFT', heading, 'BOTTOMLEFT', 0, -9)
    intro:SetText('Independent action bar for mouse + controller hybrid play')

    local warning = optionsPanel:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
    warning:SetPoint('TOPLEFT', intro, 'BOTTOMLEFT', 0, -10)
    warning:SetText('Layout and secure-button settings cannot be changed during combat.')

    local updating = false
    local sliders = {}
    local function newSlider(name, title, minVal, maxVal, step, y, getter, change, format)
        local slider = CreateFrame('Slider', 'dillaHybridBarOpt' .. name, optionsPanel, 'OptionsSliderTemplate')
        slider:SetPoint('TOPLEFT', 24, y)
        slider:SetWidth(280)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
        _G[slider:GetName() .. 'Low']:SetText(tostring(minVal))
        _G[slider:GetName() .. 'High']:SetText(tostring(maxVal))
        local label = _G[slider:GetName() .. 'Text']
        slider.refresh = function()
            local value = getter()
            updating = true
            slider:SetValue(value)
            updating = false
            label:SetText(title .. ': ' .. (format and format(value) or tostring(value)))
        end
        slider:SetScript('OnValueChanged', function(self, value)
            if updating then return end
            if inCombat() then self.refresh(); return end
            value = math.floor(value / step + .5) * step
            change(value)
            applyLayout()
            for _, other in ipairs(sliders) do other.refresh() end
        end)
        sliders[#sliders + 1] = slider
        return slider
    end
    newSlider('Slots', 'Total slots', 1, MAX_SLOTS, 1, -115,
        function() return db.slotCount end,
        function(value) db.slotCount = value; db.columns = math.min(value, db.columns) end)
    newSlider('Columns', 'Columns', 1, MAX_SLOTS, 1, -181,
        function() return db.columns end,
        function(value) db.columns = math.min(value, db.slotCount) end)
    newSlider('Rows', 'Rows', 1, MAX_SLOTS, 1, -247,
        function() return db.rows end,
        function(value) db.columns = math.ceil(db.slotCount / value) end)
    newSlider('Scale', 'Scale', .5, 2, .05, -313,
        function() return db.scale end,
        function(value) db.scale = value; placeFrame() end,
        function(value) return string.format('%.2f', value) end)
    newSlider('Spacing', 'Button spacing', 0, 12, 1, -379,
        function() return db.gap end,
        function(value) db.gap = value end)
    newSlider('Opacity', 'Background opacity', .1, 1, .05, -445,
        function() return db.opacity end,
        function(value) db.opacity = value end,
        function(value) return tostring(math.floor(value * 100 + .5)) .. '%' end)

    local lock = CreateFrame('CheckButton', 'dillaHybridBarOptLock', optionsPanel, 'InterfaceOptionsCheckButtonTemplate')
    lock:SetPoint('TOPLEFT', 23, -492)
    _G[lock:GetName() .. 'Text']:SetText('Lock bar (hide drag handle)')
    lock:SetScript('OnClick', function(self)
        if inCombat() then self:SetChecked(db.locked); return end
        db.locked = self:GetChecked() and true or false
        updateLock()
    end)

    local minimapCheck = CreateFrame('CheckButton', 'dillaHybridBarOptMinimap', optionsPanel, 'InterfaceOptionsCheckButtonTemplate')
    minimapCheck:SetPoint('TOPLEFT', 285, -492)
    _G[minimapCheck:GetName() .. 'Text']:SetText('Show minimap button')
    minimapCheck:SetScript('OnClick', function(self)
        db.minimapHidden = not self:GetChecked()
        if minimapButton then minimapButton:SetShown(not db.minimapHidden) end
    end)

    local bindKeys = CreateFrame('Button', nil, optionsPanel, 'UIPanelButtonTemplate')
    bindKeys:SetPoint('TOPLEFT', 230, -545)
    bindKeys:SetSize(152, 24)
    bindKeys:SetText('Bind Keys')
    bindKeys:SetScript('OnClick', function()
        if SettingsPanel and SettingsPanel:IsShown() then SettingsPanel:Hide() end
        setBindingMode(not bindingMode)
    end)

    local reset = CreateFrame('Button', nil, optionsPanel, 'UIPanelButtonTemplate')
    reset:SetPoint('TOPLEFT', 22, -545)
    reset:SetSize(174, 24)
    reset:SetText('Reset layout and position')
    reset:SetScript('OnClick', function()
        if inCombat() then say('Nicht im Kampf zuruecksetzen.'); return end
        db.positionPoint, db.positionRelativePoint, db.positionScreenAnchor = nil, nil, nil
        db.x, db.y, db.scale, db.slotCount, db.columns, db.rows, db.gap, db.opacity, db.locked =
            DEFAULT.x, DEFAULT.y, DEFAULT.scale, DEFAULT.slotCount, DEFAULT.columns, DEFAULT.rows, DEFAULT.gap, DEFAULT.opacity, false
        placeFrame(); updateLock(); applyLayout()
        optionsPanel:refresh()
    end)
    function optionsPanel:refresh()
        if not db then return end
        for _, slider in ipairs(sliders) do slider.refresh() end
        lock:SetChecked(db.locked)
        minimapCheck:SetChecked(not db.minimapHidden)
    end
    optionsPanel:SetScript('OnShow', function(self) self:refresh() end)
    refreshOptions = function() if optionsPanel and optionsPanel:IsShown() then optionsPanel:refresh() end end

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(optionsPanel, 'dillaHybridBar')
        Settings.RegisterAddOnCategory(category)
        optionsPanel.categoryID = category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(optionsPanel)
    end
end
openOptions = function()
    if not optionsPanel then return end
    if optionsPanel.categoryID and Settings and Settings.OpenToCategory then
        -- On some clients the first call opens the AddOns settings tab
        -- without activating our category. A second selection resolves it.
        Settings.OpenToCategory(optionsPanel.categoryID)
        Settings.OpenToCategory(optionsPanel.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    else
        say('Open Game Menu > Options > AddOns > dillaHybridBar.')
    end
end

local function initialize()
    dillaHybridBarDB = dillaHybridBarDB or {}
    db = dillaHybridBarDB
    for key, value in pairs(DEFAULT) do
        if db[key] == nil then db[key] = value end
    end
    db.slots = db.slots or {}
    db.keybinds = db.keybinds or {}
    -- Migration from v0.3.10: that version stored dragged mounts as spells.
    -- Identify only spells that the journal confirms are mount summon spells.
    if C_MountJournal and C_MountJournal.GetMountFromSpell then
        for i = 1, MAX_SLOTS do
            local slot = db.slots[i]
            if slot and slot.kind == 'spell' then
                local mountID = C_MountJournal.GetMountFromSpell(slot.id)
                if type(mountID) == 'number' and not (issecretvalue and issecretvalue(mountID))
                    and mountID > 0 then
                    db.slots[i] = { kind = 'mount', id = mountID, spellID = slot.id }
                end
            end
        end
    end
    db.slotCount = math.max(1, math.min(MAX_SLOTS, tonumber(db.slotCount) or 12))
    -- v0.1.0 stored spellbook INDEX as if it were the Spell ID.
    -- Existing spell entries cannot be recovered reliably; clear them once.
    if (db.dataVersion or 1) < 2 then
        local cleared = 0
        for i = 1, MAX_SLOTS do
            if db.slots[i] and db.slots[i].kind == 'spell' then
                db.slots[i] = nil
                cleared = cleared + 1
            end
        end
        db.dataVersion = 2
        if cleared > 0 then say(cleared .. ' alte Zauber-Slots entfernt (0.1.0-ID-Fehler). Bitte neu belegen.') end
    end
    frame = CreateFrame('Frame', 'dillaHybridBarFrame', UIParent, 'BackdropTemplate')
    frame:SetSize(12 * (BUTTON_SIZE + GAP) - GAP + 14, BUTTON_SIZE + 14)
    frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8', edgeFile='Interface\\Tooltips\\UI-Tooltip-Border', edgeSize=12, insets={left=3,right=3,top=3,bottom=3}})
    frame:SetBackdropColor(.025,.03,.04,db.opacity or .9)
    frame:SetBackdropBorderColor(.3,.55,.75,.8)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetUserPlaced(false)
    -- IMPORTANT: Build secure buttons before applying the saved grid layout.
    -- applyLayout() positions existing buttons; calling it here would resize
    -- only the parent and leave all buttons in their default single row.
    -- The bar has NO title strip. An independent floating handle appears only
    -- while unlocked, and never takes up space inside the action button panel.
    local handle = CreateFrame('Button', 'dillaHybridBarMoveHandle', frame, 'BackdropTemplate')
    handle:SetSize(96, 19)
    handle:SetPoint('BOTTOM', frame, 'TOP', 0, 4)
    handle:SetFrameLevel(frame:GetFrameLevel() + 10)
    handle:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8', edgeFile='Interface\\Tooltips\\UI-Tooltip-Border', edgeSize=10, insets={left=2,right=2,top=2,bottom=2}})
    handle:SetBackdropColor(.025, .03, .04, .95)
    handle:SetBackdropBorderColor(.3, .55, .75, .9)
    handle:RegisterForDrag('LeftButton')
    frame.handle = handle
    local label = handle:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    label:SetPoint('CENTER', 0, 0)
    label:SetText('MOVE')
    handle:SetScript('OnDragStart', function()
        if not db.locked and not inCombat() then frame:StartMoving() end
    end)
    handle:SetScript('OnDragStop', function()
        frame:StopMovingOrSizing()
        savePosition()
    end)
    for i = 1, MAX_SLOTS do makeButton(i) end
    -- All buttons now exist: restore saved rows/columns and hide unused slots.
    -- Size before positioning to avoid SetClampedToScreen offset on reload.
    applyLayout()
    placeFrame()
    updateLock()
    createBindingUI()
    createOptions()
    createMinimapButton()
    updateAll()
    updateCounts()
    say('Geladen. /dhb fuer Optionen; /dhb help fuer Befehle. Zauber/Makros/Items auf Slots ziehen.')
end
SLASH_DILLAHYBRIDBAR1 = '/dhb'
SlashCmdList.DILLAHYBRIDBAR = function(message)
    if not db then return end
    local command, arg = (message or ''):match('^(%S*)%s*(.-)%s*$')
    command = (command or ''):lower()
    if command == '' or command == 'config' or command == 'options' then
        openOptions()
    elseif command == 'lock' then
        if inCombat() then say('Nicht im Kampf sperren.'); return end
        db.locked = true; updateLock(); if refreshOptions then refreshOptions() end; say('Leiste gesperrt (Griff ausgeblendet).')
    elseif command == 'unlock' then
        if inCombat() then say('Nicht im Kampf entsperren.'); return end
        db.locked = false; updateLock(); if refreshOptions then refreshOptions() end; say('Leiste entsperrt (am MOVE-Griff ziehen).')
    elseif command == 'bind' then
        setBindingMode(not bindingMode)
    elseif command == 'slots' then
        local n = tonumber(arg)
        if not n or n ~= math.floor(n) or n < 1 or n > MAX_SLOTS then say('Usage: /dhb slots 1-' .. MAX_SLOTS); return end
        if inCombat() then say('Nicht waehrend des Kampfes aendern.'); return end
        db.slotCount = n; db.columns = math.min(db.columns, n)
        applyLayout(); if refreshOptions then refreshOptions() end
        say('Aktive Slots: ' .. n .. ' (versteckte Belegungen bleiben gespeichert).')
    elseif command == 'scale' then
        local v = tonumber(arg)
        if not v or v < .5 or v > 2 then say('Skalierung: /dhb scale 0.5 bis 2.0'); return end
        if inCombat() then say('Nicht waehrend des Kampfes skalieren.'); return end
        db.scale = v
        placeFrame(); if refreshOptions then refreshOptions() end
        say('Skalierung: ' .. v)
    elseif command == 'reset' then
        if inCombat() then say('Nicht waehrend des Kampfes zuruecksetzen.'); return end
        db.positionPoint, db.positionRelativePoint, db.positionScreenAnchor = nil, nil, nil
        db.x, db.y, db.scale, db.locked = DEFAULT.x, DEFAULT.y, DEFAULT.scale, false
        db.slotCount, db.columns, db.rows, db.gap, db.opacity = DEFAULT.slotCount, DEFAULT.columns, DEFAULT.rows, DEFAULT.gap, DEFAULT.opacity
        placeFrame(); updateLock(); applyLayout(); if refreshOptions then refreshOptions() end; say('Position und Skalierung zurueckgesetzt; Belegungen bleiben.')
    elseif command == 'show' then
        if inCombat() then say('Nicht waehrend des Kampfes anzeigen.'); return end
        frame:Show()
    elseif command == 'hide' then
        if inCombat() then say('Nicht waehrend des Kampfes verstecken.'); return end
        frame:Hide()
    else
        say('Befehle: /dhb (Options) | config | lock | unlock | slots 1-60 | scale 0.5-2 | bind | reset | show | hide')
        say('Shift+Rechtsklick leert einen Slot (ausserhalb des Kampfes).')
    end
end
local events = CreateFrame('Frame')
events:RegisterEvent('PLAYER_LOGIN')
events:RegisterEvent('SPELL_UPDATE_COOLDOWN')
events:RegisterEvent('BAG_UPDATE_COOLDOWN')
events:RegisterEvent('BAG_UPDATE_DELAYED')
events:RegisterEvent('BAG_UPDATE')
events:RegisterEvent('SPELLS_CHANGED')
events:RegisterEvent('UPDATE_MACROS')
events:RegisterEvent('GET_ITEM_INFO_RECEIVED')
events:SetScript('OnEvent', function(_, event)
    if event == 'PLAYER_LOGIN' then initialize(); return end
    if not db then return end
    if event == 'SPELLS_CHANGED' or event == 'UPDATE_MACROS' or event == 'GET_ITEM_INFO_RECEIVED' then
        for i = 1, MAX_SLOTS do updateIcon(i) end
    end
    updateCooldowns()
    if event == 'BAG_UPDATE_DELAYED' or event == 'BAG_UPDATE' or event == 'GET_ITEM_INFO_RECEIVED' then
        updateCounts()
    end
end)