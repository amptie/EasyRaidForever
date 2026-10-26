-- =============================================================================
-- EasyRaidForever - UI/Common/Widgets.lua
--
-- The addon's own small widget toolkit (ported from EasyRaidLoot). Every page
-- builds from these, so the look is defined once.
--
-- Forever / modern client rules applied here:
--  1. SetBackdrop only exists on frames created with "BackdropTemplate".
--  2. Solid fills use Texture:SetColorTexture (SetTexture(r,g,b,a) is gone).
--  3. Frames clip with SetClipsChildren, so scroll lists may draw a partial row.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util
local C = Util.COLORS

local Widgets = {}
ERF.Widgets = Widgets

local WHITE = "Interface\\Buttons\\WHITE8x8"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

-- CreateFrame that always carries the backdrop template.
function Widgets.Frame(frameType, name, parent, template)
    local tpl = template and (BACKDROP and (template .. "," .. BACKDROP) or template) or BACKDROP
    return CreateFrame(frameType, name, parent, tpl)
end

local function Fill(tex, c, alpha)
    tex:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end
Widgets.Fill = Fill

-- ---------------------------------------------------------------------------
-- Backdrops
-- ---------------------------------------------------------------------------
function Widgets.ApplyBackdrop(frame, opts)
    if not frame or not frame.SetBackdrop then return end
    opts = opts or {}
    frame:SetBackdrop({
        bgFile   = opts.bgFile,
        edgeFile = opts.edgeFile,
        tile     = opts.tile or false,
        tileSize = opts.tileSize,
        edgeSize = opts.edgeSize or 1,
        insets   = opts.insets or { left = 1, right = 1, top = 1, bottom = 1 },
    })
    if opts.bgColor then frame:SetBackdropColor(unpack(opts.bgColor)) end
    if opts.borderColor then frame:SetBackdropBorderColor(unpack(opts.borderColor)) end
end

function Widgets.StyleWindow(frame)
    Widgets.ApplyBackdrop(frame, {
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        bgColor = C.PANEL_BG, borderColor = C.GOLD_DIM,
    })
end

function Widgets.StylePanel(frame, alpha)
    Widgets.ApplyBackdrop(frame, {
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        bgColor = { C.SUB_BG[1], C.SUB_BG[2], C.SUB_BG[3], alpha or C.SUB_BG[4] },
        borderColor = { 1, 1, 1, 0.08 },
    })
end

-- A sunken panel frame.
function Widgets.CreatePanel(parent, alpha)
    local f = Widgets.Frame("Frame", nil, parent)
    Widgets.StylePanel(f, alpha)
    return f
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------
function Widgets.CreateLabel(parent, text, size, color)
    local font = "GameFontNormal"
    if size == "title" then font = "GameFontNormalLarge"
    elseif size == "small" then font = "GameFontHighlightSmall" end
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    local c = color or C.TEXT
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
end

function Widgets.CreateSectionHeader(parent, text, width)
    local fs = Widgets.CreateLabel(parent, text, "header", C.GOLD)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    Fill(line, C.HAIRLINE)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
    line:SetWidth(width or 300)
    fs.line = line
    return fs
end

function Widgets.CreateParagraph(parent, text, width, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetText(text or "")
    local c = color or C.TEXT
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    return fs
end

function Widgets.CreateSeparator(parent, width)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetHeight(1)
    tex:SetWidth(width or 100)
    Fill(tex, C.HAIRLINE)
    return tex
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------
function Widgets.CreateButton(parent, text, width, height, onClick)
    local btn = Widgets.Frame("Button", nil, parent)
    btn:SetSize(width or 100, height or 22)
    Widgets.ApplyBackdrop(btn, {
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        bgColor = { 0.10, 0.11, 0.14, 0.95 }, borderColor = { 1, 1, 1, 0.14 },
    })

    btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.Text:SetPoint("CENTER")
    btn.Text:SetText(text or "")
    btn.enabled = true
    btn.primary = false

    function btn:SetEnabledState(on, reason)
        self.enabled = on and true or false
        self.disabledReason = (not on) and reason or nil
        if self.enabled then
            if self.primary then
                self:SetBackdropColor(0.20, 0.17, 0.09, 0.95)
                self.Text:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3])
            else
                self:SetBackdropColor(0.10, 0.11, 0.14, 0.95)
                self.Text:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3])
            end
        else
            self:SetBackdropColor(0.06, 0.06, 0.08, 0.7)
            self.Text:SetTextColor(C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3])
        end
    end

    -- Enables the button when `ok`, otherwise disables it with `reason` as
    -- tooltip - the shape Perms:Can returns.
    function btn:SetAllowed(ok, reason)
        self:SetEnabledState(ok, reason)
    end

    function btn:SetLabel(t) self.Text:SetText(t or "") end

    btn:SetScript("OnEnter", function(self)
        if self.enabled then self:SetBackdropBorderColor(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.7) end
        local tip = self.disabledReason or self.tooltipText
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.tooltipTitle then GameTooltip:AddLine(self.tooltipTitle, 1, 1, 1) end
            GameTooltip:AddLine(tip, 0.8, 0.82, 0.88, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self.primary then
            self:SetBackdropBorderColor(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.55)
        else
            self:SetBackdropBorderColor(1, 1, 1, 0.14)
        end
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self, button)
        if not self.enabled then return end
        if onClick then Util.Guard(onClick, "button:" .. tostring(text), self, button) end
    end)
    return btn
end

function Widgets.MakePrimary(btn)
    btn.primary = true
    btn:SetBackdropBorderColor(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.55)
    btn:SetEnabledState(btn.enabled)
    return btn
end

-- ---------------------------------------------------------------------------
-- Check box
-- ---------------------------------------------------------------------------
function Widgets.CreateCheckBox(parent, label, onToggle)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetHeight(18)

    local box = Widgets.Frame("Frame", nil, cb)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", cb, "LEFT", 0, 0)
    Widgets.ApplyBackdrop(box, {
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        bgColor = { 0.02, 0.02, 0.03, 0.8 }, borderColor = { 1, 1, 1, 0.20 },
    })

    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", -3, 3)
    Fill(tick, C.GOLD, 1)
    tick:Hide()

    cb.Text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.Text:SetPoint("LEFT", box, "RIGHT", 6, 0)
    cb.Text:SetText(label or "")
    cb:SetWidth(20 + (cb.Text:GetStringWidth() or 60))
    cb.checked = false
    cb.enabled = true

    function cb:SetChecked(on)
        self.checked = on and true or false
        tick:SetShown(self.checked)
    end
    function cb:GetChecked() return self.checked end
    function cb:SetEnabledState(on)
        self.enabled = on and true or false
        local c = self.enabled and C.TEXT or C.TEXT_DIM
        self.Text:SetTextColor(c[1], c[2], c[3])
    end

    cb:SetScript("OnClick", function(self)
        if not self.enabled then return end
        self:SetChecked(not self.checked)
        if onToggle then Util.Guard(onToggle, "checkbox:" .. tostring(label), self.checked) end
    end)
    cb:SetScript("OnEnter", function(self)
        box:SetBackdropBorderColor(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.7)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tooltipText, 0.8, 0.82, 0.88, true)
            GameTooltip:Show()
        end
    end)
    cb:SetScript("OnLeave", function()
        box:SetBackdropBorderColor(1, 1, 1, 0.20)
        GameTooltip:Hide()
    end)
    return cb
end

-- ---------------------------------------------------------------------------
-- Edit boxes
-- ---------------------------------------------------------------------------
function Widgets.CreateEditBox(parent, width, height, onChange, onEnter)
    local holder = Widgets.Frame("Frame", nil, parent)
    holder:SetSize(width or 160, height or 22)
    Widgets.StylePanel(holder, 0.8)

    local eb = CreateFrame("EditBox", nil, holder)
    eb:SetPoint("TOPLEFT", 6, -2)
    eb:SetPoint("BOTTOMRIGHT", -6, 2)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3])
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onEnter then Util.Guard(onEnter, "editbox.enter", self:GetText()) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if onChange then
        eb:SetScript("OnTextChanged", function(self, userInput)
            if userInput then Util.Guard(onChange, "editbox", self:GetText()) end
        end)
    end

    -- Grey hint text while empty.
    local hint = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", 6, 0)
    hint:SetTextColor(C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3], 0.8)
    local function UpdateHint() hint:SetShown(eb:GetText() == "" and not eb:HasFocus()) end
    eb:HookScript("OnEditFocusGained", UpdateHint)
    eb:HookScript("OnEditFocusLost", UpdateHint)
    eb:HookScript("OnTextChanged", UpdateHint)

    holder.editBox = eb
    function holder:GetText() return eb:GetText() end
    function holder:SetText(t) eb:SetText(t or "") UpdateHint() end
    function holder:SetHint(t) hint:SetText(t or "") UpdateHint() end
    function holder:SetFocus() eb:SetFocus() end
    function holder:ClearFocus() eb:ClearFocus() end
    function holder:SetEnabledState(on)
        eb:SetEnabled(on and true or false)
        local c = on and C.TEXT or C.TEXT_DIM
        eb:SetTextColor(c[1], c[2], c[3])
    end
    return holder
end

function Widgets.CreateTextArea(parent, width, height, readOnly)
    local holder = Widgets.Frame("Frame", nil, parent)
    holder:SetSize(width or 300, height or 80)
    Widgets.StylePanel(holder, 0.8)

    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local new = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 30))
        self:SetVerticalScroll(new)
    end)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextColor(C.TEXT[1], C.TEXT[2], C.TEXT[3])
    eb:SetWidth((width or 300) - 16)
    eb:SetHeight((height or 80) - 12)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    if readOnly then
        eb:SetScript("OnTextChanged", function(self, userInput)
            if userInput and self.storedText then
                self:SetText(self.storedText)
                self:HighlightText()
            end
        end)
    end
    scroll:SetScrollChild(eb)

    holder:SetScript("OnSizeChanged", function(_, w, h)
        eb:SetWidth(math.max(80, (w or 100) - 16))
        eb:SetHeight(math.max(20, (h or 40) - 12))
    end)
    -- Clicking anywhere in the box focuses the edit box.
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() eb:SetFocus() end)

    holder.editBox = eb
    function holder:GetText() return eb:GetText() end
    function holder:SetText(t)
        eb.storedText = t or ""
        eb:SetText(t or "")
        eb:SetCursorPosition(0)
    end
    function holder:SelectAll()
        eb:SetFocus()
        eb:HighlightText()
    end
    return holder
end

-- ---------------------------------------------------------------------------
-- Dropdown and context menu
--
-- A small custom control rather than UIDropDownMenu (taint prone and hard to
-- theme). One shared popup serves every dropdown and every context menu.
-- ---------------------------------------------------------------------------
local popup
local POPUP_ROW_H = 18
local POPUP_MAX_ROWS = 18

local function GetPopup()
    if popup then return popup end
    popup = Widgets.Frame("Frame", "EasyRaidForeverDropdownPopup", UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:Hide()
    Widgets.ApplyBackdrop(popup, {
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        bgColor = { 0.06, 0.07, 0.09, 0.98 }, borderColor = C.GOLD_DIM,
    })
    popup.buttons = {}
    popup.offset = 0
    popup:EnableMouseWheel(true)
    popup:SetScript("OnMouseWheel", function(self, delta)
        local maxOff = math.max(0, #(self.items or {}) - POPUP_MAX_ROWS)
        self.offset = math.max(0, math.min(maxOff, self.offset - delta))
        self:Redraw()
    end)
    popup:SetScript("OnHide", function(self)
        self.owner = nil
        self.onSelect = nil
        self.items = nil
    end)

    function popup:Redraw()
        local items = self.items or {}
        local shown = math.min(#items, POPUP_MAX_ROWS)
        for i = 1, math.max(shown, #self.buttons) do
            local btn = self.buttons[i]
            if not btn and i <= shown then
                btn = CreateFrame("Button", nil, self)
                btn:SetHeight(POPUP_ROW_H)
                btn:SetPoint("LEFT", self, "LEFT", 3, 0)
                btn:SetPoint("RIGHT", self, "RIGHT", -3, 0)
                btn:SetPoint("TOP", self, "TOP", 0, -3 - (i - 1) * POPUP_ROW_H)
                btn.hl = btn:CreateTexture(nil, "BACKGROUND")
                btn.hl:SetAllPoints()
                Fill(btn.hl, C.GOLD, 0.16)
                btn.hl:Hide()
                btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.Text:SetPoint("LEFT", 5, 0)
                btn.Text:SetPoint("RIGHT", -5, 0)
                btn.Text:SetJustifyH("LEFT")
                btn:SetScript("OnEnter", function(b) b.hl:Show() end)
                btn:SetScript("OnLeave", function(b) b.hl:Hide() end)
                btn:SetScript("OnClick", function(b)
                    -- Read owner and callback BEFORE Hide(), which clears both.
                    local owner, callback, item = self.owner, self.onSelect, b.item
                    self:Hide()
                    if not item or item.disabled then return end
                    if owner and owner.SetValue then owner:SetValue(item.value, item.text) end
                    if callback then Util.Guard(callback, "dropdown", item.value, item.text) end
                end)
                self.buttons[i] = btn
            end
            if btn then
                local item = items[i + self.offset]
                if i <= shown and item then
                    btn.item = item
                    btn.Text:SetText(item.text or tostring(item.value))
                    local c = item.disabled and C.TEXT_DIM or C.TEXT
                    btn.Text:SetTextColor(c[1], c[2], c[3])
                    btn:Show()
                else
                    btn.item = nil
                    btn:Hide()
                end
            end
        end
        self:SetHeight(math.max(POPUP_ROW_H, shown * POPUP_ROW_H) + 6)
    end
    return popup
end

-- Opens the shared popup below `anchor` with `items` ({ value, text, disabled }).
function Widgets.ShowMenu(anchor, items, onSelect, width, owner)
    local p = GetPopup()
    if p:IsShown() and p.owner == (owner or anchor) then
        p:Hide()
        return
    end
    p.owner = owner or anchor
    p.onSelect = onSelect
    p.items = items or {}
    p.offset = 0
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    p:SetWidth(width or math.max(140, anchor:GetWidth()))
    p:Redraw()
    p:Show()
end

-- Context menu at the cursor.
function Widgets.ShowContextMenu(items, onSelect, width)
    local p = GetPopup()
    p:Hide()
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    p.owner = nil
    p.onSelect = onSelect
    p.items = items or {}
    p.offset = 0
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    p:SetWidth(width or 170)
    p:Redraw()
    p:Show()
end

function Widgets.CloseDropdowns()
    if popup then popup:Hide() end
end

function Widgets.CreateDropdown(parent, width, getItems, onSelect)
    local dd = Widgets.Frame("Button", nil, parent)
    dd:SetSize(width or 160, 22)
    Widgets.ApplyBackdrop(dd, {
        bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
        bgColor = { 0.02, 0.02, 0.03, 0.8 }, borderColor = { 1, 1, 1, 0.14 },
    })
    dd.Text = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dd.Text:SetPoint("LEFT", 8, 0)
    dd.Text:SetPoint("RIGHT", -18, 0)
    dd.Text:SetJustifyH("LEFT")
    dd.Text:SetWordWrap(false)

    local arrow = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    arrow:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3])

    dd.value = nil
    dd.placeholder = "-"
    dd.enabled = true

    function dd:SetValue(value, text)
        self.value = value
        if value ~= nil and text == nil then
            -- Look the label up so callers can set by value alone.
            for _, item in ipairs(getItems and getItems() or {}) do
                if item.value == value then text = item.text break end
            end
        end
        self.Text:SetText(text or (value ~= nil and tostring(value)) or self.placeholder)
        local c = (value == nil) and C.TEXT_DIM or C.TEXT
        self.Text:SetTextColor(c[1], c[2], c[3])
    end
    function dd:GetValue() return self.value end
    function dd:SetPlaceholder(t)
        self.placeholder = t
        if self.value == nil then self:SetValue(nil) end
    end
    function dd:SetEnabledState(on, reason)
        self.enabled = on and true or false
        self.disabledReason = (not on) and reason or nil
        arrow:SetShown(self.enabled)
    end

    dd:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.GOLD[1], C.GOLD[2], C.GOLD[3], 0.6)
        local tip = self.disabledReason or self.tooltipText
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.tooltipTitle then GameTooltip:AddLine(self.tooltipTitle, 1, 1, 1) end
            GameTooltip:AddLine(tip, 0.8, 0.82, 0.88, true)
            GameTooltip:Show()
        end
    end)
    dd:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 0.14)
        GameTooltip:Hide()
    end)
    dd:SetScript("OnClick", function(self)
        if not self.enabled then return end
        Widgets.ShowMenu(self, getItems and getItems() or {}, onSelect, self:GetWidth(), self)
    end)

    dd:SetValue(nil)
    return dd
end

-- ---------------------------------------------------------------------------
-- Column header row / column layout
-- ---------------------------------------------------------------------------
function Widgets.CreateHeaderRow(parent, columns, onSort)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(20)
    header.columns = columns
    header.labels = {}

    local line = Widgets.CreateSeparator(header, 10)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)

    for i = 1, #columns do
        local col = columns[i]
        local btn = CreateFrame("Button", nil, header)
        btn:SetHeight(18)
        btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.Text:SetPoint("LEFT", 4, 0)
        btn.Text:SetPoint("RIGHT", -4, 0)
        btn.Text:SetJustifyH(col.justify or "LEFT")
        btn.Text:SetText(col.text or "")
        btn.Text:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3])
        if onSort and col.key then
            btn:SetScript("OnClick", function() Util.Guard(onSort, "header", col.key) end)
            btn:SetScript("OnEnter", function(b) b.Text:SetTextColor(1, 1, 1) end)
            btn:SetScript("OnLeave", function(b) b.Text:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3]) end)
        else
            btn:EnableMouse(false)
        end
        header.labels[i] = btn
    end

    function header:Layout()
        Widgets.LayoutColumns(self, self.labels, self.columns, 8)
    end

    function header:SetSort(key, descending)
        for i = 1, #self.columns do
            local col = self.columns[i]
            local text = col.text or ""
            if col.key and col.key == key then text = text .. (descending and " v" or " ^") end
            self.labels[i].Text:SetText(text)
        end
    end

    header:SetScript("OnSizeChanged", function(self) self:Layout() end)
    return header
end

-- Fixed widths first; the single "*" column takes the rest. `reserve` keeps
-- space free on the right (the scroll bar).
function Widgets.LayoutColumns(parent, regions, columns, reserve)
    local total = (parent:GetWidth() or 0) - (reserve or 0)
    local fixed, starIndex = 0, nil
    for i = 1, #columns do
        if columns[i].width == "*" then starIndex = i else fixed = fixed + (columns[i].width or 60) end
    end
    local starWidth = math.max(40, total - fixed)
    local x = 0
    for i = 1, #columns do
        local w = (i == starIndex) and starWidth or (columns[i].width or 60)
        local r = regions[i]
        if r then
            r:ClearAllPoints()
            r:SetPoint("LEFT", parent, "LEFT", x + 4, 0)
            r:SetWidth(math.max(1, w - 8))
        end
        x = x + w
    end
end

-- Builds a list row with one FontString per column. Returns the row factory
-- used by CreateScrollList; `row.cols[i]` are the font strings.
function Widgets.ColumnRowFactory(columns)
    return function(list)
        local row = CreateFrame("Button", nil, list.content)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.cols = {}
        for i = 1, #columns do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH(columns[i].justify or "LEFT")
            fs:SetWordWrap(false)
            row.cols[i] = fs
        end
        row:SetScript("OnSizeChanged", function(self)
            Widgets.LayoutColumns(self, self.cols, columns)
        end)
        return row
    end
end

-- ---------------------------------------------------------------------------
-- Virtual scroll list
--
-- opts: rowHeight, createRow(list) -> row, updateRow(row, data, index),
--       onClick(row, data, button), onEnter(row, data), onLeave(row, data),
--       isSelected(data) -> bool
-- ---------------------------------------------------------------------------
function Widgets.CreateScrollList(parent, opts)
    opts = opts or {}
    local list = CreateFrame("Frame", nil, parent)
    list:SetClipsChildren(true)
    list.rowHeight = opts.rowHeight or 20
    list.data = {}
    list.offset = 0
    list.rows = {}

    list.content = CreateFrame("Frame", nil, list)
    list.content:SetPoint("TOPLEFT")
    list.content:SetPoint("BOTTOMRIGHT", -8, 0)

    local bar = CreateFrame("Slider", nil, list)
    bar:SetWidth(6)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)
    bar:SetOrientation("VERTICAL")
    bar:SetThumbTexture(WHITE)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    local thumb = bar:GetThumbTexture()
    if thumb then
        Fill(thumb, C.GOLD, 0.85)
        thumb:SetSize(6, 24)
    end
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.05)
    bar:SetScript("OnValueChanged", function(_, value)
        local v = math.floor(value + 0.5)
        if v ~= list.offset then
            list.offset = v
            list:Redraw()
        end
    end)
    list.scrollBar = bar

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        local minV, maxV = bar:GetMinMaxValues()
        bar:SetValue(math.max(minV, math.min(maxV, bar:GetValue() - delta * 3)))
    end)

    -- Empty-state text.
    list.emptyText = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    list.emptyText:SetPoint("TOPLEFT", 8, -8)
    list.emptyText:SetPoint("RIGHT", -16, 0)
    list.emptyText:SetJustifyH("LEFT")
    list.emptyText:SetTextColor(C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3])

    function list:SetEmptyText(t) self.emptyText:SetText(t or "") end

    function list:EnsureRows()
        local needed = math.ceil((self:GetHeight() or 0) / self.rowHeight)
        for i = #self.rows + 1, needed do
            local row = opts.createRow(self)
            row:SetHeight(self.rowHeight)
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(i - 1) * self.rowHeight)
            row:SetPoint("RIGHT", self.content, "RIGHT", 0, 0)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.highlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
            row.highlight:SetAllPoints()
            Fill(row.highlight, C.GOLD, 0.12)
            row.highlight:Hide()
            row:SetScript("OnEnter", function(r)
                r.highlight:Show()
                if opts.onEnter and r.data then Util.Guard(opts.onEnter, "list.onEnter", r, r.data) end
            end)
            row:SetScript("OnLeave", function(r)
                if not r.selected then r.highlight:Hide() end
                if opts.onLeave and r.data then Util.Guard(opts.onLeave, "list.onLeave", r, r.data) end
                GameTooltip:Hide()
            end)
            if row:GetObjectType() == "Button" then
                row:SetScript("OnClick", function(r, button)
                    if opts.onClick and r.data then Util.Guard(opts.onClick, "list.onClick", r, r.data, button) end
                end)
            end
            self.rows[i] = row
        end
        return needed
    end

    function list:SetData(data, keepPosition)
        self.data = data or {}
        if not keepPosition then self.offset = 0 end
        self:UpdateScrollRange()
        self:Redraw()
    end

    function list:UpdateScrollRange()
        local visible = math.floor((self:GetHeight() or 0) / self.rowHeight)
        local maxOffset = math.max(0, #self.data - visible)
        bar:SetMinMaxValues(0, maxOffset)
        if self.offset > maxOffset then self.offset = maxOffset end
        bar:SetValue(self.offset)
        bar:SetShown(maxOffset > 0)
        local t = bar:GetThumbTexture()
        if t and maxOffset > 0 then
            t:SetHeight(math.max(20, (self:GetHeight() or 100) * visible / math.max(1, #self.data)))
        end
    end

    function list:Redraw()
        local needed = self:EnsureRows()
        for i = 1, #self.rows do
            local row = self.rows[i]
            local dataIndex = self.offset + i
            local entry = self.data[dataIndex]
            if i <= needed and entry then
                row.data = entry
                row.dataIndex = dataIndex
                local c = (dataIndex % 2 == 0) and C.ROW_BG_ALT or C.ROW_BG
                Fill(row.bg, c)
                row.selected = opts.isSelected and opts.isSelected(entry) or false
                row.highlight:SetShown(row.selected)
                Util.Guard(opts.updateRow, "list.updateRow", row, entry, dataIndex)
                row:Show()
            else
                row.data = nil
                row:Hide()
            end
        end
        self.emptyText:SetShown(#self.data == 0)
    end

    list:SetScript("OnSizeChanged", function(self)
        self:UpdateScrollRange()
        self:Redraw()
    end)
    return list
end

-- ---------------------------------------------------------------------------
-- Standalone window
-- ---------------------------------------------------------------------------
function Widgets.CreateWindow(globalName, titleText, width, height)
    local win = Widgets.Frame("Frame", globalName, UIParent)
    win:SetSize(width or 500, height or 400)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    win:Hide()

    local saved = globalName and ERF.db and ERF.db.ui.windows[globalName]
    if saved and saved.point then
        win:SetPoint(saved.point, UIParent, saved.relPoint or "CENTER", saved.x or 0, saved.y or 0)
    else
        win:SetPoint("CENTER")
    end

    Widgets.StyleWindow(win)

    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(30)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() win:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        if globalName and ERF.db then
            local point, _, relPoint, x, y = win:GetPoint()
            ERF.db.ui.windows[globalName] = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    local underline = Widgets.CreateSeparator(bar, 10)
    underline:SetPoint("BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", 0, 0)

    win.Title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.Title:SetPoint("LEFT", 12, 0)
    win.Title:SetText(titleText or "")
    win.Title:SetTextColor(C.GOLD[1], C.GOLD[2], C.GOLD[3])

    local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
    close:SetSize(26, 26)
    close:SetPoint("RIGHT", -3, 0)
    close:SetScript("OnClick", function() win:Hide() end)

    win.Body = CreateFrame("Frame", nil, win)
    win.Body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 10, -10)
    win.Body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -11, 11)
    win:SetScript("OnHide", function() Widgets.CloseDropdowns() end)

    if globalName then table.insert(UISpecialFrames, globalName) end
    return win
end

-- ---------------------------------------------------------------------------
-- Confirmation and text prompt (StaticPopup based)
-- ---------------------------------------------------------------------------
local pendingConfirm, pendingPrompt

StaticPopupDialogs["EASYRAIDFOREVER_CONFIRM"] = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
        local action = pendingConfirm
        pendingConfirm = nil
        if action then Util.Guard(action, "Widgets.Confirm") end
    end,
    OnCancel = function() pendingConfirm = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function Widgets.Confirm(message, action)
    pendingConfirm = action
    StaticPopup_Show("EASYRAIDFOREVER_CONFIRM", message)
end

local function PromptEditBox(dialog)
    return dialog.EditBox or dialog.editBox or (dialog.GetEditBox and dialog:GetEditBox())
end

local function AcceptPrompt(dialog)
    local cb = pendingPrompt
    pendingPrompt = nil
    local eb = PromptEditBox(dialog)
    local text = eb and eb:GetText() or ""
    if cb then Util.Guard(cb, "Widgets.Prompt", text) end
end

StaticPopupDialogs["EASYRAIDFOREVER_PROMPT"] = {
    text = "%s",
    button1 = OKAY or "OK",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 0,
    editBoxWidth = 350,
    OnShow = function(self, data)
        local eb = PromptEditBox(self)
        if eb then
            eb:SetText(data or "")
            eb:HighlightText()
            eb:SetFocus()
            eb.erfAcceptsLinks = true
        end
    end,
    OnHide = function(self)
        local eb = PromptEditBox(self)
        if eb then eb.erfAcceptsLinks = nil end
    end,
    OnAccept = function(self) AcceptPrompt(self) end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        AcceptPrompt(dialog)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    OnCancel = function() pendingPrompt = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Shift-clicking an item inserts its link into the chat box. When one of our
-- edit boxes that takes item links has the keyboard focus, insert it there.
if hooksecurefunc and type(ChatEdit_InsertLink) == "function" then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focus and focus.erfAcceptsLinks and type(link) == "string" then focus:Insert(link) end
    end)
end

-- Asks for one line of text. onAccept(text).
function Widgets.Prompt(message, default, onAccept)
    pendingPrompt = onAccept
    StaticPopup_Show("EASYRAIDFOREVER_PROMPT", message, nil, default)
end

-- ---------------------------------------------------------------------------
-- Item info. Item data arrives asynchronously; the first call requests it and
-- every UI refreshes once GET_ITEM_INFO_RECEIVED comes in.
-- Returns name, coloredName, icon, quality (placeholders while loading).
-- ---------------------------------------------------------------------------
local itemEventRegistered = false
function Widgets.Item(itemId)
    local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemId)
    if not icon and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(itemId) end
    if name then
        local hex = C_Item.GetItemQualityColor and select(4, C_Item.GetItemQualityColor(quality or 1))
        return name, hex and ("|c" .. hex .. name .. "|r") or name, icon or 134400, quality
    end
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemId) end
    if not itemEventRegistered then
        itemEventRegistered = true
        ERF:RegisterEventHandler("GET_ITEM_INFO_RECEIVED", function()
            if ERF.UI then ERF.UI.RefreshSoon() end
            ERF:Notify("ITEMS")
        end)
    end
    local text = string.format(L["Item %d (loading...)"], itemId)
    return text, "|cff8c94a6" .. text .. "|r", icon or 134400, nil
end

function Widgets.ItemTooltip(owner, itemId, extraLines)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemId)
    for _, l in ipairs(extraLines or {}) do
        if l[1] then GameTooltip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1, true) end
    end
    GameTooltip:Show()
end

-- Prints a failed action's reason (the second return of most model calls).
function Widgets.Report(ok, reason)
    if not ok and reason then Util.Print(Util.CHAT_RED .. tostring(reason) .. "|r") end
    return ok
end
