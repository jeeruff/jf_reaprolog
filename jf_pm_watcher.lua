-- jf_pm_watcher.lua
-- JF PM: фоновый watcher. Единственная задача — заметить, что вкладка
-- проекта исчезла без отчёта, и пометить проект в индексе как «без отчёта».
--
-- Предельно лёгкий: раз в ~1 сек только EnumProjects (без парсинга и I/O).
-- Индекс читается/пишется ТОЛЬКО в момент закрытия проекта.
--
-- Повторный запуск экшна выключает watcher (toggle, видно в тулбаре).
-- Автозапуск: добавить экшн в __startup через SWS
-- (Extensions → Startup actions → Set global startup action).

local SCRIPT_PATH, SECTION_ID, CMD_ID = select(2, reaper.get_action_context())
local SCRIPT_DIR = SCRIPT_PATH:match('^(.*)[/\\]')
local core = dofile(SCRIPT_DIR .. '/jf_pm_core.lua')

-- toggle: второй запуск того же экшна просит первый остановиться
if reaper.GetExtState(core.EXT_SECTION, 'watcher_running') == '1' then
  reaper.SetExtState(core.EXT_SECTION, 'watcher_stop', '1', false)
  return
end
reaper.SetExtState(core.EXT_SECTION, 'watcher_running', '1', false)
reaper.SetExtState(core.EXT_SECTION, 'watcher_stop', '', false)
reaper.SetToggleCommandState(SECTION_ID, CMD_ID, 1)
reaper.RefreshToolbar2(SECTION_ID, CMD_ID)

local INTERVAL = 1.0
local last_check = 0
local open_set = {}   -- path -> true, снимок открытых вкладок
local first_pass = true

local function snapshot()
  local set = {}
  local i = 0
  while true do
    local p, fn = reaper.EnumProjects(i)
    if not p then break end
    if fn and fn ~= '' then set[fn] = true end
    i = i + 1
  end
  return set
end

-- Проект закрыли. Если report-скрипт только что отработал по этому пути —
-- ничего не делаем, иначе помечаем в индексе «без отчёта».
local function on_project_closed(path)
  local beacon = reaper.GetExtState(core.EXT_SECTION, 'REPORT_JUST_SAVED')
  local bpath, bts = beacon:match('^(.*)|(%d+)$')
  if bpath == path and os.time() - tonumber(bts) < 300 then
    reaper.SetExtState(core.EXT_SECTION, 'REPORT_JUST_SAVED', '', false)
    return
  end
  local idx = core.load_index()
  local card = idx.projects[path]
  if card then
    card.needs_report = true
    core.save_index(idx)
  end
  -- проекта нет в индексе — появится с флагом при следующем Rescan? Нет:
  -- Rescan не знает о закрытии. Дешёвый вариант — карточка сразу:
  if not card then
    local built = core.build_card(path, nil)
    if built then
      built.needs_report = true
      idx.projects[path] = built
      core.save_index(idx)
    end
  end
end

local function loop()
  if reaper.GetExtState(core.EXT_SECTION, 'watcher_stop') == '1' then
    return -- atexit приберёт state
  end
  local now = reaper.time_precise()
  if now - last_check >= INTERVAL then
    last_check = now
    local set = snapshot()
    if not first_pass then
      for path in pairs(open_set) do
        if not set[path] then on_project_closed(path) end
      end
    end
    open_set = set
    first_pass = false
  end
  reaper.defer(loop)
end

reaper.atexit(function()
  reaper.SetExtState(core.EXT_SECTION, 'watcher_running', '', false)
  reaper.SetExtState(core.EXT_SECTION, 'watcher_stop', '', false)
  reaper.SetToggleCommandState(SECTION_ID, CMD_ID, 0)
  reaper.RefreshToolbar2(SECTION_ID, CMD_ID)
end)

reaper.defer(loop)
