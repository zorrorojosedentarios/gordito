-- Gordito v2.1 - Protege tus festines
-- Autor: zorrorojo (guild Sedentarios)

local f = CreateFrame("Frame")

-- ====== CONFIGURACION ======
local FEAST_NAMES = {
    ["Festín de pescado"]=true, ["Fish Feast"]=true,
    ["Gran festín"]=true,       ["Great Feast"]=true,
    ["Festín abundante"]=true,  ["Bountiful Feast"]=true,
}
local EATING_BUFF_IDS = {
    [45548]=true, -- Comida (ID pedido por usuario)
    [57073]=true, -- Beber (ID pedido por usuario)
}
-- IDs de bufo final (1 hora) para proteccion
local WELL_FED_IDS = { [57294]=true, [57371]=true, [57139]=true, [57399]=true }
local FEAST_PLACE_IDS = { [57426]=true, [66476]=true } -- 57073 quitado de aqui por conflicto
local EATING_CAST_NAMES = {
    ["Alimentándose"]=true, ["Food"]=true, ["Eating"]=true,
    ["Comiendo"]=true, ["Beber"]=true, ["Drink"]=true, ["Bebiendo"]=true,
}
local MIN_BUFF_DURATION = 30
local ANNOUNCE_COOLDOWN = 8
local debugMode = false  -- /gordito debug para activar

-- ====== CONFIGURACION DEFAULT ======
local DEFAULT_SETTINGS = {
    enabled = true,
    announce = true,
    warnModes = { ["CHAT"] = true, ["ALERTA"] = false, ["SAY"] = false, ["GLOTON"] = true },
    clickLow = 2,
    clickHigh = 5,
    startingDebounce = 7,
    announceCooldown = 8,
    msgLow = "[Gordito] %n: %c CLICS AL FESTIN!",
    msgHigh = "[Gordito] %n PARA DE DAR CLICK!!! (comiste %c veces)",
    minimapPos = 45,
}

-- ====== ESTADO ======
local lastAnnounce   = 0
local lastPlacer     = "Nadie aun"
local eatCounts      = {}  -- veces que alguien completo comer (buff aplicado)
local clickCounts    = {}  -- veces que alguien INICIO el cast de comer (cada clic)
local totalEats    = 0
local lastPlacedTime = 0
local lastStartingTime = 0
local auraLostTime   = {}
local personLastAnnounce = {} -- Cooldown por persona para evitar spam excesivo pero permitir avisos seguidos

-- Nueva funcion para obtener todos los canales activos
local function GetActiveChannels()
    local channels = {}
    if not GorditoDB or not GorditoDB.warnModes then return {} end
    
    local inRaid = IsInRaid()
    local inParty = GetNumPartyMembers() > 0 or inRaid

    if GorditoDB.warnModes["CHAT"] then
        table.insert(channels, inRaid and "RAID" or (inParty and "PARTY" or "SAY"))
    end
    if GorditoDB.warnModes["ALERTA"] and inRaid then
        table.insert(channels, (IsRaidLeader() or IsRaidOfficer()) and "RAID_WARNING" or "RAID")
    end
    if GorditoDB.warnModes["SAY"] then
        table.insert(channels, "SAY")
    end
    
    return channels
end

-- ====== EVENTOS ======
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_SPELLCAST_START")   -- proteccion propia
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") -- deteccion de placement (alternativa a CLEU)
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("CHAT_MSG_RAID")
f:RegisterEvent("CHAT_MSG_RAID_LEADER")
f:RegisterEvent("CHAT_MSG_PARTY")
f:RegisterEvent("CHAT_MSG_SAY")
f:RegisterEvent("RAID_ROSTER_UPDATE")
f:RegisterEvent("PARTY_MEMBERS_CHANGED")

-- ====== SCAN DE BUFFS ======
local function CheckUnitHasFeastBuff(unit)
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellId = UnitAura(unit, i)
        if not name then break end
        -- Ahora solo revisamos WELL_FED_IDS (el bufo final de 1 hora)
        if WELL_FED_IDS[spellId] then return true end
    end
    return false
end

local function ScanForMissing()
    local missing, total = {}, 0
    if IsInRaid() then
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            if name then
                total = total + 1
                if not CheckUnitHasFeastBuff("raid"..i) then
                    table.insert(missing, name)
                end
            end
        end
    elseif GetNumPartyMembers() > 0 then
        total = total + 1
        if not CheckUnitHasFeastBuff("player") then
            table.insert(missing, UnitName("player") or "?")
        end
        for i = 1, GetNumPartyMembers() do
            total = total + 1
            if not CheckUnitHasFeastBuff("party"..i) then
                local n = UnitName("party"..i)
                if n then table.insert(missing, n) end
            end
        end
    end
    table.sort(missing)
    return missing, total
end

local function SendMissingToChannel(channel)
    local missing, total = ScanForMissing()
    if #missing == 0 then
        SendChatMessage("[Gordito] ¡Todos comieron del festín! ("..total.."/"..total..")", channel)
        return
    end
    local header = "[Gordito] Faltan comer ("..#missing.."/"..total.."): "
    local chunk  = header
    for i, name in ipairs(missing) do
        local sep = (i < #missing) and ", " or "."
        local add = name..sep
        if (#chunk + #add) > 250 then
            SendChatMessage(chunk, channel)
            chunk = "[Gordito] ..." .. add
        else
            chunk = chunk..add
        end
    end
    if #chunk > 0 then SendChatMessage(chunk, channel) end
end

-- ====== FORWARD DECLARATIONS ======
local UpdateUI, UpdateMissingList
local mainFrame, statusText, placerText, statsText, toggleBtn
local missingHeaderText, scrollFrame, scrollChild, scrollBar
local missingRows = {}

-- ====== VENTANA PRINCIPAL (270x480, layout Y absolutos desde TOP) ======
mainFrame = CreateFrame("Frame", "GorditoMainFrame", UIParent)
mainFrame:SetSize(560, 500)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
tinsert(UISpecialFrames, "GorditoMainFrame") -- Permite cerrar con ESC
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop",  mainFrame.StopMovingOrSizing)
mainFrame:SetFrameStrata("MEDIUM")
mainFrame:Hide()

-- En WotLK 3.3.5 se usa SetBackdrop() en vez de templates
mainFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile     = true, tileSize = 32, edgeSize = 32,
    insets   = { left = 11, right = 12, top = 12, bottom = 11 }
})

local titleBar = mainFrame:CreateTexture(nil, "ARTWORK")
titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleBar:SetWidth(290); titleBar:SetHeight(64)
titleBar:SetPoint("TOP", 0, 12)

local titleText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", mainFrame, "TOP", 0, -5)
titleText:SetText("|cff00ff00Gordito|r - Festines")

local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -3, -3)
closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

-- Seccion superior: Y absolutos desde TOP del frame
-- y=-28: Estado
-- Seccion superior Izquierda
statusText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -35)
statusText:SetWidth(240); statusText:SetJustifyH("LEFT")

placerText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
placerText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -55)
placerText:SetWidth(240); placerText:SetJustifyH("LEFT")

statsText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statsText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -70)
statsText:SetWidth(240); statsText:SetJustifyH("LEFT")

toggleBtn = CreateFrame("Button", "GorditoToggleButton", mainFrame, "GameMenuButtonTemplate")
toggleBtn:SetSize(240, 24)
toggleBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -90)
toggleBtn:SetScript("OnClick", function()
    if not GorditoDB then return end
    GorditoDB.enabled = not GorditoDB.enabled
    UpdateMinimapIcon()
    UpdateUI()
    local estado = GorditoDB.enabled and "|cff00ff00ACTIVADA|r" or "|cffff0000DESACTIVADA|r"
    print("|cff00ff00Gordito|r: Proteccion " .. estado)
end)

-- Contenedor para las 3 opciones con palomita (CheckButtons)
local checkButtons = {}
local function CreateWarnCheck(id, text, xOff)
    -- Crear el cuadro de la palomita
    local cb = CreateFrame("CheckButton", "GorditoCheck_"..id, mainFrame, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", xOff, -108)
    cb:SetSize(26, 26) -- Forzamos tamaño cuadrado
    
    -- REDUCIR AREA DE CLIC: Evita que el area invisible a la derecha tape otros botones
    -- El 4to parametro de SetHitRectInsets recorta el area clickeable desde la derecha
    cb:SetHitRectInsets(0, 0, 0, 0) 
    cb:SetWidth(26) -- Asegura que el ancho sea solo el del cuadro

    -- Ocultamos el texto interno del boton para que no sea clickeable
    local internalText = _G[cb:GetName().."Text"]
    if internalText then 
        internalText:SetText("") 
        internalText:Hide()
    end
    
    -- Creamos un texto independiente (no clickeable) al lado
    local label = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 0, 1)
    label:SetText(text)

    cb:SetScript("OnClick", function(self)
        if not GorditoDB or not GorditoDB.warnModes then return end
        GorditoDB.warnModes[id] = self:GetChecked()
        local color = (id == "ALERTA") and "|cffff4400" or (id == "SAY" and "|cffffff00" or "|cff00ffff")
        local estado = self:GetChecked() and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        print("|cff00ff00Gordito|r: "..color..id.."|r está ahora "..estado)
    end)
    checkButtons[id] = cb
end

CreateWarnCheck("CHAT", "Banda", 20)
CreateWarnCheck("ALERTA", "Alerta", 85)
CreateWarnCheck("SAY", "Decir", 150)
CreateWarnCheck("GLOTON", "Glotón", 215)

-- Separador Vertical
local vDiv = mainFrame:CreateTexture(nil, "ARTWORK")
vDiv:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
vDiv:SetSize(460, 2)
vDiv:SetPoint("CENTER", mainFrame, "LEFT", 280, 0)
vDiv:SetRotation(math.pi / 2)
vDiv:SetAlpha(0.6)

-- y=-136: Divisor 1
local div1 = mainFrame:CreateTexture(nil, "ARTWORK")
div1:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
div1:SetSize(250, 16)
div1:SetPoint("TOP", mainFrame, "TOP", 0, -136)

-- Seccion de Configuracion de Clics y Tiempos
local function CreateClickInput(labelStr, dbKey, x, y, width)
    local lbl = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x, y)
    lbl:SetText(labelStr)

    local eb = CreateFrame("EditBox", "GorditoEB_"..dbKey, mainFrame, "InputBoxTemplate")
    eb:SetSize(width or 25, 18)
    eb:SetPoint("LEFT", lbl, "RIGHT", 5, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(3)
    eb:SetScript("OnTextChanged", function(self)
        if GorditoDB then GorditoDB[dbKey] = tonumber(self:GetText()) or 1 end
    end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

-- y=-145: Umbrales de clics
-- y=-160: Umbrales
clickLowEB  = CreateClickInput("Aviso:", "clickLow", 20, -165, 25)
clickHighEB = CreateClickInput("Alerta:", "clickHigh", 155, -165, 25)

-- y=-190: Tiempos
debounceEB  = CreateClickInput("Poner(s):", "startingDebounce", 20, -190, 30)
announceCooldownEB = CreateClickInput("Grito(s):", "announceCooldown", 155, -190, 30)

-- Editores de Texto para los anuncios
local function CreateTextInput(labelStr, dbKey, xOff, yOff)
    local lbl = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", xOff, yOff)
    lbl:SetText(labelStr)

    local eb = CreateFrame("EditBox", "GorditoEB_"..dbKey, mainFrame, "InputBoxTemplate")
    eb:SetSize(240, 20)
    eb:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", xOff, yOff - 15)
    eb:SetAutoFocus(false)
    eb:SetScript("OnTextChanged", function(self)
        if GorditoDB then GorditoDB[dbKey] = self:GetText() end
    end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

msgLowEB  = CreateTextInput("Mensaje Aviso (%n=nombre):", "msgLow", 20, -225)
msgHighEB = CreateTextInput("Mensaje Alerta (%n=nombre):", "msgHigh", 20, -275)

-- Seccion inferior
-- y=-290: Header "Faltan comer"
-- y=-320: Headers de las listas
greedyHeaderText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
greedyHeaderText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 295, -35)
greedyHeaderText:SetText("|cffff4400Glotones y Clics:|r")

missingHeaderText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
missingHeaderText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 295, -245)
missingHeaderText:SetText("|cffffff00Faltan comer:|r")

-- Boton Rastrear (al lado de Faltan comer)
local btnTrack = CreateFrame("Button", "GorditoTrackMissing", mainFrame, "GameMenuButtonTemplate")
btnTrack:SetSize(80, 22)
btnTrack:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -25, -242)
btnTrack:SetText("Rastrear")
btnTrack:SetScript("OnClick", function()
    UpdateMissingList()
    print("|cff00ff00Gordito|r: Lista de faltantes actualizada.")
end)

-- Botones (Al pie de la derecha)
local btnChatBanda = CreateFrame("Button", "GorditoAnnounceBanda", mainFrame, "GameMenuButtonTemplate")
btnChatBanda:SetSize(115, 22)
btnChatBanda:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 295, -465)
btnChatBanda:SetText("Chat Banda")
btnChatBanda:SetScript("OnClick", function()
    if not IsInRaid() and GetNumPartyMembers() == 0 then
        print("|cff00ff00Gordito|r: No estas en grupo."); return
    end
    SendMissingToChannel(IsInRaid() and "RAID" or "PARTY")
end)

local btnAlertaBanda = CreateFrame("Button", "GorditoAnnounceAlerta", mainFrame, "GameMenuButtonTemplate")
btnAlertaBanda:SetSize(115, 22)
btnAlertaBanda:SetPoint("LEFT", btnChatBanda, "RIGHT", 10, 0)
btnAlertaBanda:SetText("Alerta de Banda")
btnAlertaBanda:SetScript("OnClick", function()
    if not IsInRaid() then
        print("|cff00ff00Gordito|r: Debes estar en banda."); return
    end
    if not IsRaidLeader() and not IsRaidOfficer() then
        print("|cff00ff00Gordito|r: Solo lider/oficial puede enviar Alerta de Banda."); return
    end
    SendMissingToChannel("RAID_WARNING")
end)

-- Boton Reset
local btnReset = CreateFrame("Button", "GorditoReset", mainFrame, "GameMenuButtonTemplate")
btnReset:SetSize(80, 22)
btnReset:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 15, 12)
btnReset:SetText("Reset")
btnReset:SetScript("OnClick", function()
    if GorditoDB then
        for k, v in pairs(DEFAULT_SETTINGS) do
            if type(v) == "table" then
                GorditoDB[k] = {}
                for k2, v2 in pairs(v) do GorditoDB[k][k2] = v2 end
            else
                GorditoDB[k] = v
            end
        end
        print("|cff00ff00Gordito|r: Valores reseteados a defecto.")
        UpdateUI()
    end
end)

-- Listas
-- Lista 2: Glotones (Derecha, Mitad Superior)
greedyScroll = CreateFrame("ScrollFrame", "GorditoGreedyScroll", mainFrame)
greedyScroll:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     295, -60)
greedyScroll:SetPoint("BOTTOMRIGHT", mainFrame, "TOPLEFT",     535, -235)

greedyScrollChild = CreateFrame("Frame")
greedyScrollChild:SetSize(210, 1)
greedyScroll:SetScrollChild(greedyScrollChild)

local greedyRows = {}
for i = 1, 40 do
    local row = greedyScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row:SetPoint("TOPLEFT", greedyScrollChild, "TOPLEFT", 4, -(i-1)*16)
    row:SetWidth(200); row:SetJustifyH("LEFT"); row:Hide()
    greedyRows[i] = row
end

greedyScrollBar = CreateFrame("Slider", "GorditoGreedyScrollBar", mainFrame, "UIPanelScrollBarTemplate")
greedyScrollBar:SetPoint("TOPLEFT",    greedyScroll, "TOPRIGHT",    4, -16)
greedyScrollBar:SetPoint("BOTTOMLEFT", greedyScroll, "BOTTOMRIGHT", 4,  16)
greedyScrollBar:SetMinMaxValues(0, 1); greedyScrollBar:SetValueStep(1)
greedyScrollBar:SetScript("OnValueChanged", function(self, val)
    if greedyScroll then greedyScroll:SetVerticalScroll(val * 16) end
end)
greedyScrollBar:SetValue(0)
greedyScroll:SetScript("OnMouseWheel", function(self, delta)
    local mn, mx = greedyScrollBar:GetMinMaxValues()
    greedyScrollBar:SetValue(math.max(mn, math.min(mx, greedyScrollBar:GetValue() - delta)))
end)

-- Lista 1: Faltan Comer (Derecha, Mitad Inferior)
scrollFrame = CreateFrame("ScrollFrame", "GorditoScrollFrame", mainFrame)
scrollFrame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     295, -270)
scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "TOPLEFT",     535, -455)

scrollChild = CreateFrame("Frame")
scrollChild:SetSize(210, 1)
scrollFrame:SetScrollChild(scrollChild)

for i = 1, 40 do
    local row = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -(i-1)*16)
    row:SetWidth(200); row:SetJustifyH("LEFT"); row:Hide()
    missingRows[i] = row
end

scrollBar = CreateFrame("Slider", "GorditoScrollBar", mainFrame, "UIPanelScrollBarTemplate")
scrollBar:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    4, -16)
scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4,  16)
scrollBar:SetMinMaxValues(0, 1); scrollBar:SetValueStep(1)
scrollBar:SetScript("OnValueChanged", function(self, val)
    if scrollFrame then scrollFrame:SetVerticalScroll(val * 16) end
end)
scrollBar:SetValue(0)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local mn, mx = scrollBar:GetMinMaxValues()
    scrollBar:SetValue(math.max(mn, math.min(mx, scrollBar:GetValue() - delta)))
end)

-- ====== FUNCIONES UI ======
UpdateMissingList = function()
    local missing, total = ScanForMissing()
    local count = #missing
    missingHeaderText:SetText("|cffffff00Faltan ("..count.."/"..total.."):|r")
    for i = 1, 40 do
        if i <= count then
            missingRows[i]:SetText("|cffff6060• "..missing[i].."|r"); missingRows[i]:Show()
        else
            missingRows[i]:Hide()
        end
    end
    scrollChild:SetHeight(math.max(1, count * 16))
    local mx = math.max(0, count - 10)
    scrollBar:SetMinMaxValues(0, mx); scrollBar:SetValue(math.min(scrollBar:GetValue(), mx))
    if mx > 0 then scrollBar:Show() else scrollBar:Hide() end
end

local function UpdateGreedyList()
    local entries = {}
    for name, n in pairs(clickCounts) do
        if n > 1 then table.insert(entries, "|cffff8800• "..name.."|r ("..n.." clics)") end
    end
    for name, n in pairs(eatCounts) do
        if n > 1 then table.insert(entries, "|cffff4400• "..name.."|r ("..n.." comidas)") end
    end
    local count = #entries
    greedyHeaderText:SetText("|cffff4400Glotones ("..count.."):|r")
    for i = 1, 40 do
        if i <= count then
            greedyRows[i]:SetText(entries[i]); greedyRows[i]:Show()
        else
            greedyRows[i]:Hide()
        end
    end
    greedyScrollChild:SetHeight(math.max(1, count * 16))
    local mx = math.max(0, count - 10)
    greedyScrollBar:SetMinMaxValues(0, mx); greedyScrollBar:SetValue(math.min(greedyScrollBar:GetValue(), mx))
    if mx > 0 then greedyScrollBar:Show() else greedyScrollBar:Hide() end
end

UpdateUI = function()
    if not GorditoDB then return end
    if GorditoDB.enabled then
        statusText:SetText("|cff00ff00Proteccion: ACTIVA|r")
        toggleBtn:SetText("Desactivar Proteccion")
    else
        statusText:SetText("|cffff0000Proteccion: INACTIVA|r")
        toggleBtn:SetText("Activar Proteccion")
    end

    -- Actualizar las 3 palomitas (independientes)
    if checkButtons.CHAT then checkButtons.CHAT:SetChecked(GorditoDB.warnModes["CHAT"]) end
    if checkButtons.ALERTA then checkButtons.ALERTA:SetChecked(GorditoDB.warnModes["ALERTA"]) end
    if checkButtons.SAY then checkButtons.SAY:SetChecked(GorditoDB.warnModes["SAY"]) end
    if checkButtons.GLOTON then checkButtons.GLOTON:SetChecked(GorditoDB.warnModes["GLOTON"]) end

    -- Actualizar EditBoxes
    if clickLowEB then clickLowEB:SetText(tostring(GorditoDB.clickLow or 2)) end
    if clickHighEB then clickHighEB:SetText(tostring(GorditoDB.clickHigh or 5)) end
    if debounceEB then debounceEB:SetText(tostring(GorditoDB.startingDebounce or 7)) end
    if announceCooldownEB then announceCooldownEB:SetText(tostring(GorditoDB.announceCooldown or 8)) end
    if msgLowEB then msgLowEB:SetText(GorditoDB.msgLow or "") end
    if msgHighEB then msgHighEB:SetText(GorditoDB.msgHigh or "") end

    placerText:SetText("Festin de: |cffffff00"..lastPlacer.."|r")
    statsText:SetText("Comidas totales: |cffffff00"..totalEats.."|r")
    
    UpdateMissingList()
    UpdateGreedyList()
end

-- ====== BOTON MINIMAPA ======
local minimapBtn = CreateFrame("Button", "GorditoMinimapButton", Minimap)
minimapBtn:SetSize(31, 31); minimapBtn:SetFrameLevel(8); minimapBtn:SetToplevel(true)
minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local btnIcon = minimapBtn:CreateTexture(nil, "BACKGROUND")
btnIcon:SetTexture("Interface\\Icons\\INV_Misc_Food_95")
btnIcon:SetSize(20, 20); btnIcon:SetPoint("CENTER", 0, 0)

local btnBorder = minimapBtn:CreateTexture(nil, "OVERLAY")
btnBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
btnBorder:SetSize(53, 53); btnBorder:SetPoint("TOPLEFT", 0, 0)

local function UpdateMinimapIcon()
    if not GorditoDB then return end
    btnIcon:SetVertexColor(GorditoDB.enabled and 1 or 0.5,
                           GorditoDB.enabled and 1 or 0.5,
                           GorditoDB.enabled and 1 or 0.5)
end

local function MoveMinimapButton()
    local angle = (GorditoDB and GorditoDB.minimapPos) or 45
    minimapBtn:SetPoint("TOPLEFT", Minimap, "TOPLEFT",
        52-(80*cos(angle)), (80*sin(angle))-52)
end

minimapBtn:SetMovable(true)
minimapBtn:RegisterForDrag("LeftButton")
minimapBtn:SetScript("OnDragStart", function(self)
    if not GorditoDB then return end
    self:StartMoving()
    self:SetScript("OnUpdate", function()
        local xpos, ypos = GetCursorPosition()
        local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
        GorditoDB.minimapPos = math.deg(math.atan2(
            ypos/Minimap:GetEffectiveScale()-ymin-70,
            xmin-xpos/Minimap:GetEffectiveScale()+70))
        MoveMinimapButton()
    end)
end)
minimapBtn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing(); self:SetScript("OnUpdate", nil)
end)
minimapBtn:SetScript("OnClick", function()
    if mainFrame:IsShown() then mainFrame:Hide()
    else UpdateUI(); mainFrame:Show() end
end)
minimapBtn:SetScript("OnEnter", function(self)
    if not GorditoDB then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Gordito", 0, 1, 0)
    GameTooltip:AddLine("Proteccion: "..(GorditoDB.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    GameTooltip:AddLine("Click para abrir panel", 1, 1, 1)
    GameTooltip:AddLine("Arrastra para mover", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)
minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ====== LOGICA ======
local function IsAlreadyEating()
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i)
        if not name then break end
        if EATING_BUFF_IDS[spellId] or WELL_FED_IDS[spellId] or EATING_CAST_NAMES[name] then 
            return true 
        end
    end
    return false
end

local function GetFeastTime()
    for i = 1, 40 do
        local name, _, _, _, _, _, expTime, _, _, _, spellId = UnitAura("player", i)
        if not name then break end
        if EATING_BUFF_IDS[spellId] or WELL_FED_IDS[spellId] then 
            return (expTime or 0) - GetTime() 
        end
    end
    return 0
end

local function IsMousingOverFeast()
    local text = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
    if not text then return false end
    return FEAST_NAMES[text] ~= nil
end

local function SendToGroup(msg)
    if not GorditoDB or not GorditoDB.announce then return end
    local now = GetTime()
    local coo = tonumber(GorditoDB.announceCooldown) or 8
    if now - lastAnnounce < coo then return end
    lastAnnounce = now
    
    for _, channel in ipairs(GetActiveChannels()) do
        SendChatMessage(msg, channel)
    end
end

local function OnFeastPlaced(placer)
    if not placer or placer == "" then placer = "Alguien" end
    -- Solo resetear si es un placer distinto o ha pasado mucho tiempo (evitar dobles triggers)
    local now = GetTime()
    if lastPlacer == placer and (now - lastPlacedTime < 2) then return end
    
    lastPlacer   = placer
    lastPlacedTime = now
    eatCounts    = {}
    clickCounts  = {}
    totalEats    = 0
    auraLostTime = {}
    personLastAnnounce = {}

    -- Siempre visible localmente
    UIErrorsFrame:AddMessage(
        "|cff00ff00[GORDITO] "..placer.." puso un festin! Come ahora!|r",
        0, 1, 0, 1, 10)
    print("|cff00ff00[Gordito]|r |cffffff00>>> "..placer.." puso un festin! <<<|r")

    -- Aviso al grupo (siempre, sin cooldown)
    if GorditoDB and GorditoDB.announce then
        for _, channel in ipairs(GetActiveChannels()) do
            SendChatMessage("[Gordito] >>> "..placer.." puso un festin! <<<.", channel)
        end
        lastAnnounce = 0 -- Resetear cooldown global para permitir avisos inmediatos
    end

    if mainFrame:IsShown() then UpdateUI() end
end

local function OnFeastStarting(placer)
    local now = GetTime()
    local deb = tonumber(GorditoDB.startingDebounce) or 7
    if now - lastStartingTime < deb then return end
    lastStartingTime = now

    lastPlacer = placer or "Alguien"
    UIErrorsFrame:AddMessage("|cffffff00[GORDITO] "..lastPlacer.." esta poniendo un festin...|r", 1, 1, 0, 1, 5)
    print("|cff00ff00[Gordito]|r |cffffff00"..lastPlacer.." esta poniendo un festin...|r")
    
    -- Aviso al grupo
    if GorditoDB and GorditoDB.announce then
        for _, channel in ipairs(GetActiveChannels()) do
            SendChatMessage("[Gordito] "..lastPlacer.." esta poniendo un festin...", channel)
        end
    end
    if mainFrame:IsShown() then UpdateUI() end -- Actualizar panel de inmediato
end

local function AnnounceToRW(name, count)
    if not GorditoDB or not GorditoDB.announce then return end
    
    local now = GetTime()
    local coo = tonumber(GorditoDB.announceCooldown) or 8
    local high = tonumber(GorditoDB.clickHigh) or 5
    
    -- Si count >= high, es un aviso de "Gloton", respetamos ese toggle
    if count and count >= high and not GorditoDB.warnModes["GLOTON"] then return end
    
    -- Cooldown inteligente: 1s para spam de clics exagerados, 8s para lo demas
    local actualCoo = (count and count >= high) and 1 or coo
    if now - (personLastAnnounce[name] or 0) < actualCoo then return end
    
    personLastAnnounce[name] = now
    lastAnnounce = now

    local rawMsg = GorditoDB.msgHigh or "[Gordito] %n PARA DE DAR CLICK!!! (comiste %c veces)"
    local msg = rawMsg:gsub("%%n", name):gsub("%%c", tostring(count or ""))
    
    -- 1. Enviar SIEMPRE por CHAT normal (Banda/Grupo) si CHAT esta activo
    if GorditoDB.warnModes["CHAT"] then
        local inRaid = IsInRaid()
        local inParty = GetNumPartyMembers() > 0 or inRaid
        local channel = inRaid and "RAID" or (inParty and "PARTY" or "SAY")
        SendChatMessage(msg, channel)
    end
    
    -- 2. Enviar por SAY si esta activo
    if GorditoDB.warnModes["SAY"] then
        SendChatMessage(msg, "SAY")
    end

    -- 3. Enviar por ALERTA de banda SI esta activa y eres lider/officer
    if GorditoDB.warnModes["ALERTA"] and IsInRaid() and (IsRaidLeader() or IsRaidOfficer()) then
        SendChatMessage(msg, "RAID_WARNING")
    end
end

local function OnGreedyClicker(name, clicks)
    -- Local
    UIErrorsFrame:AddMessage("|cffff8800[GORDITO] "..name.." - "..clicks.." clics!|r", 1, 0.5, 0, 1, 8)
    print("|cff00ff00[Gordito]|r |cffff8800"..name.." dio "..clicks.." clics!|r")

    if GorditoDB and GorditoDB.announce and GorditoDB.warnModes["GLOTON"] then
        local low = tonumber(GorditoDB.clickLow) or 2
        local high = tonumber(GorditoDB.clickHigh) or 5
        
        if clicks == low then
            local now = GetTime()
            local coo = tonumber(GorditoDB.announceCooldown) or 8
            if now - (personLastAnnounce[name] or 0) >= coo then
                personLastAnnounce[name] = now
                lastAnnounce = now
                local rawMsg = GorditoDB.msgLow or "[Gordito] %n: %c CLICS AL FESTIN!"
                local msg = rawMsg:gsub("%%n", name):gsub("%%c", clicks)
                for _, channel in ipairs(GetActiveChannels()) do
                    if channel ~= "RAID_WARNING" then SendChatMessage(msg, channel) end
                end
            end
        elseif clicks >= high then
            AnnounceToRW(name, clicks)
        end
    end
    if mainFrame:IsShown() then UpdateUI() end
end

local function OnGreedyEater(name, count)
    UIErrorsFrame:AddMessage("|cffff4400[GORDITO] "..name.." ya comio "..count.." veces!|r", 1, 0.3, 0, 1, 10)
    print("|cff00ff00[Gordito]|r |cffff4400"..name.." lleva "..count.." comidas!|r")

    if GorditoDB and GorditoDB.announce and GorditoDB.warnModes["GLOTON"] then
        local high = tonumber(GorditoDB.clickHigh) or 5
        -- Usar directamente AnnounceToRW que ahora maneja todos los canales (Chat, Say y Alerta)
        if count >= high then 
            AnnounceToRW(name, count) 
        end
    end
    if mainFrame:IsShown() then UpdateUI() end
end

-- ====== EVENTOS ======
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if not GorditoDB then GorditoDB = {} end
        for k, v in pairs(DEFAULT_SETTINGS) do
            if GorditoDB[k] == nil then
                if type(v) == "table" then
                    GorditoDB[k] = {}
                    for k2, v2 in pairs(v) do GorditoDB[k][k2] = v2 end
                else
                    GorditoDB[k] = v
                end
            end
        end
        -- Asegurar que las claves de warnModes esten todas
        for k2, v2 in pairs(DEFAULT_SETTINGS.warnModes) do
            if GorditoDB.warnModes[k2] == nil then GorditoDB.warnModes[k2] = v2 end
        end

        MoveMinimapButton(); UpdateMinimapIcon()
        local s  = GorditoDB.enabled  and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        local as = GorditoDB.announce and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        print("|cff00ff00Gordito v2.1|r cargado! Proteccion ["..s.."] Avisos ["..as.."]")
        print("Comandos: |cffffff00/gordito|r (toggle) | |cffffff00/gordito avisos|r | |cffffff00/gordito panel|r")
        return
    end

    if event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER"
    or event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_SAY" then
        -- Ya no bloqueamos el cronometro por chat para no esperar 10 seg
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        if mainFrame:IsShown() then UpdateMissingList() end
        return
    end

    if event == "UNIT_SPELLCAST_START" then
        if not GorditoDB or not GorditoDB.enabled then return end
        local unit = ...
        -- En 3.3.5a: name, subText, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID
        local spellName, _, _, _, _, _, _, _, _, spellId = UnitCastingInfo(unit)
        if not spellName then return end
        
        -- 1. Proteccion Propia
        if unit == "player" and IsMousingOverFeast() then
            local timeLeft = GetFeastTime()
            local alreadyEating = IsAlreadyEating()
            -- Si ya tienes el bufo (>0) o estas en el proceso de comer
            if (timeLeft > 0 or alreadyEating) then
                SpellStopCasting()
                local reason = alreadyEating and "YA ESTAS COMIENDO" or "YA TENES EL BUFO"
                UIErrorsFrame:AddMessage("|cffff0000GORDITO: NO TOQUES EL FESTIN! "..reason..".|r", 1.0, 0.1, 0.1, 1.0, 10)
                PlaySoundFile("Sound\\Interface\\RaidWarning.wav")
                return
            end
        end

        -- 2. Deteccion de inicio de placement (Aviso Amarillo)
        if FEAST_PLACE_IDS[spellId] or (FEAST_NAMES[spellName] and not IsMousingOverFeast()) then
            OnFeastStarting(UnitName(unit) or "Alguien")
        end
        return
    end

    -- UNIT_SPELLCAST_SUCCEEDED: Confirmacion rapida por ID
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not GorditoDB or not GorditoDB.enabled then return end
        local unit, _, _, _, spellId = ...
        if FEAST_PLACE_IDS[spellId] then
            OnFeastPlaced(UnitName(unit) or unit or "Alguien")
        end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not GorditoDB or not GorditoDB.enabled then return end
        local _, subevent, _, sourceName, _, _, destName, _, spellId, spellName = ...
        if not subevent then return end

        if debugMode and (subevent:find("CAST") or subevent:find("AURA")) then
            print("|cffff0000[G-Debug]|r "..subevent.." | ID: "..(spellId or "nil").." | Name: "..(spellName or "nil"))
        end

        -- 1. COLOCACION FISICA (SUMMON/CREATE)
        if subevent == "SPELL_SUMMON" or subevent == "SPELL_CREATE" then
            if FEAST_PLACE_IDS[spellId] then
                OnFeastPlaced(sourceName or "Alguien")
                return
            end
        end

        -- 2. CLIC AL FESTIN (START)
        if subevent == "SPELL_CAST_START" then
            if EATING_CAST_NAMES[spellName] or EATING_BUFF_IDS[spellId] then
                local clicker = sourceName or "Alguien"
                -- Registrar el clic para los glotones
                clickCounts[clicker] = (clickCounts[clicker] or 0) + 1
                if clickCounts[clicker] > 1 then
                    OnGreedyClicker(clicker, clickCounts[clicker])
                end
                if mainFrame:IsShown() then UpdateUI() end
                return
            end
        end

        -- 3. BUFO APLICADO / REFRESCADO
        if EATING_BUFF_IDS[spellId] or EATING_CAST_NAMES[spellName] then
            local eater = destName or "Alguien"
            if subevent == "SPELL_AURA_APPLIED" then
                eatCounts[eater] = (eatCounts[eater] or 0) + 1
                totalEats = totalEats + 1
                auraLostTime[eater] = nil
                if eatCounts[eater] > 1 then
                    OnGreedyEater(eater, eatCounts[eater])
                else
                    if mainFrame:IsShown() then UpdateUI() end
                end
            elseif subevent == "SPELL_AURA_REFRESH" then
                eatCounts[eater] = (eatCounts[eater] or 0) + 1
                totalEats = totalEats + 1
                auraLostTime[eater] = nil
                OnGreedyEater(eater, eatCounts[eater])
            elseif subevent == "SPELL_AURA_REMOVED" then
                auraLostTime[eater] = GetTime()
            end
        end
    end
end)

-- ====== SLASH COMMANDS ======
SLASH_GORDITO1 = "/gordito"
SlashCmdList["GORDITO"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "avisos" or msg == "announce" then
        GorditoDB.announce = not GorditoDB.announce
        print("|cff00ff00Gordito|r: Avisos "..(GorditoDB.announce and "|cff00ff00ACTIVADOS|r" or "|cffff0000DESACTIVADOS|r"))
    elseif msg == "panel" then
        if mainFrame:IsShown() then mainFrame:Hide()
        else UpdateUI(); mainFrame:Show() end
    elseif msg == "debug" then
        debugMode = not debugMode
        print("|cff00ff00Gordito|r: Modo debug "..(debugMode and "|cffffff00ACTIVADO|r - pon un festin para ver los eventos" or "|cffff0000DESACTIVADO|r"))
    elseif msg == "toggle" then
        GorditoDB.enabled = not GorditoDB.enabled
        print("|cff00ff00Gordito|r: Proteccion "..(GorditoDB.enabled and "|cff00ff00ACTIVADA|r" or "|cffff0000DESACTIVADA|r"))
        UpdateMinimapIcon()
        UpdateUI()
    else
        -- Sin argumentos o comando desconocido abre el panel
        if mainFrame:IsShown() then mainFrame:Hide()
        else UpdateUI(); mainFrame:Show() end
    end
end
