-----------------------------------
-- Define some needed parameters --
-----------------------------------
-- the name of the robot used
local robot_name
-- the direction the robot (and the whole setup) is facing
local direction
-- the ports used
local robot_port = 5336
local computer_port = 5337
-- Addresses of the analyzers
local analyzer_11_addr
local analyzer_21_addr
local analyzer_12_addr
local analyzer_22_addr
-- components
local computer = require("computer")
local component = require("component")
local event = require("event")
local shell = require("shell")
local term = require("term")
local sides = require("sides")
local process = require("process")
local filesystem = require("filesystem")
local charts
local inifile

local function loadrequire(module)
  local res = pcall(require, module)
  if not(res) then
      error("System not initialized yet! run '" .. process.info()["command"] .. " --init' to initialize.")
      os.exit()
  end
end

local _, ops = shell.parse(...)

if ops.init then
  if not filesystem.exists("/usr/lib/") then
    print("test")
    print(filesystem.makeDirectory("/usr/lib/"))
  end
  -- initialize everything
  -- install the needed libraries
  if not filesystem.exists("/usr/lib/charts.lua") then
    print("Downloading charts library...")
    os.execute("wget https://raw.githubusercontent.com/OpenPrograms/Fingercomp-Programs/master/charts/charts.lua /usr/lib/charts.lua")
    os.sleep(2)
  else
    print("Charts library already downloaded.")
  end
  if not filesystem.exists("/usr/lib/inifile.lua") then
    print("Downloading inifile library...")
    os.execute("wget https://raw.githubusercontent.com/bartbes/inifile/main/inifile.lua /usr/lib/inifile.lua")
    os.sleep(2)
  else
    print("Inifile library already downloaded.")
  end
  if not filesystem.exists("/usr/man/breeder") then
    print("Downloading manpage...")
    os.execute("wget https://pastebin.com/raw/N1ybafwk /usr/man/breeder")
    os.sleep(2)
  else
    print("Manpage already downloaded.")
  end


  -- create ini file
  inifile = require("inifile")
  io.write("Please enter the name of the harvesting robot... ")
  local _robot_name = io.read()
  io.write("Please enter the direction the harvesting robot is facing (full word)... ")
  local _robot_direction = string.upper(io.read())
  io.write("Please enter the first few digits of the address of the analyzers (3-5 digits, must be unique)\n")
  io.write("[12][FP][FP][22]\tFP=Farmplot, TR=Trash\n")
  io.write("[11][FP][FP][21]\tBP=Byproducts (Drops of the seeds)\n")
  io.write("[TR][BP][RO][SO]\tRO=Robot, SO=Seed Output\n")
  io.write("Analyzer [11] Address: ")
  local _analyzer_11 = io.read()
  io.write("Analyzer [12] Address: ")
  local _analyzer_12 = io.read()
  io.write("Analyzer [21] Address: ")
  local _analyzer_21 = io.read()
  io.write("Analyzer [22] Address: ")
  local _analyzer_22 = io.read()

  local ini_table = {
    robot = {
      name = _robot_name,
      direction = _robot_direction,
    },
    port = {
      robot = robot_port,
      computer = computer_port
    },
    analyzers = {
      analyzer_11 = _analyzer_11,
      analyzer_12 = _analyzer_12,
      analyzer_21 = _analyzer_21,
      analyzer_22 = _analyzer_22,
    }
  }

  inifile.save('breeder.ini', ini_table)
  os.exit()
else
  loadrequire("charts")
  charts = require("charts")
  loadrequire("inifile")
  inifile = require("inifile")

  -- load the inifile
  local ini_table = inifile.parse("breeder.ini")
  robot_name = ini_table.robot.name
  direction = ini_table.robot.direction

  computer_port = ini_table.port.computer
  robot_port = ini_table.port.robot

  analyzer_11_addr = tostring(ini_table.analyzers.analyzer_11):gsub("+", "")
  analyzer_12_addr = tostring(ini_table.analyzers.analyzer_12):gsub("+", "")
  analyzer_21_addr = tostring(ini_table.analyzers.analyzer_21):gsub("+", "")
  analyzer_22_addr = tostring(ini_table.analyzers.analyzer_22):gsub("+", "")
end

-- indexof function for tables
table.indexOf = function ( tab, value )
  for index, val in ipairs(tab) do
      if value == val then
          return index
      end
  end
  return -1
end

local modem = component.modem
local gpu = component.gpu
local screen = component.screen
local redstone = component.redstone

local directions = {"NORTH", "EAST", "SOUTH", "WEST"}
local bestSeedGrowth = 0
local bestSeedGain = 0
local bestSeedStrength = 0
local currentSeedName = ""
local currentBestSeedStats = 0
local agri_growth, agri_gain, agri_strength, seed_progress = nil, nil, nil, nil
local seedsToBreed
local seedsToGo
local done = false

if redstone ~= nil then
  redstone.setOutput(sides.top, 15)
end

modem.open(computer_port)

local function msg(cmd, a, b, c)
  modem.broadcast(robot_port, robot_name, cmd, a, b, c)
end


if ops.seeds then
  local num_seeds = tonumber(ops.seeds)
  if num_seeds == nil then
    error("Error: " .. tostring(ops.seeds) .. "is not a valid number")
  else
    seedsToGo = math.floor(num_seeds)
    seedsToBreed = math.floor(num_seeds)
  end
else
  seedsToGo = 2
  seedsToBreed = 2
end

local analyzer_11 = component.proxy(component.get(analyzer_11_addr, "agricraft_peripheral"))
local analyzer_21 = component.proxy(component.get(analyzer_21_addr, "agricraft_peripheral"))
local analyzer_12 = component.proxy(component.get(analyzer_12_addr, "agricraft_peripheral"))
local analyzer_22 = component.proxy(component.get(analyzer_22_addr, "agricraft_peripheral"))


local function needsRecropping()
  local indexof = table.indexOf(directions, direction)
  if analyzer_11.isCrossCrop(directions[(indexof) % (#directions) + 1]) == nil then
    return true
  end
  if analyzer_12.isCrossCrop(directions[(indexof) % (#directions) + 1]) == nil then
    return true
  end
  if analyzer_21.isCrossCrop(directions[(indexof - 1  + (#directions - 1)) % (#directions) + 1]) == nil then
    return true
  end
  if analyzer_22.isCrossCrop(directions[(indexof - 1  + (#directions - 1)) % (#directions) + 1]) == nil then
    return true
  end
  return false
end

local function recrop()
  msg("harvest")
  msg("cropstickdrop")
  msg("placecropstick")
  msg("dropoffproduce")
  os.sleep(20)
end

local function gotSeeds()
  msg("gotseeds")
  msg("dummy")
end

local function plantsLeft()
  local indexof = table.indexOf(directions, direction)
  if analyzer_11.hasPlant(directions[(indexof) % (#directions) + 1])  then
    return true
  end
  if analyzer_12.hasPlant(directions[(indexof) % (#directions) + 1])  then
    return true
  end
  if analyzer_21.hasPlant(directions[(indexof - 1  + (#directions - 1)) % (#directions) + 1])  then
    return true
  end
  if analyzer_22.hasPlant(directions[(indexof - 1  + (#directions - 1)) % (#directions) + 1])  then
    return true
  end
  return false
end

local function plantsMature()
  local indexof = table.indexOf(directions, direction)
  if analyzer_11.isMature(directions[(indexof) % (#directions) + 1]) and
     analyzer_12.isMature(directions[(indexof) % (#directions) + 1]) and
     analyzer_21.isMature(directions[(indexof - 1  + (#directions - 1)) % (#directions) + 1]) and
     analyzer_22.isMature(directions[(indexof - 1  + (#directions - 1)) % (#directions) + 1]) then
    return true
  end
  return false
end

local function analyzeSeeds()
  local seeds = {}
  msg("gotoanalyzer")
  os.sleep(2)
  for i=1, 16, 1 do
    --print("analyze loop " .. i)
    os.sleep(0.5)
    -- attempt to drop the first seed into the analyzer
    msg("dropseed", i)
    msg("dummy")
    os.sleep(1)
    -- check if we got a seed in the analyzer
    if analyzer_21.getSpecimen() == "Air" then
      -- no seed in the analyzer, go to the next one
      goto continue
    end
    -- we have a seed
    if not analyzer_21.isAnalyzed() then
      analyzer_21.analyze()
      while analyzer_21.isAnalyzed() == false do
        os.sleep(0.5)
      end
    end
    local gr, ga, str = analyzer_21.getSpecimenStats()
    local temp = {}
    local seedStats = gr + ga + str
    if currentBestSeedStats < seedStats then
      currentBestSeedStats = seedStats
      bestSeedGrowth = gr
      bestSeedGain = ga
      bestSeedStrength = str
    end
    temp.stats = seedStats
    temp.index = i
    msg("takeseedfromanalyzer", i)
    os.sleep(0.5)
    msg("getstacksize", i)
    local _, _, _, _, _, name, response, stacksize = event.pull("modem_message")
    if name == robot_name then
      if response == "stacksize" then
        temp.size = stacksize
      end
    end
    table.insert(seeds, temp)
    ::continue::
  end
  os.sleep(0.5)
  msg("gobackfromanalyzer")
  os.sleep(2)
  return seeds
end

local function getBestSeeds(seeds)
  -- find the best seeds
  local bestStatIndex = 0
  local secondStatIndex = 0

  local bestInvIndex = 0
  local secondInvIndex = 0
  for j=1, #seeds, 1 do
    if seeds[bestStatIndex] == nil then
      bestStatIndex = j
      bestInvIndex = seeds[bestStatIndex].index
      goto continue1
    end
    if seeds[j].stats > seeds[bestStatIndex].stats then
      secondStatIndex = bestStatIndex
      secondInvIndex = seeds[secondStatIndex].index
      bestStatIndex = j
      bestInvIndex = seeds[bestStatIndex].index
    else
      if seeds[secondStatIndex] == nil then
        secondStatIndex = j
        secondInvIndex = seeds[secondStatIndex].index
      end
      if seeds[j].stats > seeds[secondStatIndex].stats then
        secondStatIndex = j
        secondInvIndex = seeds[secondStatIndex].index
      end
    end
    ::continue1::
  end
  if seeds[bestStatIndex].stats == 30 then
    -- we have 10/10/10 seeds
    local bestSeeds = {}
    for i = 1, #seeds do
      if seeds[i].stats == 30 then
        local temp = {}
        temp.index = seeds[i].index
        temp.size = seeds[i].size
        table.insert(bestSeeds, temp)
      end
    end

    if bestSeeds[1].size >= 2 then
      -- we have two seeds on this slot
      bestSeeds[1].size = bestSeeds[1].size - 2
      bestInvIndex = bestSeeds[1].index
    elseif #bestSeeds >=2 then
      bestSeeds[1].size = bestSeeds[1].size - 1
      bestInvIndex = bestSeeds[1].index
      bestSeeds[2].size = bestSeeds[2].size - 1
      secondInvIndex = bestSeeds[2].index
    end

    -- go to the outputchest
    msg("gotooutput")
    os.sleep(2)

    -- iterate over the bestseed array and dump all of them into the chest
    for i = 1, #bestSeeds do
      --print("Side: " .. tostring(sides.down) .. ", Index: " .. tostring(bestSeeds[i].index) .. ", Size: " .. tostring(bestSeeds[i].size))
      msg("dropitem", sides.down, bestSeeds[i].index, bestSeeds[i].size)
      msg("dummy")
      os.sleep(bestSeeds[i].size * 0.75)
      seedsToGo = seedsToGo - bestSeeds[i].size
    end
    msg("gobackfromoutput")
    os.sleep(2)
  end

  if seedsToGo <= 0 then
    -- we are done breeding
    msg("trashinventory")
    return true
  else
    -- keep going
    msg("manageseeds", bestInvIndex, secondInvIndex)
    return false
  end
end

local function setupScreen()
  local x, y = screen.getAspectRatio()
  x = x - 0.25
  y = y - 0.25
  local max_x, max_y = gpu.maxResolution()
  local end_x, end_y
  if x == y then
      end_x = max_y * 2
      end_y = max_y
  elseif x > y then
      end_x = max_x
      end_y = max_x / x * y / 2
      if end_y > max_y then
          local v = max_y / end_y
          end_x = end_x * v
          end_y = end_y * v
      end
      end_x = math.ceil(end_x)
      end_y = math.floor(end_y)
  elseif x < y then
      end_x = max_y / y * x * 2
      end_y = max_y
      if end_x > max_x then
          local v = max_x / end_x
          end_x = end_x * v
          end_y = end_y * v
      end
      end_x = math.floor(end_x)
      end_y = math.ceil(end_y)
  end
  gpu.setResolution(end_x, end_y)
end

if not ops.d then
  setupScreen()

  local w, h = gpu.getResolution()

  agri_growth = charts.Container {
    x = w * .25 - 2,
    y = 5,
    width = 6,
    height = h * 0.6,
    bg = 0x696969,
    payload = charts.ProgressBar {
      direction = charts.sides.TOP,
      value = 0,
      colorFunc = function(_, perc)
          if perc >= 1 then
          return 0x20afff
        elseif perc >= .8 then
          return 0x20ff20
        elseif perc >= .6 then
          return 0xafff20
        elseif perc >= .4 then
          return 0xffff20
        elseif perc >= .2 then
          return 0xffaf20
        else
          return 0xff2020
        end
      end
    }
  }

  agri_gain = charts.Container {
    x = w * .5 - 2,
    y = agri_growth.y,
    width = agri_growth.width,
    height = agri_growth.height,
    bg = agri_growth.bg,
    payload = charts.ProgressBar {
      direction = charts.sides.TOP,
      value = 0,
      colorFunc = agri_growth.payload.colorFunc
    }
  }

  agri_strength = charts.Container {
    x = w * .75 - 2,
    y = agri_growth.y,
    width = agri_growth.width,
    height = agri_growth.height,
    bg = agri_growth.bg,
    payload = charts.ProgressBar {
      direction = charts.sides.TOP,
      value = 0,
      colorFunc = agri_growth.payload.colorFunc
    }
  }

  seed_progress = charts.Container {
    x = agri_growth.y,
    y = h - 3,
    width = w - 2 * agri_growth.y,
    height = 2,
    bg = agri_growth.bg,
    payload = charts.ProgressBar {
      direction = charts.sides.RIGHT,
      value = 0,
      colorFunc = agri_growth.payload.colorFunc
    }
  }
end

-- check if we got seeds in the robot
gotSeeds()

-- wait for a response
local _, _, _, _, _, name, response, seedName = event.pull("modem_message")
if name == robot_name then
  if response == "false" then
    print("Please make sure that there are 1 of the same seeds in each of the last two slots of the robot.")
    return
  elseif response == "true" then
    currentSeedName = seedName
  end
end
-- check if there are any plants remaining or crops missing
if plantsLeft() or needsRecropping() then
  recrop()
end

analyzeSeeds()

-- we got seeds and the crops are setup
-- main loop
while true do
  if not ops.d then
    -- display the graphical interface
    local w, h = gpu.getResolution()
    local currentSeedStr = "Current Seed: " .. currentSeedName
    local seedsToBreedStr = "Seeds to Breed: " .. tostring(seedsToBreed - seedsToGo) .. "/" .. tostring(seedsToBreed)

    term.clear()
    gpu.set(w * .25 - 3, h * 0.7 + 1, "GROWTH " .. bestSeedGrowth)
    gpu.set(w * .5  - 2, h * 0.7 + 1, "GAIN " .. bestSeedGain)
    gpu.set(w * .75 - 4, h * 0.7 + 1, "STRENGTH " .. bestSeedStrength)

    gpu.set(w / 2 - #currentSeedStr / 2, h * 0.8, currentSeedStr)
    gpu.set(w / 2 - #seedsToBreedStr / 2, h * 0.9, seedsToBreedStr)

    agri_growth.payload.value = bestSeedGrowth / 10
    agri_gain.payload.value = bestSeedGain / 10
    agri_strength.payload.value = bestSeedStrength / 10
    local seed_progress_value = (seedsToBreed - seedsToGo) / seedsToBreed
    if seed_progress_value > 1 then seed_progress_value = 1 end
    seed_progress.payload.value = seed_progress_value

    agri_growth:draw()
    agri_gain:draw()
    agri_strength:draw()
    seed_progress:draw()

    if done then
      -- print "done" screen
      gpu.setForeground(0x660000)
      gpu.fill(w/2 - 25, h/2 - 4, 51, 9, "█")
      gpu.setForeground(0xFFFFFF)
      --gpu.setBackground(0x660000)
      gpu.set(w/2-2, h/2 - 1, "DONE!")
      gpu.set(w/2-7, h/2 + 1, "CTRL-C TO EXIT!")
    end
  else
    if done then
      term.write("DONE!")
      term.write("CTRL-C TO EXIT!")
    end
  end

  if not done then
    -- plant new crops and wait for them to grow
    msg("plantseeds")
    while not plantsMature() do
      if event.pull(3, "interrupted") then
        --msg("exit")
        term.clear()
        os.exit()
      end
    end
    -- all plants are mature
    -- recrop the field
    recrop()
    -- analyze the seeds
    local seeds = analyzeSeeds()
    done = getBestSeeds(seeds)
    os.sleep(10)
  else
    for i = 1, 3 do
      computer.beep(1000, 0.25)
      computer.beep(1500, 0.25)
      computer.beep(2000, 0.25)
    end
    if event.pull(10, "interrupted") then
      term.clear()
      os.exit()
    end
  end
end
