-- ============================================================
--  MapSetup.lua  -  Tabletop Simulator Global Script
--  Baut die Hex-Karte automatisch beim Spielstart auf.
-- ============================================================

-- ============================================================
--  KONFIGURATION  (wird per UI gesetzt, nicht mehr haendisch)
-- ============================================================

local PLAYER_COUNT = 2
local SCENARIO     = "full"
local TEAM_MODE    = nil

-- ============================================================
--  HUD-UI  (erscheint beim Host im Sichtfeld)
-- ============================================================

local SCENARIOS = {
    { label = "Tutorial – 2 Spieler", scenario = "tutorial", players = 2, team = nil },
    { label = "Tutorial – 3 Spieler", scenario = "tutorial", players = 3, team = nil },
    { label = "2 Spieler",            scenario = "full",     players = 2, team = nil },
    { label = "3 Spieler",            scenario = "full",     players = 3, team = nil },
    { label = "4 Spieler",            scenario = "full",     players = 4, team = nil },
    { label = "5 Spieler",            scenario = "full",     players = 5, team = nil },
    { label = "6 Spieler",            scenario = "full",     players = 6, team = nil },
    { label = "2 vs. 2",              scenario = "full",     players = 4, team = "2v2" },
    { label = "3 vs. 3",              scenario = "full",     players = 6, team = "3v3" },
}
local setupMap        -- Forward-Declaration
local shuffleDecks    -- Forward-Declaration
local setupFernerKrieg -- Forward-Declaration


local function buildUI()
    local parts = {}
    parts[#parts+1] = '<VerticalLayout id="setupPanel"'
    parts[#parts+1] = ' spacing="6" padding="20 20 20 20"'
    parts[#parts+1] = ' childAlignment="UpperCenter"'
    parts[#parts+1] = ' childForceExpandWidth="true">'
    parts[#parts+1] = '<Text fontSize="20" fontStyle="Bold" color="#c8c640"'
    parts[#parts+1] = ' preferredHeight="36" alignment="MiddleCenter">Szenario waehlen</Text>'
    for i, s in ipairs(SCENARIOS) do
        -- onClick uebergibt (player, value) an den Handler
        -- Wir kodieren den Index als id und lesen ihn per UI.getAttribute
        parts[#parts+1] = '<Button id="sc_' .. i .. '"'
                       .. ' onClick="onScenarioChosen"'
                       .. ' fontSize="16" preferredHeight="38"'
                       .. ' color="#2a2a2a" textColor="#e8e6de"'
                       .. ' highlightColor="#4a4a4a">' .. s.label .. '</Button>'
    end
    parts[#parts+1] = '<Button id="sc_cancel"'
                   .. ' onClick="onScenarioChosen"'
                   .. ' fontSize="16" preferredHeight="38"'
                   .. ' color="#4a1a1a" textColor="#e8e6de"'
                   .. ' highlightColor="#6a2a2a">Abbrechen</Button>'
    parts[#parts+1] = '</VerticalLayout>'
    return table.concat(parts, "\n")
end

-- TTS ruft Button-Handler mit (player, value, id) auf
-- 'id' ist die id des geklickten Elements
function onScenarioChosen(player, value, id)
    -- Abbrechen
    if id == "sc_cancel" then
        UI.hide("setupPanel")
        print("[MapSetup] Abgebrochen.")
        return
    end
    -- id hat Format "sc_1", "sc_2" etc.
    local idx = tonumber(string.match(id, "sc_(%d+)"))
    if not idx then
        print("[MapSetup] Unbekannte Button-ID: " .. tostring(id))
        return
    end
    local s = SCENARIOS[idx]
    if not s then return end
    PLAYER_COUNT = s.players
    SCENARIO     = s.scenario
    TEAM_MODE    = s.team
    UI.hide("setupPanel")
    print("[MapSetup] Starte: " .. s.label)
    shuffleDecks()
    setupFernerKrieg()
    setupMap()
end

local function showSetupUI()
    -- Nur der Host bekommt das Setup-Panel
    if not Player.getPlayers()[1].host then
        return
    end
    UI.setXml(buildUI())
end


local GZ_POS = {x = 0.00, y = 0.75, z = 2.51}
local TILE_Y  = 0.75

local BASIS_Q = {x =  2.18, z =  1.26}
local BASIS_R = {x =  2.18, z = -1.26}

local SYSTEMS_BAG_GUID = "0d2a31"
local PARK_POS = {x = 0, y = -10, z = 0}

local BAGS = {
    Planet        = "28408b",
    SchwarzesLoch = "9548ca",
    Supernova     = "bc6105",
    Sturm         = "3e6c13",
    Anomalie      = "7cd1bb",
    Asteroid      = "4bb20e",
    Nebel         = "9f11cf",
    Weltall       = "c9a943",
    Heimatwelt    = "262891",
}

local activeBags = {}

-- ============================================================
--  HEIMATWELT-POSITIONEN
--  Feste (q,r)-Koordinaten fuer jeden Spieler.
--  Direkt aus dem Regelwerk abgelesen.
-- ============================================================

local HOME_POSITIONS = {
    tutorial = {
        [2] = { {q= 0, r= 3}, {q= 0, r=-3} },
        [3] = { {q= 3, r= 0}, {q=-3, r= 3}, {q= 0, r=-3} },
    },
    full = {
        [2] = { {q= 0, r= 4}, {q= 0, r=-4} },
        [3] = { {q= 0, r=-4}, {q= 4, r= 0}, {q=-4, r= 4} },
        [4] = { {q= 2, r=-4}, {q=-4, r= 0}, {q= 4, r= 0}, {q=-2, r= 4} },
        [5] = { {q= 1, r=-4}, {q=-4, r= 1}, {q= 2, r= 2},
                {q= 5, r=-3}, {q=-3, r= 5} },
        [6] = { {q= 1, r=-5}, {q= 5, r=-4}, {q= 4, r= 1},
                {q=-1, r= 5}, {q=-5, r= 4}, {q=-4, r=-1} },
    },
    ["2v2"] = { {q= 0, r=-4}, {q=-4, r= 0}, {q= 4, r= 0}, {q= 0, r= 4} },
    ["3v3"] = { {q= 1, r=-5}, {q=-2, r=-2}, {q=-5, r=1},
                {q=-1, r= 5}, {q= 2, r= 2}, {q= 5, r=-1} },
}

-- ============================================================
--  SZENARIO-DATEN
--  Heimatwelten sind hier noch enthalten (fuer Zaehlung),
--  werden aber nicht zufaellig platziert sondern an Ecken gesetzt.
-- ============================================================

local SCENARIO_DATA = {
    tutorial = {
        [2] = {
            [2] = { Planet=3, SchwarzesLoch=1, Supernova=1, Sturm=1 },
            [3] = { Anomalie=4, Asteroid=1, Nebel=1, Planet=2,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [4] = { Anomalie=2, Asteroid=5, Nebel=5,
                    Planet=1, Weltall=3 },
        },
        [3] = {
            [2] = { Planet=3, SchwarzesLoch=1, Supernova=1, Sturm=1 },
            [3] = { Anomalie=4, Asteroid=1, Nebel=1, Planet=2,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [4] = { Anomalie=1, Asteroid=5, Nebel=5,
                    Planet=1, Weltall=3 },
        },
    },
    full = {
        [2] = {
            [2] = { Planet=1, SchwarzesLoch=1, Supernova=1, Sturm=3 },
            [3] = { Anomalie=4, Asteroid=1, Nebel=1, Planet=1,
                    SchwarzesLoch=2, Supernova=1, Sturm=2 },
            [4] = { Anomalie=3, Asteroid=5, Nebel=5, Planet=1,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [5] = { Anomalie=2, Asteroid=6, Nebel=6,
                    Planet=1, Weltall=7 },
        },
        [3] = {
            [2] = { Planet=2, SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [3] = { Anomalie=4, Asteroid=1, Nebel=1, Planet=2,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [4] = { Anomalie=3, Asteroid=5, Nebel=5, Planet=1,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [5] = { Anomalie=2, Asteroid=6, Nebel=6,
                    Planet=1, Weltall=6 },
        },
        [4] = {
            [2] = { Planet=2, SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [3] = { Anomalie=4, Asteroid=1, Nebel=1, Planet=2,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [4] = { Anomalie=3, Asteroid=4, Nebel=5, Planet=2,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [5] = { Anomalie=2, Asteroid=5, Nebel=5,
                    Planet=2, Weltall=6 },
        },
        [5] = {
            [2] = { Planet=3, SchwarzesLoch=1, Supernova=1, Sturm=1 },
            [3] = { Anomalie=4, Asteroid=1, Planet=3,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [4] = { Anomalie=3, Asteroid=4, Nebel=5, Planet=2,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [5] = { Anomalie=2, Asteroid=6, Nebel=6,
                    Planet=1, Weltall=6 },
            [6] = { Heimatwelt=5 },  -- Ring VI: nur Heimatwelten
        },
        [6] = {
            [2] = { Planet=3, SchwarzesLoch=1, Supernova=1, Sturm=1 },
            [3] = { Anomalie=4, Asteroid=1, Planet=3,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [4] = { Anomalie=3, Asteroid=4, Nebel=4, Planet=3,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [5] = { Anomalie=2, Asteroid=8, Nebel=8,
                    Weltall=6 },
            [6] = { Heimatwelt=6 },  -- Ring VI: nur Heimatwelten
        },
    },
    ["3v3"] = {
        [6] = {
            [2] = { Planet=3, SchwarzesLoch=1, Supernova=1, Sturm=1 },
            [3] = { Anomalie=4, Asteroid=1, Planet=3,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [4] = { Anomalie=3, Asteroid=4, Nebel=4, Planet=3,
                    SchwarzesLoch=1, Supernova=1, Sturm=2 },
            [5] = { Anomalie=2, Asteroid=7, Nebel=7,
                    Weltall=6 },
            [6] = { Heimatwelt=4 },  -- Ring VI: 4 Heimatwelten
        },
    },
}

-- ============================================================
--  HEX-GITTER
-- ============================================================

local function hexToWorld(q, r)
    return {
        x = GZ_POS.x + q * BASIS_Q.x + r * BASIS_R.x,
        y = TILE_Y,
        z = GZ_POS.z + q * BASIS_Q.z + r * BASIS_R.z,
    }
end

local function getRingPositions(n)
    if n == 0 then return { {q=0, r=0} } end
    local positions = {}
    local directions = {
        {q=-1, r= 1}, {q=-1, r= 0}, {q= 0, r=-1},
        {q= 1, r=-1}, {q= 1, r= 0}, {q= 0, r= 1},
    }
    local q, r = n, 0
    for side = 1, 6 do
        for _ = 1, n do
            table.insert(positions, {q=q, r=r})
            q = q + directions[side].q
            r = r + directions[side].r
        end
    end
    return positions
end

-- Gibt die Positions-Indizes (1-basiert) der Ecken zurueck
-- fuer gegebene Eck-Nummern (0-basiert) und Ringradius n
local function getCornerIndices(cornerNums, n)
    local indices = {}
    for _, k in ipairs(cornerNums) do
        table.insert(indices, k * n + 1)  -- +1 weil Lua 1-basiert
    end
    return indices
end

-- ============================================================
--  TILE-POOL & SHUFFLE
-- ============================================================

local function buildPool(tileTable)
    local pool = {}
    for tileType, count in pairs(tileTable) do
        -- Heimatwelten werden separat platziert, nicht in den Pool
        if tileType ~= "Heimatwelt" then
            for _ = 1, count do
                table.insert(pool, tileType)
            end
        end
    end
    return pool
end

local function shuffle(t)
    math.randomseed(os.time())
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local function collectNeededTypes(playerRings)
    local seen, needed = {}, {}
    for _, tileTable in pairs(playerRings) do
        for tileType in pairs(tileTable) do
            if not seen[tileType] then
                seen[tileType] = true
                table.insert(needed, tileType)
            end
        end
    end
    return needed
end

-- ============================================================
--  BAG-MANAGEMENT
-- ============================================================

local function pullBagsFromSystemsBag(neededTypes)
    local systemsBag = getObjectFromGUID(SYSTEMS_BAG_GUID)
    if not systemsBag then
        print("[MapSetup] FEHLER: Systems-Bag nicht gefunden! GUID: " .. SYSTEMS_BAG_GUID)
        return false
    end
    for _, tileType in ipairs(neededTypes) do
        local guid = BAGS[tileType]
        if not guid then
            print("[MapSetup] Unbekannter Tile-Typ: " .. tileType)
        elseif not activeBags[guid] then
            local obj = systemsBag.takeObject({
                guid = guid, position = PARK_POS, smooth = false,
            })
            if obj then
                activeBags[guid] = obj
            else
                print("[MapSetup] FEHLER: Bag nicht gefunden: " .. tileType)
            end
        end
    end
    return true
end

local function returnBagsToSystemsBag(afterDelay)
    local bagList = {}
    for _, bagObj in pairs(activeBags) do
        if bagObj then table.insert(bagList, bagObj) end
    end

    for i, bagObj in ipairs(bagList) do
        -- Erst zur Parkposition teleportieren (keine Animation, keine Kollision)
        Wait.time(function()
            bagObj.setPosition(PARK_POS)
            bagObj.setVelocity({0, 0, 0})
        end, afterDelay + (i - 1) * 0.5)

        -- Dann mit etwas Abstand in den Systems-Bag legen
        Wait.time(function()
            local systemsBag = getObjectFromGUID(SYSTEMS_BAG_GUID)
            if not systemsBag then
                print("[MapSetup] Systems-Bag nicht gefunden!")
                return
            end
            systemsBag.putObject(bagObj)
            if i == #bagList then
                activeBags = {}
                print("[MapSetup] Alle Tile-Bags zurueck im Systems-Bag.")
            end
        end, afterDelay + (i - 1) * 0.5 + 0.3)
    end
end

-- ============================================================
--  TILE SPAWNEN
-- ============================================================

local function spawnTile(tileType, pos, delay)
    local guid = BAGS[tileType]
    if not guid then
        print("[MapSetup] Unbekannter Tile-Typ: " .. tostring(tileType))
        return
    end
    Wait.time(function()
        local bag = activeBags[guid]
        if not bag then
            print("[MapSetup] Aktiver Bag nicht verfuegbar: " .. tileType)
            return
        end
        local obj = bag.takeObject({
            position = pos,
            rotation = {x=0, y=0, z=180},
            smooth   = true,
        })
        if obj then obj.use_snap_points = false end
    end, delay)
end

-- ============================================================
--  HAUPT-SETUP
-- ============================================================

setupMap = function()
    -- Wird nach UI-Auswahl aufgerufen, kein Wait noetig
    print("[MapSetup] Starte -- " .. SCENARIO .. ", " .. PLAYER_COUNT .. " Spieler"
          .. (TEAM_MODE and (" (" .. TEAM_MODE .. ")") or ""))

    -- Szenario-Daten (TEAM_MODE hat Vorrang)
    local scenarioKey = TEAM_MODE or SCENARIO
    local scenarioRings = SCENARIO_DATA[scenarioKey] or SCENARIO_DATA[SCENARIO]
    if not scenarioRings then
        print("[MapSetup] Unbekanntes Szenario: " .. scenarioKey); return
    end
    local playerRings = scenarioRings[PLAYER_COUNT]
    if not playerRings then
        print("[MapSetup] Keine Daten fuer " .. PLAYER_COUNT .. " Spieler"); return
    end

    -- Heimatwelt-Positionen bestimmen
    local posKey = TEAM_MODE or SCENARIO
    local posEntry = HOME_POSITIONS[posKey]
    local homeList
    if type(posEntry) == "table" then
        local first = posEntry[1]
        if type(first) == "table" and first.q ~= nil then
            -- Direkte Positionsliste (Team-Modi): erstes Element ist {q,r}
            homeList = posEntry
        else
            -- Spielerzahl-Tabelle (normale Szenarien)
            homeList = posEntry[PLAYER_COUNT] or {}
        end
    else
        homeList = {}
    end
    if not homeList then
        print("[MapSetup] Keine Heimatwelt-Positionen definiert!")
        homeList = {}
    end
    -- Set aus (q,r)-Strings fuer schnellen Lookup
    local homeSet = {}
    for _, hw in ipairs(homeList) do
        local k = hw.q .. "," .. hw.r
        homeSet[k] = true
    end

    -- Bags holen (Heimatwelt-Bag immer einschliessen wenn Heimatwelten platziert werden)
    local neededTypes = collectNeededTypes(playerRings)
    if #homeList > 0 then
        table.insert(neededTypes, "Heimatwelt")
    end
    if not pullBagsFromSystemsBag(neededTypes) then return end

    Wait.time(function()  -- kurze Pause nach takeObject
        -- Hoechsten Ring ermitteln
        local maxRing = 0
        for ringIdx in pairs(playerRings) do
            if ringIdx > maxRing then maxRing = ringIdx end
        end
        local outerRadius = maxRing - 1  -- Radius des aeussersten Rings

        -- Heimatwelten werden per (q,r)-Lookup identifiziert, nicht per Index

        local delay = 0.0
        local DELAY_STEP = 0.15

        for ringIdx = 2, maxRing do
            local tileTable = playerRings[ringIdx]
            if not tileTable then
                print("[MapSetup] Ring " .. ringIdx .. " fehlt, ueberspringe.")
            else
                local radius   = ringIdx - 1
                local positions = getRingPositions(radius)

                -- Pool ohne Heimatwelten
                local pool = shuffle(buildPool(tileTable))
                local poolIdx = 1

                for _, hex in ipairs(positions) do
                    local worldPos = hexToWorld(hex.q, hex.r)
                    local key = hex.q .. "," .. hex.r
                    if homeSet[key] then
                        -- Heimatwelt an diese Position
                        spawnTile("Heimatwelt", worldPos, delay)
                    else
                        -- Normales Tile aus dem Pool
                        if pool[poolIdx] then
                            spawnTile(pool[poolIdx], worldPos, delay)
                            poolIdx = poolIdx + 1
                        else
                            print("[MapSetup] Pool leer bei Ring " .. ringIdx ..
                                  ", hex " .. key)
                        end
                    end
                    delay = delay + DELAY_STEP
                end

                print(string.format("[MapSetup] Ring %d: %d Positionen gesetzt.",
                                    ringIdx, #positions))
            end
        end

        returnBagsToSystemsBag(delay + 1.0)
        print("[MapSetup] Fertig.")
    end, 0.5)
end

-- ============================================================
--  EINSTIEGSPUNKT
-- ============================================================

local DECK_GUIDS = {
    "527d7e", "f165f8", "7c12ae", "7a4b82", "e4c980",
    "0785fb", "5e39f1", "acb627", "5a5092", "6b01d1",
}

shuffleDecks = function()
    for _, guid in ipairs(DECK_GUIDS) do
        local deck = getObjectFromGUID(guid)
        if deck then
            deck.shuffle()
        else
            print("[MapSetup] Kartenstapel nicht gefunden: " .. guid)
        end
    end
    print("[MapSetup] Alle Kartenstapel gemischt.")
end

-- Position wo abgeworfene Karten landen
local DISCARD_POS = {x = -45.64, y = 0.76, z = 3.80}

-- Ferner Krieg Stapel: Karten pro Stufe, in der Reihenfolge wie sie im Stapel liegen
-- Stufe I liegt oben, Stufe III unten
local FERNER_KRIEG = {
    {
        guid  = "15822c",  -- Boden
        name  = "Ferner Krieg Boden",
        tiers = {
            { "3aa43d", "175218", "7f3a77", "ef71a3" },  -- Stufe I
            { "337429", "2829c1", "bf0dee" },              -- Stufe II
            { "860268", "25bd44" },                        -- Stufe III
        },
    },
    {
        guid  = "7feb0b",  -- Weltraum
        name  = "Ferner Krieg Weltraum",
        tiers = {
            { "af364d", "e5a973", "8b16e1", "1cd6e4" },  -- Stufe I
            { "3f7c02", "296815", "c287a4" },              -- Stufe II
            { "52c248", "f7ba87" },                        -- Stufe III
        },
    },
}

-- Verarbeitet eine einzelne Stufe eines Stapels:
-- Karten raus, mischen, eine abwerfen, Rest zuruecklegen, dann callback()
local function processTier(stapelGuid, stapelName, tierGuids, callback)
    local takenCards = {}
    local STEP = 0.4

    for i, cardGuid in ipairs(tierGuids) do
        Wait.time(function()
            local deck = getObjectFromGUID(stapelGuid)
            if not deck then
                print("[MapSetup] " .. stapelName .. " nicht gefunden!")
                return
            end
            local found = false
            for _, entry in ipairs(deck.getObjects()) do
                if entry.guid == cardGuid then found = true; break end
            end
            if not found then
                print("[MapSetup] Karte nicht im Stapel: " .. cardGuid)
                return
            end
            local card = deck.takeObject({
                guid     = cardGuid,
                position = PARK_POS,
                smooth   = false,
            })
            if card then table.insert(takenCards, card) end
        end, (i - 1) * STEP)
    end

    Wait.time(function()
        if #takenCards == 0 then
            if callback then callback() end
            return
        end
        math.randomseed(os.time())
        for i = #takenCards, 2, -1 do
            local j = math.random(i)
            takenCards[i], takenCards[j] = takenCards[j], takenCards[i]
        end
        local discardCard = table.remove(takenCards, 1)
        discardCard.setPosition(DISCARD_POS)
        discardCard.setRotation({0, 0, 180})
        local deck = getObjectFromGUID(stapelGuid)
        for _, card in ipairs(takenCards) do
            if deck then
                deck.putObject(card)
                deck = getObjectFromGUID(stapelGuid)
            else
                card.setPosition(PARK_POS)
                deck = card
            end
        end
        print("[MapSetup] " .. stapelName .. " Stufe gemischt, 1 Karte abgeworfen.")
        if callback then callback() end
    end, #tierGuids * STEP)
end

local function processStapel(stapel, tierIdx, callback)
    if tierIdx < 1 then
        print("[MapSetup] " .. stapel.name .. " vollstaendig vorbereitet.")
        if callback then callback() end
        return
    end
    processTier(stapel.guid, stapel.name, stapel.tiers[tierIdx], function()
        processStapel(stapel, tierIdx - 1, callback)
    end)
end

setupFernerKrieg = function()
    -- Stufen 1->2->3 verarbeiten: putObject legt unter den Stapel,
    -- also wird Stufe III zuerst gelegt (unten) und Stufe I zuletzt (oben)
    local function processStapelVorwaerts(stapel, tierIdx, callback)
        if tierIdx > #stapel.tiers then
            print("[MapSetup] " .. stapel.name .. " vollstaendig vorbereitet.")
            if callback then callback() end
            return
        end
        processTier(stapel.guid, stapel.name, stapel.tiers[tierIdx], function()
            processStapelVorwaerts(stapel, tierIdx + 1, callback)
        end)
    end
    processStapelVorwaerts(FERNER_KRIEG[1], 1, function()
        processStapelVorwaerts(FERNER_KRIEG[2], 1, nil)
    end)
end


function onLoad()
    Wait.time(showSetupUI, 1.0)
end
