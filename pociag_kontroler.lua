-- Kontroler pociagu: routing (steerValueOverride) + hamowanie (brakeStrengthOverride)
-- Jazda do przodu (drive strength) NIE jest jeszcze obslugiwana - kolejny krok

local URL_MAPY = "https://raw.githubusercontent.com/TWOJ_NICK/TWOJE_REPO/main/skrzyzowania.json" -- <- PODMIEN
local CEL = "albert" -- <- stacja docelowa tego pociagu
local BOGIE = "bogie_0" -- <- PODMIEN na prawdziwa nazwe (peripheral.getNames())
local PRZOD = false -- <- ustalone wczesniej dla tego bogie
local ZASIEG_PROBE = 50

-- routing / skret
local DYSTANS_DECYZJI = 5 -- ile blokow przed skrzyzowaniem ustawiamy steer override
local OPOZNIENIE_WYLACZENIA_SKRETU = 3 -- sekundy - jak dlugo trzymac steer override po zniknieciu sygnalu
local STEER = { left = 1, straight = 0, right = -1 } -- potwierdzone znaki w Twoim swiecie

-- hamowanie
local DYSTANS_START_HAMOWANIA = 24 -- od tej odleglosci zaczynamy delikatnie hamowac (sila = 0)
local DYSTANS_PELNE_HAMOWANIE = 4  -- od tej odleglosci sila = 1 (pelne hamowanie)

local mapa = nil

-- stan routingu
local ostatnieSkrzyzowanie = nil
local skretAktywny = false
local skretCzasZnikniecia = nil

-- stan hamowania
local hamowanieAktywne = false

local function pobierzMape()
  local odp = http.get(URL_MAPY)
  if not odp then
    error("Nie udalo sie pobrac mapy z GitHuba - sprawdz http_enabled i link")
  end
  local dane = odp.readAll()
  odp.close()
  local sparsowane = textutils.unserializeJSON(dane)
  if not sparsowane then
    error("Nie udalo sie sparsowac JSON")
  end
  return sparsowane
end

local function wybierzKierunek(nazwaSkrzyzowania, cel)
  local opcje = mapa[nazwaSkrzyzowania]
  if not opcje then return nil end
  for kierunek, stacje in pairs(opcje) do
    if type(stacje) == "table" then
      for _, s in ipairs(stacje) do
        if s == cel then return kierunek end
      end
    elseif stacje == cel then
      return kierunek
    end
  end
  return nil
end

local function silaHamowania(dystans)
  if dystans >= DYSTANS_START_HAMOWANIA then
    return 0
  elseif dystans <= DYSTANS_PELNE_HAMOWANIE then
    return 1
  else
    return (DYSTANS_START_HAMOWANIA - dystans) / (DYSTANS_START_HAMOWANIA - DYSTANS_PELNE_HAMOWANIE)
  end
end

-- ===== ROUTING (skret na zwrotnicy) =====
local function obslugaRoutingu()
  local nazwy = peripheral.call(BOGIE, "getProbeSignalNames", PRZOD)
  local dystans = peripheral.call(BOGIE, "getProbeSignalDistance", PRZOD)

  if nazwy and #nazwy > 0 then
    local skrzyzowanie = nazwy[1]

    if dystans and dystans <= DYSTANS_DECYZJI and skrzyzowanie ~= ostatnieSkrzyzowanie then
      local kierunek = wybierzKierunek(skrzyzowanie, CEL)

      if kierunek and STEER[kierunek] ~= nil then
        print("Skrzyzowanie " .. skrzyzowanie .. " -> " .. kierunek .. " (steer=" .. STEER[kierunek] .. ")")
        peripheral.call(BOGIE, "setSteerValueOverride", STEER[kierunek])
        skretAktywny = true
      else
        print("UWAGA: brak trasy do '" .. CEL .. "' ze skrzyzowania " .. skrzyzowanie)
      end

      ostatnieSkrzyzowanie = skrzyzowanie
    end

    skretCzasZnikniecia = nil
  else
    if skretAktywny then
      if skretCzasZnikniecia == nil then
        skretCzasZnikniecia = os.clock()
      elseif os.clock() - skretCzasZnikniecia >= OPOZNIENIE_WYLACZENIA_SKRETU then
        peripheral.call(BOGIE, "disableSteerValueOverride")
        skretAktywny = false
        skretCzasZnikniecia = nil
        print("Steer override wylaczony")
      end
    end
  end
end

-- ===== HAMOWANIE na czerwonym =====
local function obslugaHamowania()
  local czerwoneNazwy = peripheral.call(BOGIE, "getProbeOccupiedSignalNames", PRZOD)
  local czerwonyDystans = peripheral.call(BOGIE, "getProbeOccupiedSignalDistance", PRZOD)

  local wZasiegu = czerwoneNazwy and #czerwoneNazwy > 0
                   and czerwonyDystans and czerwonyDystans <= DYSTANS_START_HAMOWANIA

  if wZasiegu then
    local sila = silaHamowania(czerwonyDystans)
    peripheral.call(BOGIE, "setBrakeStrengthOverride", sila)
    hamowanieAktywne = true
  else
    if hamowanieAktywne then
      print("Droga wolna - zwalniam hamulec")
      peripheral.call(BOGIE, "disableBrakeStrengthOverride")
      hamowanieAktywne = false
    end
  end
end

-- ===== START =====
peripheral.call(BOGIE, "setProbeDistance", ZASIEG_PROBE)
sleep(0.2)
mapa = pobierzMape()
print("Kontroler uruchomiony. Cel: " .. CEL .. ". Zasieg probe: " .. tostring(peripheral.call(BOGIE, "getProbeDistance")))

while true do
  obslugaHamowania()
  obslugaRoutingu()
  sleep(0.3)
end
