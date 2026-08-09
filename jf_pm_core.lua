-- jf_pm_core.lua
-- Общий модуль JF Project Manager: парсер .rpp, JSON, индекс, настройки.
-- Загружается без глобального `reaper` (для тестов): reaper.* только внутри функций.

local M = {}

M.NAMESPACE = 'JF_PM'          -- namespace project extstate в .rpp
M.EXT_SECTION = 'JF_PM'        -- секция глобального extstate (настройки)
M.INDEX_FILENAME = 'jf_pm_index.json'

-- Класс описывает МАТЕРИАЛ проекта («что внутри»), а не долг («что должен»).
-- Императивов нет намеренно: «доделать» читается как невыполненное
-- обязательство и держит внимание открытой петлёй.
-- Пайплайн: зерно → джем → ритм → луп → аранжировка → микс → мастер → издано.
-- Вне пайплайна: «на расслоение» (очередь на разбор), «семплпак» (разобран),
-- «покой» (закрыт сознательно).
M.STATUSES = { 'зерно', 'джем', 'ритм', 'луп', 'аранжировка', 'микс',
               'мастер', 'издано', 'на расслоение', 'семплпак', 'покой' }
M.PIPELINE = { ['зерно'] = 1, ['джем'] = 2, ['ритм'] = 3, ['луп'] = 4,
               ['аранжировка'] = 5, ['микс'] = 6, ['мастер'] = 7,
               ['издано'] = 8 }
M.PIPELINE_STEPS = 8
-- 0xRRGGBBAA для ReaImGui
M.STATUS_COLORS = {
  ['зерно']       = 0x8A8A8AFF,
  ['джем']        = 0xB58AD9FF,
  ['ритм']        = 0xD98A8AFF,
  ['луп']         = 0x7BB8D9FF,
  ['аранжировка'] = 0xD9B96CFF,
  ['микс']        = 0xE8E8E8FF,
  ['мастер']      = 0xC98AD9FF,
  ['издано']      = 0x7FD98AFF,
  ['на расслоение'] = 0xD98ABDFF,
  ['семплпак']    = 0x7BD9D0FF,
  ['покой']       = 0x5F5F5FFF,
}
-- отображение классов на английском (данные в .rpp остаются каноничными)
M.STATUS_EN = {
  ['зерно'] = 'seed', ['джем'] = 'jam', ['ритм'] = 'beat', ['луп'] = 'loop',
  ['аранжировка'] = 'arrangement', ['микс'] = 'mix', ['мастер'] = 'master',
  ['издано'] = 'out', ['на расслоение'] = 'to harvest',
  ['семплпак'] = 'samplepack', ['покой'] = 'rest',
}
-- Чужие DAW: расширение → тип. Список из jf_dawsync.lua пользователя.
-- is_dir: проект — пакет-папка (Logic), внутрь при скане не заходим.
M.DAW_TYPES = {
  als       = { daw = 'ableton',  label = 'Ab', color = 0xB8D97BFF },
  flp       = { daw = 'flstudio', label = 'FL', color = 0xD9A87BFF },
  xrns      = { daw = 'renoise',  label = 'Rn', color = 0x7BD9D0FF },
  ptx       = { daw = 'protools', label = 'PT', color = 0x9A7BD9FF },
  ptf       = { daw = 'protools', label = 'PT', color = 0x9A7BD9FF },
  logicx    = { daw = 'logic',    label = 'Lg', color = 0x7FD98AFF, is_dir = true },
  bwproject = { daw = 'bitwig',   label = 'Bw', color = 0xD98A8AFF },
  npr       = { daw = 'nuendo',   label = 'Nu', color = 0x8AA0D9FF },
  pd        = { daw = 'puredata', label = 'Pd', color = 0xE8E8E8FF },
  maxpat    = { daw = 'max',      label = 'Mx', color = 0x8A8F93FF },
}

-- легаси-статусы из старых .rpp → новые классы (нормализуются в card_meta).
-- Файлы не переписываются: миграция ленивая, на чтении.
M.STATUS_ALIASES = {
  ['набросок'] = 'зерно',       ['идея'] = 'зерно',
  ['в работе'] = 'аранжировка', ['доделать'] = 'аранжировка',
  ['к миксу'] = 'микс',         ['отмиксить'] = 'микс',
  ['мастеринг'] = 'мастер',
  ['готово'] = 'издано',
  ['заморожено'] = 'покой',     ['архив'] = 'покой',
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
    duration = 0, ext = {}, items = {},
    notes = '', track_notes = {}, item_notes = {},
    item_count = 0,
  }
  local MAX_ITEMS = 800      -- кап карты айтемов, чтобы индекс не разбухал
  local MAX_NOTE_ITEMS = 200 -- кап заметок айтемов
  local note_buf, note_parent = nil, nil
  local stack = {}
  local region_open = {}   -- id -> запись региона, ждущая парной строки-конца
  local cur_item = nil
  local tempo_pts = {}     -- bpm-точки TEMPOENVEX (span темпа)
  local file_names = {}    -- basename'ы FILE-ссылок (детект тональностей)
  local file_names_n = 0

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
        cur_item = { pos = 0, len = 0, tr = #card.track_names }
      elseif tag == 'NOTES' then
        -- заметки: |строки; хозяин — проект, трек или айтем
        note_buf, note_parent = {}, parent
      end
    elseif s == '>' then
      local top = stack[#stack]
      if top == 'NOTES' and note_buf then
        local text = table.concat(note_buf, '\n')
        if text ~= '' then
          if note_parent == 'REAPER_PROJECT' then
            card.notes = text
          elseif note_parent == 'TRACK' then
            card.track_notes[#card.track_notes + 1] =
              { t = #card.track_names, s = text }
          elseif note_parent == 'ITEM' and cur_item then
            cur_item.note = text
          end
        end
        note_buf, note_parent = nil, nil
      end
      if top == 'ITEM' and cur_item then
        card.item_count = card.item_count + 1
        local fin = cur_item.pos + cur_item.len
        if fin > card.duration then card.duration = fin end
        -- карта айтемов для тамбнейла-навигатора: {t трек, p позиция, l длина}
        if cur_item.tr > 0 and cur_item.len > 0 and #card.items < MAX_ITEMS then
          card.items[#card.items + 1] = {
            t = cur_item.tr,
            p = math.floor(cur_item.pos * 10 + 0.5) / 10,
            l = math.floor(cur_item.len * 10 + 0.5) / 10,
          }
        end
        if cur_item.note and #card.item_notes < MAX_NOTE_ITEMS then
          card.item_notes[#card.item_notes + 1] = {
            t = cur_item.tr,
            p = math.floor(cur_item.pos * 10 + 0.5) / 10,
            s = cur_item.note:sub(1, 400),
          }
        end
        cur_item = nil
      end
      stack[#stack] = nil
    elseif first ~= '' then
      local depth = #stack
      local top = stack[depth]
      if top == 'TEMPOENVEX' and s:sub(1, 3) == 'PT ' then
        local bpm = tonumber(M.tokenize_rpp_line(s)[3])
        if bpm and bpm > 0 then tempo_pts[#tempo_pts + 1] = bpm end
      elseif s:sub(1, 5) == 'FILE ' and file_names_n < 400 then
        local fn = M.tokenize_rpp_line(s)[2]
        if fn and fn ~= '' then
          file_names_n = file_names_n + 1
          file_names[file_names_n] = fn:match('([^/\\]+)$') or fn
        end
      end
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
      elseif top == 'NOTES' and note_buf then
        if s:sub(1, 1) == '|' then note_buf[#note_buf + 1] = s:sub(2) end
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

  -- span темпа: базовый TEMPO + все точки огибающей
  local mn, mx = card.tempo, card.tempo
  for _, b in ipairs(tempo_pts) do
    if not mn or b < mn then mn = b end
    if not mx or b > mx then mx = b end
  end
  card.bpm_min, card.bpm_max = mn, mx

  -- тональности: имя проекта/регионы/маркеры/треки (свободный матч),
  -- имена FILE — только с явным min/maj (иначе питчи семплов дают мусор)
  local keys, seen = {}, {}
  local function add_keys(str, strict)
    if not str or str == '' or #keys >= 4 then return end
    for _, k in ipairs(M.find_keys_in(str, strict)) do
      if not seen[k] and #keys < 4 then
        seen[k] = true
        keys[#keys + 1] = k
      end
    end
  end
  add_keys(path:match('([^/\\]+)%.[rR][pP][pP]$'), false)
  for _, r in ipairs(card.regions) do add_keys(r.name, false) end
  for _, mk in ipairs(card.markers) do add_keys(mk.name, false) end
  for _, tn in ipairs(card.track_names) do add_keys(tn, false) end
  for _, fn in ipairs(file_names) do add_keys(fn, true) end
  card.keys = keys

  return card
end

-- ===========================================================================
-- BPM из имени и тональности из строк
-- ===========================================================================

-- '[160]' или '160bpm' в имени проекта → число (40..300)
function M.name_bpm(name)
  if not name then return nil end
  for num in name:gmatch('%[(%d+%.?%d*)%]') do
    local b = tonumber(num)
    if b and b >= 40 and b <= 300 then return b end
  end
  local b = tonumber(name:match('%f[%d](%d+%.?%d*)%s*[bB][pP][mM]'))
  if b and b >= 40 and b <= 300 then return b end
  return nil
end

-- эффективный bpm карточки: тег в имени приоритетнее TEMPO из .rpp
function M.card_bpm(card)
  return M.name_bpm(card.name) or card.tempo
end

-- Тональности в строке: 'Amin', 'F#m', 'Db maj', 'C#'…
-- strict=true (имена файлов): нужен явный суффикс m/min/maj —
-- голые 'C#4' это питчи семплов, не тональности.
-- Нормализация: минор → 'Am', мажор → 'A'.
function M.find_keys_in(str, strict)
  local out = {}
  if not str then return out end
  local norm = str:gsub('[%-_%.]', ' ')
  -- склейка 'A min'/'F# maj' в одно слово
  norm = norm:gsub('([A-Ga-g][#b]?)%s+(m[ia][jn]o?r?)', '%1%2')
  for w in norm:gmatch('%S+') do
    local note, acc, suf = w:match('^([A-Ga-g])([#b]?)(%a*)$')
    if note then
      suf = suf:lower()
      local minor = (suf == 'm' or suf == 'min' or suf == 'minor')
      local major = (suf == 'maj' or suf == 'major')
      local bare = (suf == '')
      local upper = note:match('%u') ~= nil
      local ok
      if minor or major then
        ok = true
      elseif bare and acc ~= '' and upper and not strict then
        ok = true -- 'F#' в имени проекта/региона — принимаем
      end
      if ok then
        local k = note:upper() .. (acc == 'b' and 'b' or acc)
        if minor then k = k .. 'm' end
        out[#out + 1] = k
      end
    end
  end
  return out
end

-- ===========================================================================
-- Аудиофайлы в папке проекта (детект пустых проектов)
-- ===========================================================================

M.AUDIO_EXT = {
  wav = true, aif = true, aiff = true, flac = true, mp3 = true,
  ogg = true, m4a = true, caf = true, wv = true, opus = true,
}

-- Рекурсивный счётчик аудиофайлов (ранний выход: больше 99 не считаем)
function M.dir_audio_count(dir, depth)
  depth = depth or 1
  if depth > 6 then return 0 end
  local count, subs = 0, {}
  local i = 0
  while true do
    local fn = reaper.EnumerateFiles(dir, i)
    if not fn then break end
    local ext = fn:match('%.([%a%d]+)$')
    if ext and M.AUDIO_EXT[ext:lower()] then
      count = count + 1
      if count > 99 then return count end
    end
    i = i + 1
  end
  i = 0
  while true do
    local sub = reaper.EnumerateSubdirectories(dir, i)
    if not sub then break end
    if sub:sub(1, 1) ~= '.' then subs[#subs + 1] = sub end
    i = i + 1
  end
  for _, sub in ipairs(subs) do
    count = count + M.dir_audio_count(dir .. '/' .. sub, depth + 1)
    if count > 99 then return count end
  end
  return count
end

-- Пустой проект: нет ни одного айтема ИЛИ ни одного аудиофайла в папке.
-- Поля могут отсутствовать в старом индексе — тогда не помечаем.
function M.is_empty_project(card)
  if card.daw then return false end -- чужая DAW: содержимое не парсим
  if card.item_count ~= nil and card.item_count == 0 then return true end
  if card.audio_files ~= nil and card.audio_files == 0 then return true end
  return false
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

-- Время последнего открытия (atime): REAPER читает .rpp при открытии,
-- поэтому atime = «когда последний раз открывал». macOS обновляет atime
-- лениво, но для сортировки по дням этого достаточно.
function M.file_atime(path)
  if reaper.JS_File_Stat then
    local retval, _, _, _, accessed = reaper.JS_File_Stat(path)
    if retval == 0 and accessed then
      local num = tonumber(accessed)
      if num then return num end
      local y, mo, d, h, mi, sec =
        tostring(accessed):match('(%d+)%-(%d+)%-(%d+)[T ](%d+):(%d+):(%d+)')
      if y then
        return os.time{ year = y, month = mo, day = d, hour = h, min = mi, sec = sec }
      end
    end
  end
  local out = reaper.ExecProcess('/usr/bin/stat -f %a "' .. path .. '"', 5000)
  if out then
    local ts = out:match('^%d+\n(%d+)')
    if ts then return tonumber(ts) end
  end
  return 0
end

-- Список недавних проектов REAPER (reaper.ini, recentNN=path) — порядок
-- открытия для тех, кто в него попал. Возвращает {path_lower -> ранг}.
function M.recent_projects()
  local ini = reaper.GetResourcePath() .. '/reaper.ini'
  local f = io.open(ini, 'rb')
  if not f then return {} end
  local out = {}
  for line in f:lines() do
    local n, p = line:match('^recent(%d+)=(.+)$')
    if n and p and p ~= '' then out[p:lower()] = tonumber(n) end
  end
  f:close()
  return out
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
  local found, foreign = {}, {}
  local function scandir(dir, depth)
    if depth > 6 then return end
    local i = 0
    while true do
      local fn = reaper.EnumerateFiles(dir, i)
      if not fn then break end
      local lower = fn:lower()
      if lower:match('%.rpp$') and not lower:find('autosave', 1, true) then
        found[#found + 1] = dir .. '/' .. fn
      else
        local e = lower:match('%.([%w]+)$')
        if e and M.DAW_TYPES[e] and not M.DAW_TYPES[e].is_dir
           -- автосейвы/бэкапы чужих DAW: FL «autosaved/overwritten»,
           -- Pro Tools .bak.NNN, Renoise _Backups-копии
           and not lower:find('autosaved', 1, true)
           and not lower:find('overwritten', 1, true)
           and not lower:find('%.bak%.') then
          foreign[#foreign + 1] = { path = dir .. '/' .. fn, ext = e }
        end
      end
      i = i + 1
    end
    local j = 0
    while true do
      local sub = reaper.EnumerateSubdirectories(dir, j)
      if not sub then break end
      local se = sub:lower():match('%.([%w]+)$')
      if se and M.DAW_TYPES[se] and M.DAW_TYPES[se].is_dir then
        -- пакет-папка (Logic .logicx) — сам проект, внутрь не идём
        foreign[#foreign + 1] = { path = dir .. '/' .. sub, ext = se }
      elseif sub:sub(1, 1) ~= '.' and not sub:match('^Backup')
          and not sub:find('Backups', 1, true) then
        -- Backup/Backup_N/…_Backups/Session File Backups — автосейвы DAW
        scandir(dir .. '/' .. sub, depth + 1)
      end
      j = j + 1
    end
  end
  for _, p in ipairs(paths) do
    p = p:gsub('/+$', '')
    if p ~= '' then scandir(p, 1) end
  end
  return found, foreign
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
            file = fn, dir = d, -- d: папка проекта или Backups/
            mtime = M.file_mtime(full), size = M.file_size(full),
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

-- Своя картинка-тамбнейл в папке проекта: <имя проекта>.png/jpg приоритетнее
-- общего jf_thumb.png (несколько .rpp в папке — у каждого своё превью).
function M.find_thumb(path, base_override)
  local dir = path:match('^(.*)[/\\]') or '.'
  local base = (base_override
    or path:match('([^/\\]+)%.[rR][pP][pP]$') or ''):lower()
  local generic
  local i = 0
  while true do
    local fn = reaper.EnumerateFiles(dir, i)
    if not fn then break end
    local stem, ext = fn:lower():match('^(.+)%.([a-z]+)$')
    if ext == 'png' or ext == 'jpg' or ext == 'jpeg' then
      if base ~= '' and stem == base then return dir .. '/' .. fn end
      if stem == 'jf_thumb' then generic = dir .. '/' .. fn end
    end
    i = i + 1
  end
  return generic
end

-- Полная карточка одного проекта (парсинг + fs). old_card — из прежнего
-- индекса, оттуда переносятся index-only поля (needs_report).
function M.build_card(path, old_card, dir_sizes, dir_audio)
  local card, err = M.parse_rpp(path)
  if not card then return nil, err end
  card.path = path
  card.name = path:match('([^/\\]+)%.[rR][pP][pP]$') or path
  card.mtime = M.file_mtime(path)
  card.atime = M.file_atime(path)
  card.size = M.file_size(path)
  local dir = path:match('^(.*)[/\\]') or '.'
  if dir_sizes and dir_sizes[dir] then
    card.dir_size = dir_sizes[dir]
  else
    card.dir_size = M.dir_size(dir)
    if dir_sizes then dir_sizes[dir] = card.dir_size end
  end
  if dir_audio and dir_audio[dir] then
    card.audio_files = dir_audio[dir]
  else
    card.audio_files = M.dir_audio_count(dir)
    if dir_audio then dir_audio[dir] = card.audio_files end
  end
  card.fs_tags = M.finder_tags(path)
  card.backups = M.find_backups(path)
  card.thumb_file = M.find_thumb(path)
  card.thumb_user = old_card and old_card.thumb_user or nil
  card.needs_report = old_card and old_card.needs_report or false
  if old_card then
    -- index-only поля: закреп, теги из браузера, статус из канбана, лупы
    card.pinned = old_card.pinned
    card.tags_extra = old_card.tags_extra
    card.loops = old_card.loops
    card.pv_offset = old_card.pv_offset
    card.preview_found = old_card.preview_found
    if old_card.status_over
       and (old_card.status_over_base or '') == (card.ext.STATUS or '') then
      card.status_over = old_card.status_over
      card.status_over_base = old_card.status_over_base
    end
  end
  return card
end

-- Карточка проекта чужой DAW: без парсинга содержимого — метаданные файла,
-- теги Finder, превью-картинка/аудио по имени, bpm/тональности из имени.
-- Index-only поля (класс, закреп, теги, превью) работают как у REAPER-карт.
function M.build_foreign_card(path, ext, old_card, dir_sizes)
  local t = M.DAW_TYPES[ext] or {}
  local name = path:match('([^/\\]+)%.' .. ext .. '$')
    or path:match('([^/\\]+)$')
  local card = {
    path = path, daw = t.daw or ext, daw_ext = ext, name = name,
    tempo = nil, timesig_num = 4, timesig_den = 4,
    track_names = {}, regions = {}, markers = {}, items = {},
    notes = '', track_notes = {}, item_notes = {}, backups = {},
    render_file = '', render_pattern = '', duration = 0, ext = {},
  }
  card.mtime = M.file_mtime(path)
  card.atime = M.file_atime(path)
  card.size = M.file_size(path)
  local dir = path:match('^(.*)[/\\]') or '.'
  if dir_sizes and dir_sizes[dir] then
    card.dir_size = dir_sizes[dir]
  else
    card.dir_size = M.dir_size(dir)
    if dir_sizes then dir_sizes[dir] = card.dir_size end
  end
  card.fs_tags = M.finder_tags(path)
  card.thumb_file = M.find_thumb(path, name)
  card.keys = M.find_keys_in(name, false)
  card.needs_report = false
  if old_card then
    card.pinned = old_card.pinned
    card.tags_extra = old_card.tags_extra
    card.thumb_user = old_card.thumb_user
    card.status_over = old_card.status_over
    card.status_over_base = old_card.status_over_base
    card.loops = old_card.loops
    card.pv_offset = old_card.pv_offset
    card.preview_found = old_card.preview_found
  end
  return card
end

function M.build_index(paths, old_index)
  local idx = { version = 1, updated = 0, projects = {} }
  local old = old_index and old_index.projects or {}
  local dir_sizes = {} -- кэш: несколько .rpp в одной папке — один обход
  local dir_audio = {}
  local rpp, foreign = M.scan_projects(paths)
  for _, p in ipairs(rpp) do
    local card = M.build_card(p, old[p], dir_sizes, dir_audio)
    if card then idx.projects[p] = card end
  end
  for _, f in ipairs(foreign) do
    local card = M.build_foreign_card(f.path, f.ext, old[f.path], dir_sizes)
    if card then idx.projects[f.path] = card end
  end
  return idx
end

-- ===========================================================================
-- Правка закрытого .rpp (текстовый уровень)
-- ===========================================================================
-- Для дедлайнов и чекбоксов из карточки: extstate и project notes меняются
-- прямо в тексте файла. Вызывающий обязан проверить, что проект не открыт
-- в REAPER (открытый перезапишет файл при сохранении).

local function read_lines(p)
  local f = io.open(p, 'rb')
  if not f then return nil end
  local out = {}
  for l in f:lines() do out[#out + 1] = l end
  f:close()
  return out
end

local function write_lines(path, lines)
  local f, err = io.open(path, 'wb')
  if not f then return nil, err end
  f:write(table.concat(lines, '\n'), '\n')
  f:close()
  return true
end

local function rpp_quote(v)
  if not v:find('"') then return '"' .. v .. '"'
  elseif not v:find("'") then return "'" .. v .. "'"
  else return '`' .. v .. '`' end
end

-- Ставит key value в блок <EXTSTATE><JF_PM> (создаёт блоки при отсутствии).
function M.set_ext_in_rpp(path, key, value)
  local lines = read_lines(path)
  if not lines then return nil, 'cannot read: ' .. path end
  local depth, in_ext, in_ns = 0, false, false
  local key_line, ns_close, ext_close, proj_close
  for i, line in ipairs(lines) do
    local s = line:match('^%s*(.-)%s*$')
    if s:sub(1, 1) == '<' then
      depth = depth + 1
      local tag = s:match('^<([%u%d_]+)')
      if depth == 2 and tag == 'EXTSTATE' then in_ext = true end
      if depth == 3 and in_ext and tag == M.NAMESPACE then in_ns = true end
    elseif s == '>' then
      if in_ns and depth == 3 then in_ns = false ns_close = ns_close or i end
      if in_ext and depth == 2 then in_ext = false ext_close = ext_close or i end
      if depth == 1 then proj_close = i end
      depth = depth - 1
    elseif in_ns and depth == 3 then
      local t = M.tokenize_rpp_line(s)
      if t[1] == key and not key_line then key_line = i end
    end
  end
  if not proj_close then return nil, 'нет закрывающего >' end

  local kv = key .. ' ' .. rpp_quote(value)
  if key_line then
    local indent = lines[key_line]:match('^(%s*)') or '      '
    lines[key_line] = indent .. kv
  elseif ns_close then
    table.insert(lines, ns_close, '      ' .. kv)
  elseif ext_close then
    table.insert(lines, ext_close, '    <' .. M.NAMESPACE)
    table.insert(lines, ext_close + 1, '      ' .. kv)
    table.insert(lines, ext_close + 2, '    >')
  else
    table.insert(lines, proj_close, '  <EXTSTATE')
    table.insert(lines, proj_close + 1, '    <' .. M.NAMESPACE)
    table.insert(lines, proj_close + 2, '      ' .. kv)
    table.insert(lines, proj_close + 3, '    >')
    table.insert(lines, proj_close + 4, '  >')
  end
  return write_lines(path, lines)
end

-- Ставит/заменяет top-level строку «TOKEN value» (внутри REAPER_PROJECT,
-- вне под-блоков). value = nil — удалить строку. Возвращает старое значение
-- (строку после токена), false — если строки не было, nil+err — ошибка.
function M.set_project_token(path, token, value)
  local lines = read_lines(path)
  if not lines then return nil, 'cannot read: ' .. path end
  local depth, found_i, old, proj_close = 0, nil, nil, nil
  for i, line in ipairs(lines) do
    local s = line:match('^%s*(.-)%s*$')
    if s:sub(1, 1) == '<' then
      depth = depth + 1
    elseif s == '>' then
      if depth == 1 then proj_close = i end
      depth = depth - 1
    elseif depth == 1 and not found_i then
      local v = s:match('^' .. token .. '%s+(.*)$')
      if v then found_i, old = i, v end
    end
  end
  if not proj_close then return nil, 'нет закрывающего >' end
  if found_i then
    if value == nil then
      table.remove(lines, found_i)
    else
      local indent = lines[found_i]:match('^(%s*)')
      lines[found_i] = indent .. token .. ' ' .. value
    end
  elseif value ~= nil then
    table.insert(lines, 2, '  ' .. token .. ' ' .. value)
  end
  local ok, err = write_lines(path, lines)
  if not ok then return nil, err end
  return old or false
end

-- Заменяет project notes (top-level <NOTES>) на text; создаёт блок при
-- отсутствии.
function M.set_project_notes(path, text)
  local lines = read_lines(path)
  if not lines then return nil, 'cannot read: ' .. path end
  local depth = 0
  local n_open, n_close, proj_close
  for i, line in ipairs(lines) do
    local s = line:match('^%s*(.-)%s*$')
    if s:sub(1, 1) == '<' then
      depth = depth + 1
      if depth == 2 and s:match('^<NOTES') and not n_open then n_open = i end
    elseif s == '>' then
      if depth == 2 and n_open and not n_close then n_close = i end
      if depth == 1 then proj_close = i end
      depth = depth - 1
    end
  end
  if not proj_close then return nil, 'нет закрывающего >' end

  local block = {}
  for l in (text .. '\n'):gmatch('(.-)\n') do
    block[#block + 1] = '    |' .. l
  end
  while #block > 0 and block[#block] == '    |' do block[#block] = nil end

  local out = {}
  if n_open then
    for i = 1, n_open do out[#out + 1] = lines[i] end
    for _, b in ipairs(block) do out[#out + 1] = b end
    for i = n_close, #lines do out[#out + 1] = lines[i] end
  else
    for i = 1, proj_close - 1 do out[#out + 1] = lines[i] end
    out[#out + 1] = '  <NOTES 0 2'
    for _, b in ipairs(block) do out[#out + 1] = b end
    out[#out + 1] = '  >'
    for i = proj_close, #lines do out[#out + 1] = lines[i] end
  end
  return write_lines(path, out)
end

-- Пропавшие медиафайлы проекта: FILE-ссылки из текста .rpp, которых нет на
-- диске (проверка до открытия — чтобы батч не спотыкался о модальный диалог
-- REAPER «файлы не найдены»). Относительные пути — от папки проекта; как и
-- REAPER, дополнительно ищем по имени в корне папки проекта.
-- Возвращает список имён (уникальные, максимум 20).
function M.missing_media(path)
  local lines = read_lines(path)
  if not lines then return {} end
  local dir = path:match('^(.*)[/\\]') or '.'
  local seen, missing = {}, {}
  local function exists(p)
    local f = io.open(p, 'rb')
    if f then f:close() return true end
    return false
  end
  for _, line in ipairs(lines) do
    local fn = line:match("^%s*FILE%s+[\"'`](.-)[\"'`]")
    if fn and fn ~= '' and not seen[fn] then
      seen[fn] = true
      local full = fn:match('^/') and fn or (dir .. '/' .. fn)
      if not exists(full) then
        local base = fn:match('([^/\\]+)$') or fn
        if not exists(dir .. '/' .. base) then
          missing[#missing + 1] = base
          if #missing >= 20 then break end
        end
      end
    end
  end
  return missing
end

-- true, если WAV — сплошная цифровая тишина (все сэмплы нулевые).
-- Быстро для нормальных файлов: выход на первом ненулевом байте.
function M.wav_is_silent(path)
  local f = io.open(path, 'rb')
  if not f then return nil, 'cannot open' end
  local head = f:read(12)
  if not head or head:sub(1, 4) ~= 'RIFF' or head:sub(9, 12) ~= 'WAVE' then
    f:close()
    return nil, 'не WAV'
  end
  -- ищем data-чанк
  local doff, dsize
  while true do
    local hdr = f:read(8)
    if not hdr or #hdr < 8 then break end
    local id = hdr:sub(1, 4)
    local sz = string.unpack('<I4', hdr, 5)
    if id == 'data' then
      doff, dsize = f:seek(), sz
      break
    end
    f:seek('cur', sz + (sz % 2))
  end
  if not doff then f:close() return nil, 'нет data' end
  local left = dsize
  while left > 0 do
    local chunk = f:read(math.min(left, 1 << 20))
    if not chunk then break end
    if chunk:find('[^%z]') then f:close() return false end
    left = left - #chunk
  end
  f:close()
  return true
end

-- Обрезает цифровую тишину (нулевые сэмплы) в начале и хвосте WAV,
-- оставляя max_lead_sec воздуха в начале и max_tail_sec в конце. Тишина
-- рендера — точные нули при любом формате сэмплов (дизеринг в пустоту не
-- пишется), поэтому порог не нужен.
-- Возвращает (true, срезано_в_начале, срезано_в_конце) | false | nil, err.
function M.trim_wav_silence(path, max_lead_sec, max_tail_sec)
  local f = io.open(path, 'rb')
  if not f then return nil, 'cannot open: ' .. tostring(path) end
  local data = f:read('*a')
  f:close()
  if data:sub(1, 4) ~= 'RIFF' or data:sub(9, 12) ~= 'WAVE' then
    return nil, 'не WAV'
  end
  local pos = 13
  local srate, balign, doff, dsize
  while pos + 8 <= #data do
    local id = data:sub(pos, pos + 3)
    local sz = string.unpack('<I4', data, pos + 4)
    if id == 'fmt ' then
      srate = string.unpack('<I4', data, pos + 12)
      balign = string.unpack('<I2', data, pos + 20)
    elseif id == 'data' then
      doff, dsize = pos + 8, sz
      break -- data обычно последний; чанки после него не сохраняем
    end
    pos = pos + 8 + sz + (sz % 2)
  end
  if not (srate and balign and doff) or balign == 0 or srate == 0 then
    return nil, 'нет fmt/data'
  end
  if doff + dsize - 1 > #data then dsize = #data - doff + 1 end

  local BLOCK = 1 << 20
  -- первый ненулевой байт, с начала блоками
  local first_nz = 0
  local i = doff
  local dend = doff + dsize - 1
  while i <= dend do
    local j = math.min(dend, i + BLOCK - 1)
    local k = data:sub(i, j):find('[^%z]')
    if k then first_nz = i + k - 1 break end
    i = j + 1
  end
  if first_nz == 0 then return false end -- сплошная тишина — не трогаем
  -- последний ненулевой байт, с конца блоками
  local last_nz = 0
  i = dend
  while i >= doff do
    local j = math.max(doff, i - BLOCK + 1)
    local chunk = data:sub(j, i)
    if chunk:find('[^%z]') then
      for k = #chunk, 1, -1 do
        if chunk:byte(k) ~= 0 then
          last_nz = j + k - 1
          break
        end
      end
      break
    end
    i = j - 1
  end

  local frames_total = math.floor(dsize / balign)
  local first_frame = math.floor((first_nz - doff) / balign)      -- 0-based
  local sound_end = math.ceil((last_nz - doff + 1) / balign)      -- счёт кадров
  local skip = math.max(0,
    first_frame - math.floor(srate * (max_lead_sec or 0.5)))
  local keep_end = math.min(frames_total,
    sound_end + math.floor(srate * (max_tail_sec or 1)))
  if skip == 0 and keep_end >= frames_total then return false end

  local new_dsize = (keep_end - skip) * balign
  local new_head = data:sub(1, doff - 5) .. string.pack('<I4', new_dsize)
  local riff_size = #new_head - 8 + new_dsize
  local out, err = io.open(path, 'wb')
  if not out then return nil, err end
  out:write('RIFF', string.pack('<I4', riff_size), new_head:sub(9))
  local start = doff + skip * balign
  out:write(data:sub(start, start + new_dsize - 1))
  out:close()
  return true, skip / srate, (frames_total - keep_end) / srate
end

-- ===========================================================================
-- Переименование проекта
-- ===========================================================================
-- Переименовывает всё с префиксом старого имени: .rpp, бэкапы (в папке и в
-- Backups/), пики .reapeaks, превью <имя>.png. Папку проекта — только если
-- она названа как проект. Относительные пути внутри .rpp остаются валидными.
-- Все коллизии проверяются ДО первого rename — либо всё, либо ничего.
-- Возвращает (новый путь .rpp, старая папка|nil) либо (nil, err).

function M.rename_project(path, new_name)
  if not new_name or new_name == ''
     or new_name:find('[/\\:]') or new_name:find('^%.') then
    return nil, 'недопустимое имя'
  end
  local dir = path:match('^(.*)[/\\]') or '.'
  local old_base = path:match('([^/\\]+)%.[rR][pP][pP]$')
  if not old_base then return nil, 'не .rpp: ' .. path end
  if new_name == old_base then return nil, 'имя не изменилось' end

  local renames = {}
  local function collect(d)
    local i = 0
    while true do
      local fn = reaper.EnumerateFiles(d, i)
      if not fn then break end
      if fn:sub(1, #old_base) == old_base then
        renames[#renames + 1] = {
          d .. '/' .. fn,
          d .. '/' .. new_name .. fn:sub(#old_base + 1),
        }
      end
      i = i + 1
    end
  end
  collect(dir)
  collect(dir .. '/Backups')

  local parent, dname = dir:match('^(.*)[/\\]([^/\\]+)$')
  local rename_dir = dname == old_base
  if rename_dir then
    local j = 0
    while true do
      local sub = reaper.EnumerateSubdirectories(parent, j)
      if not sub then break end
      if sub == new_name then return nil, 'папка занята: ' .. new_name end
      j = j + 1
    end
  end
  for _, r in ipairs(renames) do
    local f = io.open(r[2], 'rb')
    if f then f:close() return nil, 'файл занят: ' .. r[2] end
  end

  for _, r in ipairs(renames) do
    local ok, err = os.rename(r[1], r[2])
    if not ok then return nil, tostring(err) end
  end
  local new_dir = dir
  if rename_dir then
    new_dir = parent .. '/' .. new_name
    local ok, err = os.rename(dir, new_dir)
    if not ok then return nil, tostring(err) end
  end
  return new_dir .. '/' .. new_name .. '.rpp', rename_dir and dir or nil
end

-- ===========================================================================
-- Слияние проектов (текстовый уровень, проекты не открываются)
-- ===========================================================================
-- Треки всех проектов складываются в один; айтемы и маркеры последующих
-- сдвигаются на суммарную длительность предыдущих, каждый проект получает
-- регион со своим именем. FILE-пути становятся абсолютными (слитый .rpp
-- живёт в другой папке), AUXRECV-индексы смещаются на число треков до них.
-- Ограничения: точки огибающих и BEAT-привязка не сдвигаются, темп — из
-- первого проекта, GUID-ы не перегенерируются (self-merge — на свой риск).

local function q_name(name)
  if not name:find('"') then return '"' .. name .. '"'
  elseif not name:find("'") then return "'" .. name .. "'"
  else return '`' .. name .. '`' end
end

local function abs_file_line(line, dir)
  local head, q, path, tail = line:match("^(%s*FILE%s+)([\"'`])(.-)%2(.*)$")
  if not head then return line end
  if path:sub(1, 1) ~= '/' and path:sub(2, 2) ~= ':' then
    path = dir .. '/' .. path
  end
  return head .. q .. path .. q .. tail
end

-- paths — упорядоченный список .rpp, out_path — куда писать результат.
function M.merge_projects(paths, out_path)
  if #paths < 2 then return nil, 'нужно минимум два проекта' end
  local cards, durs = {}, {}
  for i, p in ipairs(paths) do
    local card, err = M.parse_rpp(p)
    if not card then return nil, err end
    cards[i], durs[i] = card, card.duration or 0
  end

  local base_dir = paths[1]:match('^(.*)[/\\]') or '.'
  local base = read_lines(paths[1])
  if not base then return nil, 'cannot read ' .. paths[1] end
  local close_at
  for i = #base, 1, -1 do
    if base[i]:match('^%s*>%s*$') then close_at = i break end
  end
  if not close_at then return nil, 'нет закрывающего > : ' .. paths[1] end

  local out_lines = {}
  for i = 1, close_at - 1 do
    out_lines[#out_lines + 1] = abs_file_line(base[i], base_dir)
  end

  local offset = durs[1]
  local track_offset = cards[1].track_count or 0
  local extra_markers = {}

  for pi = 2, #paths do
    local dir = paths[pi]:match('^(.*)[/\\]') or '.'
    local lines = read_lines(paths[pi])
    if not lines then return nil, 'cannot read ' .. paths[pi] end
    local depth, in_track = 0, false
    for _, line in ipairs(lines) do
      local s = line:match('^%s*(.-)%s*$')
      local opened = s:sub(1, 1) == '<'
      if opened then
        depth = depth + 1
        if depth == 2 and s:match('^<TRACK') then in_track = true end
      end
      if in_track then
        local l2 = abs_file_line(line, dir)
        local head, num, tail = l2:match('^(%s*POSITION%s+)(%-?[%d%.]+)(.*)$')
        if head then
          l2 = head .. string.format('%.10g', tonumber(num) + offset) .. tail
        else
          local ah, an, at = l2:match('^(%s*AUXRECV%s+)(%d+)(.*)$')
          if ah then l2 = ah .. tostring(tonumber(an) + track_offset) .. at end
        end
        out_lines[#out_lines + 1] = l2
      elseif depth == 1 and s:sub(1, 7) == 'MARKER ' then
        local mh, id, sp, pos, mt =
          line:match('^(%s*MARKER%s+)(%d+)(%s+)(%-?[%d%.]+)(.*)$')
        if mh then
          extra_markers[#extra_markers + 1] = mh .. (tonumber(id) + 1000 * pi)
            .. sp .. string.format('%.10g', tonumber(pos) + offset) .. mt
        end
      end
      if s == '>' then
        depth = depth - 1
        if depth == 1 then in_track = false end
      end
    end
    offset = offset + durs[pi]
    track_offset = track_offset + (cards[pi].track_count or 0)
  end

  -- регион на каждый исходный проект — карта формы слитого файла
  local start = 0
  for i, p in ipairs(paths) do
    local name = p:match('([^/\\]+)%.[rR][pP][pP]$') or p
    local id = 900000 + i
    extra_markers[#extra_markers + 1] =
      string.format('  MARKER %d %.10g %s 1', id, start, q_name(name))
    extra_markers[#extra_markers + 1] =
      string.format('  MARKER %d %.10g "" 1', id, start + durs[i])
    start = start + durs[i]
  end

  for _, m in ipairs(extra_markers) do out_lines[#out_lines + 1] = m end
  out_lines[#out_lines + 1] = '>'

  local f, err = io.open(out_path, 'wb')
  if not f then return nil, err end
  f:write(table.concat(out_lines, '\n'), '\n')
  f:close()
  return true
end

-- ===========================================================================
-- Настройки (глобальный extstate, переживает рестарт Reaper)
-- ===========================================================================

-- Настройки живут в ДВУХ местах: extstate (как раньше) и JSON-файл рядом
-- со скриптом. Файл пишется немедленно и приоритетен при чтении: extstate
-- сбрасывается в reaper.ini только при выходе REAPER, и крэш/вторая копия
-- скрипта теряли пути. Файл эту потерю исключает.
M.SETTINGS_FILENAME = 'jf_pm_settings.json'

local settings_cache
local function settings_path()
  return M.script_dir() .. '/' .. M.SETTINGS_FILENAME
end

local function load_settings_file()
  if settings_cache then return settings_cache end
  local f = io.open(settings_path(), 'rb')
  if f then
    local data = M.json_decode(f:read('*a'))
    f:close()
    settings_cache = type(data) == 'table' and data or {}
  else
    settings_cache = {}
  end
  return settings_cache
end

local function save_settings_file()
  local f = io.open(settings_path(), 'wb')
  if not f then return end
  f:write(M.json_encode(settings_cache or {}))
  f:close()
end

function M.get_setting(key)
  local s = load_settings_file()
  if s[key] ~= nil then return s[key] end
  return reaper.GetExtState(M.EXT_SECTION, key)
end

function M.set_setting(key, val)
  local s = load_settings_file()
  s[key] = val
  save_settings_file()
  reaper.SetExtState(M.EXT_SECTION, key, val, true)
end

-- Ключи настроек: scan_paths (директории проектов через ;),
-- stems_path (расслоение на мультитреки), regions_path (расслоение
-- на регионы), thumb_style ('0' калейдоскоп / '1' иероглиф / '2' навигатор)

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

-- 'дд.мм[.гг[гг]]' → unix ts (12:00). Без года — ближайшая будущая дата.
function M.parse_date(s)
  local d, m, y = s:match('^%s*(%d%d?)%.(%d%d?)%.?(%d*)%s*$')
  if not d then return nil end
  d, m = tonumber(d), tonumber(m)
  if d < 1 or d > 31 or m < 1 or m > 12 then return nil end
  local year
  if y == '' then
    year = os.date('*t').year
    if os.time{ year = year, month = m, day = d, hour = 12 }
       < os.time() - 86400 then
      year = year + 1
    end
  else
    year = tonumber(y)
    if year < 100 then year = year + 2000 end
  end
  return os.time{ year = year, month = m, day = d, hour = 12 }
end

-- Чекбоксы '- [ ] текст' / '- [x] текст' из текста (md-синтаксис)
local function scan_todos(text, src, out)
  local ln = 0
  for line in (text .. '\n'):gmatch('(.-)\n') do
    ln = ln + 1
    local mark, rest = line:match('^%s*[-*]%s*%[([ xXхХ])%]%s*(.*)')
    if mark then
      out[#out + 1] = { done = mark ~= ' ', text = rest, src = src, line = ln }
    end
  end
end

-- Расшифровка полей extstate карточки в удобный вид
function M.card_meta(card)
  local ext = card.ext or {}
  local tags = {}
  for t in (ext.TAGS or ''):gmatch('[^,]+') do
    t = t:match('^%s*(.-)%s*$')
    if t ~= '' then tags[#tags + 1] = t end
  end
  local todo_text = ext.REPORT_TODO and M.decode_ml(ext.REPORT_TODO) or ''
  -- todo из отчёта и из project notes, src помнит источник (для toggle)
  local todos = {}
  scan_todos(todo_text, 'todo', todos)
  scan_todos(card.notes or '', 'notes', todos)
  return {
    deadline = tonumber(ext.DEADLINE) or 0,
    todos = todos,
    -- status_over — решение из канбана/карточки (индекс), пока проект не
    -- открыт; сбрасывается в build_card, если STATUS в .rpp изменился после.
    -- Легаси-статусы нормализуются в новые классы.
    status = (function(s)
      return M.STATUS_ALIASES[s] or s
    end)(card.status_over or ext.STATUS or ''),
    track_id = ext.TRACKID or '',
    samples = ext.SAMPLES and M.decode_ml(ext.SAMPLES) or '',
    desc = ext.DESC and M.decode_ml(ext.DESC) or '',
    tags = tags,
    report_done = ext.REPORT_DONE and M.decode_ml(ext.REPORT_DONE) or '',
    report_todo = ext.REPORT_TODO and M.decode_ml(ext.REPORT_TODO) or '',
    report_log = ext.REPORT_LOG and M.decode_ml(ext.REPORT_LOG) or '',
    report_ts = tonumber(ext.REPORT_TS) or 0,
  }
end

return M
