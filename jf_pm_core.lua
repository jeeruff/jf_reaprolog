-- jf_pm_core.lua
-- Общий модуль JF Project Manager: парсер .rpp, JSON, индекс, настройки.
-- Загружается без глобального `reaper` (для тестов): reaper.* только внутри функций.

local M = {}

M.NAMESPACE = 'JF_PM'          -- namespace project extstate в .rpp
M.EXT_SECTION = 'JF_PM'        -- секция глобального extstate (настройки)
M.INDEX_FILENAME = 'jf_pm_index.json'

-- Статус — это решение о судьбе проекта, а не полка.
-- Пайплайн (прогресс): набросок → в работе → к миксу → готово.
-- Решения вне пайплайна: «на расслоение» (разобрать на семплы — это закрытие
-- петли, не провал), «архив» (расслоение сделано / проект закрыт),
-- «заморожено» (решение отложено сознательно).
M.STATUSES = { 'набросок', 'в работе', 'к миксу', 'готово',
               'на расслоение', 'архив', 'заморожено' }
M.PIPELINE = { ['набросок'] = 1, ['в работе'] = 2, ['к миксу'] = 3, ['готово'] = 4 }
M.PIPELINE_STEPS = 4
-- 0xRRGGBBAA для ReaImGui
M.STATUS_COLORS = {
  ['набросок']      = 0x8A8A8AFF,
  ['в работе']      = 0xE8E8E8FF,
  ['к миксу']       = 0xD9B96CFF,
  ['готово']        = 0x7FD98AFF,
  ['на расслоение'] = 0xC98AD9FF,
  ['архив']         = 0x5F5F5FFF,
  ['заморожено']    = 0x6C87A0FF,
}

-- ===========================================================================
-- JSON (минимальный, под наши данные: объекты/массивы/строки/числа/bool/null)
-- ===========================================================================

local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= 'number' then return false end
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return n > 0
end

local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r',
              ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f' }

local function esc_str(s)
  return (s:gsub('[%z\1-\31"\\]', function(c)
    return ESC[c] or string.format('\\u%04x', c:byte())
  end))
end

function M.json_encode(v, indent)
  indent = indent or ''
  local t = type(v)
  if v == nil then return 'null' end
  if t == 'boolean' then return tostring(v) end
  if t == 'number' then
    if v % 1 == 0 and math.abs(v) < 2^53 then return string.format('%d', v) end
    return string.format('%.10g', v)
  end
  if t == 'string' then return '"' .. esc_str(v) .. '"' end
  if t == 'table' then
    local ind2 = indent .. '  '
    if is_array(v) then
      local out = {}
      for i = 1, #v do out[i] = ind2 .. M.json_encode(v[i], ind2) end
      return '[\n' .. table.concat(out, ',\n') .. '\n' .. indent .. ']'
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      if #keys == 0 then return '{}' end
      local out = {}
      for i, k in ipairs(keys) do
        out[i] = ind2 .. '"' .. esc_str(k) .. '": ' .. M.json_encode(v[k], ind2)
      end
      return '{\n' .. table.concat(out, ',\n') .. '\n' .. indent .. '}'
    end
  end
  error('json_encode: unsupported type ' .. t)
end

function M.json_decode(s)
  local pos = 1

  local function skip_ws()
    pos = s:find('[^ \t\r\n]', pos) or #s + 1
  end

  local parse_value

  local function parse_string()
    pos = pos + 1 -- opening quote
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == '' then error('json: unterminated string') end
      if c == '"' then pos = pos + 1 break end
      if c == '\\' then
        local e = s:sub(pos + 1, pos + 1)
        if e == 'u' then
          local hex = s:sub(pos + 2, pos + 5)
          local cp = tonumber(hex, 16) or 0
          out[#out + 1] = utf8 and utf8.char(cp) or string.char(cp % 256)
          pos = pos + 6
        else
          local map = { n = '\n', r = '\r', t = '\t', b = '\b', f = '\f' }
          out[#out + 1] = map[e] or e
          pos = pos + 2
        end
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    return table.concat(out)
  end

  parse_value = function()
    skip_ws()
    local c = s:sub(pos, pos)
    if c == '"' then return parse_string() end
    if c == '{' then
      pos = pos + 1
      local obj = {}
      skip_ws()
      if s:sub(pos, pos) == '}' then pos = pos + 1 return obj end
      while true do
        skip_ws()
        local k = parse_string()
        skip_ws()
        if s:sub(pos, pos) ~= ':' then error('json: expected :') end
        pos = pos + 1
        obj[k] = parse_value()
        skip_ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == '}' then return obj end
        if d ~= ',' then error('json: expected , or }') end
      end
    end
    if c == '[' then
      pos = pos + 1
      local arr = {}
      skip_ws()
      if s:sub(pos, pos) == ']' then pos = pos + 1 return arr end
      while true do
        arr[#arr + 1] = parse_value()
        skip_ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == ']' then return arr end
        if d ~= ',' then error('json: expected , or ]') end
      end
    end
    local lit = s:match('^[%w%.%+%-]+', pos)
    if lit == 'true' then pos = pos + 4 return true end
    if lit == 'false' then pos = pos + 5 return false end
    if lit == 'null' then pos = pos + 4 return nil end
    local num = tonumber(lit)
    if num then pos = pos + #lit return num end
    error('json: unexpected token at ' .. pos)
  end

  local ok, res = pcall(parse_value)
  if not ok then return nil, res end
  return res
end

-- ===========================================================================
-- Кодирование многострочных значений для extstate (одна строка в .rpp)
-- ===========================================================================

function M.encode_ml(str)
  return (str:gsub('\\', '\\\\'):gsub('\r\n', '\n'):gsub('\n', '\\n'))
end

function M.decode_ml(str)
  local out = str:gsub('\\\\', '\0'):gsub('\\n', '\n'):gsub('%z', '\\')
  return out
end

-- ===========================================================================
-- Парсер .rpp (plain text, проект не открывается)
-- ===========================================================================

-- Токенизатор строки .rpp: Reaper квотит строки одним из ", ', ` —
-- выбирая символ, которого нет в самой строке.
function M.tokenize_rpp_line(line)
  local toks = {}
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if c == ' ' or c == '\t' then
      i = i + 1
    elseif c == '"' or c == "'" or c == '`' then
      local j = line:find(c, i + 1, true)
      if not j then
        toks[#toks + 1] = line:sub(i + 1)
        break
      end
      toks[#toks + 1] = line:sub(i + 1, j - 1)
      i = j + 1
    else
      local j = line:find('[ \t]', i) or (n + 1)
      toks[#toks + 1] = line:sub(i, j - 1)
      i = j
    end
  end
  return toks
end

-- Возвращает карточку-таблицу либо nil, err.
-- Формат строк проверен на Reaper 7; при расхождениях — чинить здесь,
-- тест: tests/test_parser.lua.
function M.parse_rpp(path)
  local f = io.open(path, 'rb')
  if not f then return nil, 'cannot open: ' .. tostring(path) end

  local card = {
    tempo = nil, timesig_num = 4, timesig_den = 4,
    track_names = {}, regions = {}, markers = {},
    render_file = '', render_pattern = '',
    duration = 0, ext = {},
  }
  local stack = {}
  local region_open = {}   -- id -> запись региона, ждущая парной строки-конца
  local cur_item = nil

  for line in f:lines() do
    local s = line:match('^%s*(.-)%s*$')
    local first = s:sub(1, 1)
    if first == '<' then
      local tag = s:match('^<([%u%d_]+)') or '?'
      local parent = stack[#stack]
      stack[#stack + 1] = tag
      if tag == 'TRACK' and parent == 'REAPER_PROJECT' then
        card.track_names[#card.track_names + 1] = ''
      elseif tag == 'ITEM' then
        cur_item = { pos = 0, len = 0 }
      end
    elseif s == '>' then
      local top = stack[#stack]
      if top == 'ITEM' and cur_item then
        local fin = cur_item.pos + cur_item.len
        if fin > card.duration then card.duration = fin end
        cur_item = nil
      end
      stack[#stack] = nil
    elseif first ~= '' then
      local depth = #stack
      local top = stack[depth]
      if top == 'REAPER_PROJECT' then
        if s:sub(1, 6) == 'MARKER' then
          local t = M.tokenize_rpp_line(s)
          local id, pos, name, flag = t[2], tonumber(t[3]), t[4] or '', tonumber(t[5]) or 0
          if pos then
            if flag % 2 == 1 then -- регион: две строки MARKER с одним id
              local open = region_open[id]
              if open then
                open.fin = pos
                region_open[id] = nil
              else
                local r = { name = name, pos = pos, fin = pos }
                card.regions[#card.regions + 1] = r
                region_open[id] = r
              end
            else
              card.markers[#card.markers + 1] = { name = name, pos = pos }
            end
          end
        elseif s:sub(1, 6) == 'TEMPO ' then
          local t = M.tokenize_rpp_line(s)
          card.tempo = tonumber(t[2])
          card.timesig_num = tonumber(t[3]) or 4
          card.timesig_den = tonumber(t[4]) or 4
        elseif s:sub(1, 12) == 'RENDER_FILE ' then
          card.render_file = M.tokenize_rpp_line(s)[2] or ''
        elseif s:sub(1, 15) == 'RENDER_PATTERN ' then
          card.render_pattern = M.tokenize_rpp_line(s)[2] or ''
        end
      elseif top == 'TRACK' and stack[depth - 1] == 'REAPER_PROJECT' then
        if s:sub(1, 5) == 'NAME ' or s == 'NAME' then
          card.track_names[#card.track_names] = M.tokenize_rpp_line(s)[2] or ''
        end
      elseif top == 'ITEM' and cur_item then
        if s:sub(1, 9) == 'POSITION ' then
          cur_item.pos = tonumber(s:sub(10)) or 0
        elseif s:sub(1, 7) == 'LENGTH ' then
          cur_item.len = tonumber(s:sub(8)) or 0
        end
      elseif top == M.NAMESPACE and stack[depth - 1] == 'EXTSTATE' then
        local t = M.tokenize_rpp_line(s)
        if t[1] then card.ext[t[1]] = t[2] or '' end
      end
    end
  end
  f:close()

  for _, r in ipairs(card.regions) do
    if r.fin > card.duration then card.duration = r.fin end
  end
  card.track_count = #card.track_names
  return card
end

-- ===========================================================================
-- Файловая система (только внутри Reaper)
-- ===========================================================================

function M.file_size(path)
  local f = io.open(path, 'rb')
  if not f then return 0 end
  local size = f:seek('end') or 0
  f:close()
  return size
end

-- Рекурсивный размер папки (аудио, рендеры, бэкапы). Сабдиры собираются
-- в список до рекурсии: EnumerateFiles/EnumerateSubdirectories кэшируют
-- по одной директории, интерливинг сбрасывал бы кэш.
function M.dir_size(dir)
  local total, subs, i = 0, {}, 0
  while true do
    local fn = reaper.EnumerateFiles(dir, i)
    if not fn then break end
    total = total + M.file_size(dir .. '/' .. fn)
    i = i + 1
  end
  i = 0
  while true do
    local sub = reaper.EnumerateSubdirectories(dir, i)
    if not sub then break end
    subs[#subs + 1] = sub
    i = i + 1
  end
  for _, sub in ipairs(subs) do
    total = total + M.dir_size(dir .. '/' .. sub)
  end
  return total
end

function M.file_mtime(path)
  -- js_ReaScriptAPI установлен (см. handover); формат modifiedTime проверить
  -- на железе — подстраховано разбором и unix-ts, и ISO-строки.
  if reaper.JS_File_Stat then
    local retval, _, _, modified = reaper.JS_File_Stat(path)
    if retval == 0 and modified then
      local num = tonumber(modified)
      if num then return num end
      local y, mo, d, h, mi, sec =
        tostring(modified):match('(%d+)%-(%d+)%-(%d+)[T ](%d+):(%d+):(%d+)')
      if y then
        return os.time{ year = y, month = mo, day = d, hour = h, min = mi, sec = sec }
      end
    end
  end
  if reaper.GetOS():find('OSX') or reaper.GetOS():find('macOS') then
    local out = reaper.ExecProcess('/usr/bin/stat -f %m "' .. path .. '"', 5000)
    if out then
      local ts = out:match('^%d+\n(%d+)')
      if ts then return tonumber(ts) end
    end
  end
  return 0
end

-- Теги Finder через mdls (xattr отдаёт бинарный plist — не использовать).
-- Формат вывода mdls -raw: "(null)" либо "(\n    \"Тег1\",\n    Tag2\n)".
function M.finder_tags(path)
  local os_name = reaper.GetOS()
  if not (os_name:find('OSX') or os_name:find('macOS')) then return {} end
  local out = reaper.ExecProcess(
    '/usr/bin/mdls -raw -name kMDItemUserTags "' .. path .. '"', 5000)
  if not out then return {} end
  local body = out:gsub('^%d+\n', '')
  if body:find('%(null%)') then return {} end
  local tags = {}
  for line in body:gmatch('[^\r\n]+') do
    local tag = line:match('^%s*"?(.-)"?,?%s*$')
    if tag and tag ~= '' and tag ~= '(' and tag ~= ')' then
      tags[#tags + 1] = tag
    end
  end
  return tags
end

-- ===========================================================================
-- Сканирование директорий и индекс
-- ===========================================================================

function M.scan_projects(paths)
  local found = {}
  local function scandir(dir, depth)
    if depth > 6 then return end
    local i = 0
    while true do
      local fn = reaper.EnumerateFiles(dir, i)
      if not fn then break end
      local lower = fn:lower()
      if lower:match('%.rpp$') and not lower:find('autosave', 1, true) then
        found[#found + 1] = dir .. '/' .. fn
      end
      i = i + 1
    end
    local j = 0
    while true do
      local sub = reaper.EnumerateSubdirectories(dir, j)
      if not sub then break end
      if sub:sub(1, 1) ~= '.' and sub ~= 'Backups' then
        scandir(dir .. '/' .. sub, depth + 1)
      end
      j = j + 1
    end
  end
  for _, p in ipairs(paths) do
    p = p:gsub('/+$', '')
    if p ~= '' then scandir(p, 1) end
  end
  return found
end

function M.script_dir()
  local src = debug.getinfo(1, 'S').source:sub(2)
  return src:match('^(.*)[/\\]') or '.'
end

function M.index_path()
  return M.script_dir() .. '/' .. M.INDEX_FILENAME
end

function M.load_index()
  local f = io.open(M.index_path(), 'rb')
  if not f then return { version = 1, updated = 0, projects = {} } end
  local data = f:read('*a')
  f:close()
  local idx = M.json_decode(data)
  if type(idx) ~= 'table' or type(idx.projects) ~= 'table' then
    return { version = 1, updated = 0, projects = {} }
  end
  return idx
end

function M.save_index(idx)
  idx.updated = os.time()
  local f, err = io.open(M.index_path(), 'wb')
  if not f then return nil, err end
  f:write(M.json_encode(idx))
  f:close()
  return true
end

-- Бэкапы проекта: *.rpp-bak / autosave / таймстампы рядом с проектом
-- и в подпапке Backups. Форматы имён проверить на железе.
function M.find_backups(path)
  local dir = path:match('^(.*)[/\\]') or '.'
  local name = path:match('([^/\\]+)$')
  local base = name:gsub('%.[rR][pP][pP]$', '')
  local out = {}
  local function checkdir(d)
    local i = 0
    while true do
      local fn = reaper.EnumerateFiles(d, i)
      if not fn then break end
      if fn ~= name and fn:sub(1, #base) == base then
        local l = fn:lower()
        if l:find('bak', 1, true) or l:find('autosave', 1, true)
           or fn:match('%d%d%d%d%-%d%d%-%d%d') then
          local full = d .. '/' .. fn
          out[#out + 1] = {
            file = fn, mtime = M.file_mtime(full), size = M.file_size(full),
          }
        end
      end
      i = i + 1
    end
  end
  checkdir(dir)
  checkdir(dir .. '/Backups')
  table.sort(out, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
  return out
end

-- Своя картинка-тамбнейл: jf_thumb.png/jpg в папке проекта
function M.find_thumb(path)
  local dir = path:match('^(.*)[/\\]') or '.'
  local i = 0
  while true do
    local fn = reaper.EnumerateFiles(dir, i)
    if not fn then break end
    local l = fn:lower()
    if l == 'jf_thumb.png' or l == 'jf_thumb.jpg' or l == 'jf_thumb.jpeg' then
      return dir .. '/' .. fn
    end
    i = i + 1
  end
  return nil
end

-- Полная карточка одного проекта (парсинг + fs). old_card — из прежнего
-- индекса, оттуда переносятся index-only поля (needs_report).
function M.build_card(path, old_card, dir_sizes)
  local card, err = M.parse_rpp(path)
  if not card then return nil, err end
  card.path = path
  card.name = path:match('([^/\\]+)%.[rR][pP][pP]$') or path
  card.mtime = M.file_mtime(path)
  card.size = M.file_size(path)
  local dir = path:match('^(.*)[/\\]') or '.'
  if dir_sizes and dir_sizes[dir] then
    card.dir_size = dir_sizes[dir]
  else
    card.dir_size = M.dir_size(dir)
    if dir_sizes then dir_sizes[dir] = card.dir_size end
  end
  card.fs_tags = M.finder_tags(path)
  card.backups = M.find_backups(path)
  card.thumb_file = M.find_thumb(path)
  card.needs_report = old_card and old_card.needs_report or false
  return card
end

function M.build_index(paths, old_index)
  local idx = { version = 1, updated = 0, projects = {} }
  local old = old_index and old_index.projects or {}
  local dir_sizes = {} -- кэш: несколько .rpp в одной папке — один обход
  for _, p in ipairs(M.scan_projects(paths)) do
    local card = M.build_card(p, old[p], dir_sizes)
    if card then idx.projects[p] = card end
  end
  return idx
end

-- ===========================================================================
-- Настройки (глобальный extstate, переживает рестарт Reaper)
-- ===========================================================================

function M.get_setting(key)
  return reaper.GetExtState(M.EXT_SECTION, key)
end

function M.set_setting(key, val)
  reaper.SetExtState(M.EXT_SECTION, key, val, true)
end

-- Ключи настроек: scan_paths (директории проектов через ;),
-- stems_path (расслоение на мультитреки), regions_path (расслоение
-- на регионы), thumb_style ('0' калейдоскоп / '1' иероглиф)

function M.get_scan_paths_str()
  return M.get_setting('scan_paths')
end

function M.set_scan_paths_str(str)
  M.set_setting('scan_paths', str)
end

function M.get_scan_paths()
  local out = {}
  for p in M.get_scan_paths_str():gmatch('[^;]+') do
    p = p:match('^%s*(.-)%s*$')
    if p ~= '' then out[#out + 1] = p end
  end
  return out
end

-- Расшифровка полей extstate карточки в удобный вид
function M.card_meta(card)
  local ext = card.ext or {}
  local tags = {}
  for t in (ext.TAGS or ''):gmatch('[^,]+') do
    t = t:match('^%s*(.-)%s*$')
    if t ~= '' then tags[#tags + 1] = t end
  end
  return {
    status = ext.STATUS or '',
    desc = ext.DESC and M.decode_ml(ext.DESC) or '',
    tags = tags,
    report_done = ext.REPORT_DONE and M.decode_ml(ext.REPORT_DONE) or '',
    report_todo = ext.REPORT_TODO and M.decode_ml(ext.REPORT_TODO) or '',
    report_log = ext.REPORT_LOG and M.decode_ml(ext.REPORT_LOG) or '',
    report_ts = tonumber(ext.REPORT_TS) or 0,
  }
end

return M
