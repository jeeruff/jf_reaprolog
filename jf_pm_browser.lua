-- jf_pm_browser.lua
-- JF PM: браузер проектов (ReaImGui).
-- Запуск по хоткею из Action List, в фоне не висит.
-- Читает ТОЛЬКО индекс (jf_pm_index.json); Rescan пересобирает индекс
-- парсингом .rpp как текста — проекты не открываются.
--
-- Эргономика: без слайдеров и выпадашек — всё чипами в ширину, не в глубину.
-- Vim-навигация: h/j/k/l — фокус, Enter — раскрыть (вне сетки — открыть),
-- o — открыть, x — в выборку (порядок = порядок merge), p — закрепить,
-- Shift+D — удалить в Корзину, m — merge выборки, / — в поле fzf,
-- g/G — в начало/конец, Esc — свернуть → сброс выборки → сброс фокуса.
-- Канбан: Shift+H/L — перенести карточку в соседний статус, drag&drop мышью.

local VERSION = '0.2'

local SCRIPT_PATH = ({reaper.get_action_context()})[2]
local SCRIPT_DIR = SCRIPT_PATH:match('^(.*)[/\\]')
local core = dofile(SCRIPT_DIR .. '/jf_pm_core.lua')
local gallery = dofile(SCRIPT_DIR .. '/jf_pm_gallery.lua')

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB('Нужен ReaImGui 0.9+ (ReaPack: ReaImGui: ReaScript binding for Dear ImGui).',
    'JF PM', 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.9'

-- ===========================================================================
-- ТЕГИ: правь список прямо здесь. { 'имя', 0xRRGGBBAA }.
-- Тег не из списка тоже работает — цвет получит от хеша имени.
-- ===========================================================================
local TAGS = {
  { 'флейта',      0x7BB8D9FF },
  { 'dungeon',     0x9A7BD9FF },
  { 'EP-кандидат', 0xD9B96CFF },
  { 'амбиент',     0x7BD9A8FF },
  { 'бит',         0xD97B7BFF },
  { 'лайв',        0xD9A87BFF },
  { 'кавер',       0x7BD9D0FF },
  { 'скетч',       0x8A8F93FF },
}
local TAG_COLOR_MAP = {}
for _, e in ipairs(TAGS) do TAG_COLOR_MAP[e[1]] = e[2] end

local ctx = ImGui.CreateContext('JF PM')
local font = ImGui.CreateFont('sans-serif', 14)
local big_font = ImGui.CreateFont('sans-serif', 44) -- для иероглифов-тамбнейлов
ImGui.Attach(ctx, font)
ImGui.Attach(ctx, big_font)

-- ---------------------------------------------------------------------------

local state = {
  index = core.load_index(),
  scan_paths = core.get_setting('scan_paths'),
  stems_path = core.get_setting('stems_path'),
  regions_path = core.get_setting('regions_path'),
  thumb_style = tonumber(core.get_setting('thumb_style')) or 0, -- 0 калейдоскоп, 1 иероглиф
  view = 0,                 -- 0 сетка, 1 таймлайн, 2 календарь, 3 канбан
  filter_status = 0,        -- 0 активные, 1 все, 2 без отчёта, 3.. статусы
  filter_text = '',         -- fzf: имя, теги, треки
  sel = {},                 -- упорядоченный список путей — порядок = порядок merge
  kb_col = 0, kb_row = 0,   -- фокус в канбане
  sort_mode = 1,            -- 1 дата, 2 статус, 3 длительность, 4 имя, 5 размер
  sort_rev = false,         -- клик по активному чипу переворачивает порядок
  expanded = nil,           -- path раскрытой карточки
  focus = 0,                -- индекс карточки в фокусе (vim), 0 = нет
  scroll_to_focus = false,
  focus_tag_input = false,
  status_msg = '',
  show_settings = false,
  cal_scroll_end = 2,       -- кадры доскролла календаря к сегодняшнему краю
  tag_add_path = nil,       -- карточка с открытым полем нового тега
  tag_add_text = '',
}

local STATUS_ORDER = {}
for i, s in ipairs(core.STATUSES) do STATUS_ORDER[s] = i end

local SORT_CHIPS = { 'дата', 'статус', 'длительность', 'имя', 'размер' }
-- естественное направление: true = по убыванию (новое/большое сверху)
local SORT_DESC_NATURAL = { true, false, true, false, true }
local VIEW_CHIPS = { 'сетка', 'таймлайн', 'календарь', 'канбан' }

-- радикалы Канси для тамбнейлов-иероглифов
local RADICALS = {
  '山','川','水','火','木','金','土','日','月','風','雨','雷','雲','雪','氷',
  '龍','鳥','魚','馬','鹿','虫','鬼','心','手','足','目','耳','口','骨','血',
  '人','女','子','母','父','老','鼓','音','言','歌','舞','弓','刀','矛','斧',
  '門','戶','井','田','里','谷','林','森','岩','石','沙','泉','海','波','潮',
  '光','影','闇','夜','夢','霧','煙','灰','炎','燈','星','空','天','地','原',
  '花','草','竹','米','麥','豆','瓜','桑','梅','蘭','菊','苔','根','葉','實',
  '絲','網','布','衣','革','皮','角','爪','牙','羽','毛','殼','壺','皿','鼎',
}

local function fmt_duration(sec)
  if not sec or sec <= 0 then return '—' end
  return string.format('%d:%02d', math.floor(sec / 60), math.floor(sec % 60))
end

local function fmt_date(ts)
  if not ts or ts == 0 then return '—' end
  return os.date('%d.%m.%y %H:%M', ts)
end

local function fmt_size(bytes)
  if not bytes or bytes <= 0 then return '?' end
  if bytes >= 1073741824 then return string.format('%.1f ГБ', bytes / 1073741824) end
  if bytes >= 1048576 then return string.format('%.1f МБ', bytes / 1048576) end
  return string.format('%d КБ', math.max(1, math.floor(bytes / 1024)))
end

local function trunc(s, n)
  local len = utf8.len(s)
  if len and len > n then
    return s:sub(1, utf8.offset(s, n + 1) - 1) .. '…'
  end
  return s
end

local function fnv1a(str)
  local h = 2166136261
  for i = 1, #str do
    h = ((h ~ str:byte(i)) * 16777619) & 0xFFFFFFFF
  end
  return h
end

local function hash_color(h, s, v)
  local r, g, b = ImGui.ColorConvertHSVtoRGB((h % 360) / 360, s or 0.5, v or 0.92)
  return ImGui.ColorConvertDouble4ToU32(r, g, b, 1.0)
end

local function all_tags(card, meta)
  local seen, out = {}, {}
  for _, t in ipairs(meta.tags) do
    if not seen[t] then seen[t] = true; out[#out + 1] = t end
  end
  for _, t in ipairs(card.fs_tags or {}) do
    if not seen[t] then seen[t] = true; out[#out + 1] = t end
  end
  for _, t in ipairs(card.tags_extra or {}) do
    if not seen[t] then seen[t] = true; out[#out + 1] = t end
  end
  return out
end

local function tag_color(t)
  return TAG_COLOR_MAP[t] or hash_color(fnv1a(t) % 360, 0.4, 0.8)
end

-- ---------------------------------------------------------------------------
-- fzf: подпоследовательность по имени, тегам и трекам всех проектов.
-- string.lower не знает кириллицу — свой utf8-lower для А-Я/Ё.

local function ulower(s)
  return (s:gsub('[\194-\244][\128-\191]*', function(ch)
    if #ch ~= 2 then return ch end
    local b1, b2 = ch:byte(1, 2)
    local cp = (b1 - 0xC0) * 64 + (b2 - 0x80)
    if cp >= 0x410 and cp <= 0x42F then cp = cp + 0x20      -- А-Я → а-я
    elseif cp == 0x401 then cp = 0x451                       -- Ё → ё
    else return ch end
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  end)):lower()
end

local function to_codes(s)
  local t = {}
  for _, c in utf8.codes(s) do t[#t + 1] = c end
  return t
end

local function fuzzy_match(needle_codes, hay)
  if #needle_codes == 0 then return true end
  local k = 1
  for _, c in utf8.codes(hay) do
    if c == needle_codes[k] then
      k = k + 1
      if k > #needle_codes then return true end
    end
  end
  return false
end

-- кэш поисковой строки на карточку (не пересобирать каждый кадр);
-- инвалидация: rescan и правка тегов
local search_cache = {}
local function search_text(card, meta)
  local s = search_cache[card.path]
  if not s then
    s = ulower(card.name .. ' ' .. table.concat(all_tags(card, meta), ' ')
      .. ' ' .. table.concat(card.track_names or {}, ' '))
    search_cache[card.path] = s
  end
  return s
end

-- ---------------------------------------------------------------------------
-- Выбор (порядок выделения = порядок merge)

local function sel_index(path)
  for i, p in ipairs(state.sel) do if p == path then return i end end
  return nil
end

local function toggle_select(path)
  local i = sel_index(path)
  if i then table.remove(state.sel, i) else state.sel[#state.sel + 1] = path end
end

-- ---------------------------------------------------------------------------

local function collect_cards()
  local cards = {}
  local needle_codes
  if state.filter_text ~= '' then
    local okc, codes = pcall(to_codes, ulower(state.filter_text))
    needle_codes = okc and codes or nil
  end
  for _, card in pairs(state.index.projects) do
    local meta = core.card_meta(card)
    local ok = true
    local f = state.filter_status
    if f == 0 then
      ok = meta.status ~= 'архив'
    elseif f == 2 then
      ok = card.needs_report or meta.report_ts == 0
    elseif f >= 3 then
      ok = meta.status == core.STATUSES[f - 2]
    end
    if ok and needle_codes then
      local okm, m = pcall(fuzzy_match, needle_codes, search_text(card, meta))
      ok = okm and m
    end
    if ok then cards[#cards + 1] = { card = card, meta = meta } end
  end

  local m = state.sort_mode
  local function less(a, b)
    if m == 2 then
      local oa = STATUS_ORDER[a.meta.status] or 99
      local ob = STATUS_ORDER[b.meta.status] or 99
      if oa ~= ob then return oa < ob end
    elseif m == 3 then
      if (a.card.duration or 0) ~= (b.card.duration or 0) then
        return (a.card.duration or 0) > (b.card.duration or 0)
      end
    elseif m == 4 then
      if a.card.name:lower() ~= b.card.name:lower() then
        return a.card.name:lower() < b.card.name:lower()
      end
    elseif m == 5 then
      local sa = a.card.dir_size or a.card.size or 0
      local sb = b.card.dir_size or b.card.size or 0
      if sa ~= sb then return sa > sb end
    end
    if (a.card.mtime or 0) ~= (b.card.mtime or 0) then
      return (a.card.mtime or 0) > (b.card.mtime or 0)
    end
    return a.card.name < b.card.name
  end
  table.sort(cards, function(a, b)
    -- закреплённые — всегда сверху, затем проекты без отчёта
    local pa = a.card.pinned and 1 or 0
    local pb = b.card.pinned and 1 or 0
    if pa ~= pb then return pa > pb end
    local na = a.card.needs_report and 1 or 0
    local nb = b.card.needs_report and 1 or 0
    if na ~= nb then return na > nb end
    if state.sort_rev then return less(b, a) end
    return less(a, b)
  end)
  return cards
end

local function rescan()
  local paths = core.get_scan_paths()
  if #paths == 0 then
    state.status_msg = 'Укажи директории проектов (кнопка «настройки»)'
    state.show_settings = true
    return
  end
  local t0 = reaper.time_precise()
  state.index = core.build_index(paths, state.index)
  core.save_index(state.index)
  search_cache = {}
  local n = 0
  for _ in pairs(state.index.projects) do n = n + 1 end
  state.status_msg = string.format('Rescan: %d проектов за %.1f c', n,
    reaper.time_precise() - t0)
end

-- Экспорт текущего вида (фильтры и сортировка учтены) в автономный HTML
local function export_gallery()
  local out = SCRIPT_DIR .. '/jf_pm_gallery.html'
  local ok, err = gallery.export(core, collect_cards(), out)
  if not ok then
    state.status_msg = 'Галерея: ' .. tostring(err)
    return
  end
  state.status_msg = 'Галерея: ' .. out
  if reaper.CF_ShellExecute then
    reaper.CF_ShellExecute(out)
  else
    reaper.ExecProcess('/usr/bin/open "' .. out .. '"', -1)
  end
end

local function open_project(path)
  reaper.Main_OnCommand(40859, 0) -- New project tab
  reaper.Main_openProject(path)
end

-- Статус из канбана: живёт в индексе, пока проект не открыт и отчёт
-- не перезаписал STATUS в .rpp (см. build_card).
local function set_status(card, status)
  if status == '' then
    card.status_over, card.status_over_base = nil, nil
  else
    card.status_over = status
    card.status_over_base = (card.ext or {}).STATUS or ''
  end
  core.save_index(state.index)
end

local function toggle_pin(card)
  card.pinned = not card.pinned or nil
  core.save_index(state.index)
end

-- В Корзину (с возможностью «вернуть обратно»): Finder на macOS, gio на Linux
local function trash_path(target)
  local os_name = reaper.GetOS()
  if os_name:find('OSX') or os_name:find('macOS') then
    local scpt = os.tmpname()
    local f = io.open(scpt, 'wb')
    if not f then return false end
    f:write('tell application "Finder" to delete POSIX file "' .. target .. '"')
    f:close()
    reaper.ExecProcess('/usr/bin/osascript "' .. scpt .. '"', 15000)
    os.remove(scpt)
  else
    reaper.ExecProcess('/usr/bin/gio trash "' .. target .. '"', 15000)
  end
  return true
end

-- Выкинуть проект из индекса после успешного удаления; removed_dir ~= nil —
-- удалялась папка целиком, вычищаем и соседние .rpp из неё
local function drop_from_index(path, removed_dir)
  for p in pairs(state.index.projects) do
    if p == path or (removed_dir and p:sub(1, #removed_dir + 1) == removed_dir .. '/') then
      state.index.projects[p] = nil
    end
  end
  local i = sel_index(path)
  if i then table.remove(state.sel, i) end
  if state.expanded == path then state.expanded = nil end
end

-- Удаление в Корзину. Папку целиком — только если это не корень сканирования.
local function delete_project(card)
  local dir = card.path:match('^(.*)[/\\]')
  local roots = {}
  for _, p in ipairs(core.get_scan_paths()) do roots[(p:gsub('/+$', ''))] = true end
  local dir_ok = dir and not roots[dir]
  local r = reaper.MB(
    'Удалить «' .. card.name .. '» в Корзину?\n\n' ..
    (dir_ok and 'Да — папку проекта целиком\nНет — только .rpp'
            or 'Да/Нет — только .rpp (папка — корень сканирования)'),
    'JF PM — удаление', 3)
  if r ~= 6 and r ~= 7 then return end
  local target = (r == 6 and dir_ok) and dir or card.path

  if not trash_path(target) then
    state.status_msg = 'Удаление: tmp недоступен'
    return
  end
  local still = io.open(card.path, 'rb')
  if still then
    still:close()
    state.status_msg = 'Удаление не удалось'
    return
  end
  drop_from_index(card.path, target == dir and dir or nil)
  state.focus = 0
  core.save_index(state.index)
  state.status_msg = 'В Корзине: ' .. target
end

-- Массовое удаление выделенных: один вопрос на всех
local function delete_selected()
  local n = #state.sel
  if n == 0 then return end
  local roots = {}
  for _, p in ipairs(core.get_scan_paths()) do roots[(p:gsub('/+$', ''))] = true end
  local r = reaper.MB(
    string.format('Удалить %d проект(ов) в Корзину?\n\n' ..
      'Да — папки целиком (корни сканирования — только .rpp)\nНет — только .rpp', n),
    'JF PM — удаление', 3)
  if r ~= 6 and r ~= 7 then return end
  local removed = 0
  for _, path in ipairs({table.unpack(state.sel)}) do
    local card = state.index.projects[path]
    if card then
      local dir = path:match('^(.*)[/\\]')
      local dir_ok = r == 6 and dir and not roots[dir]
      local target = dir_ok and dir or path
      trash_path(target)
      local still = io.open(path, 'rb')
      if still then
        still:close()
      else
        drop_from_index(path, dir_ok and dir or nil)
        removed = removed + 1
      end
    end
  end
  state.focus = 0
  core.save_index(state.index)
  state.status_msg = string.format('В Корзине: %d из %d', removed, n)
end

-- Закрепить все выделенные; если уже все закреплены — открепить
local function pin_selected()
  local all = true
  for _, p in ipairs(state.sel) do
    local c = state.index.projects[p]
    if c and not c.pinned then all = false end
  end
  for _, p in ipairs(state.sel) do
    local c = state.index.projects[p]
    if c then c.pinned = (not all) or nil end
  end
  core.save_index(state.index)
end

-- Merge: выделенные соединяются последовательно в порядке выделения.
local function merge_selected()
  if #state.sel < 2 then return end
  local dir = state.sel[1]:match('^(.*)[/\\]')
  local out = dir .. '/merge_' .. os.date('%y%m%d_%H%M') .. '.rpp'
  local ok, err = core.merge_projects(state.sel, out)
  if not ok then
    state.status_msg = 'Merge: ' .. tostring(err)
    return
  end
  local card = core.build_card(out, nil)
  if card then
    state.index.projects[out] = card
    core.save_index(state.index)
  end
  state.sel = {}
  state.status_msg = 'Merge → ' .. out
end

-- ---------------------------------------------------------------------------
-- Тамбнейлы

local img_cache = {}
local function get_image(path)
  local img = img_cache[path]
  if img == nil then
    local ok, res = pcall(ImGui.CreateImage, path)
    img = ok and res or false
    if img then ImGui.Attach(ctx, img) end
    img_cache[path] = img
  end
  return img or nil
end

local function draw_thumb(card, size)
  -- превью: назначенное вручную → <имя проекта>.png / jf_thumb.png в папке
  local img = card.thumb_user and get_image(card.thumb_user) or nil
  if not img and card.thumb_file then img = get_image(card.thumb_file) end
  if img then
    ImGui.Image(ctx, img, size, size)
    return
  end
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + size, y0 + size, 0x161616FF, 4)
  local h = fnv1a(card.path)
  if state.thumb_style == 2 and #(card.items or {}) > 0
     and (card.duration or 0) > 0 then
    -- навигатор: мини-аранжировка, айтемы по трекам, оттенок — от трека
    local tracks = math.max(card.track_count or 1, 1)
    local row = size / tracks
    for _, it in ipairs(card.items) do
      local ix0 = x0 + (it.p / card.duration) * size
      local ix1 = math.min(ix0 + (it.l / card.duration) * size, x0 + size)
      if ix1 - ix0 < 1 then ix1 = ix0 + 1 end
      local iy0 = y0 + (it.t - 1) * row
      local col = hash_color((h + it.t * 53) % 360, 0.5, 0.85)
      ImGui.DrawList_AddRectFilled(dl, ix0, iy0 + 0.5,
        ix1, iy0 + math.max(1, row - 1) + 0.5, col)
    end
    -- полоса регионов внизу: цвет от имени региона, «intro» узнаваем
    -- одинаково во всех проектах
    for _, r in ipairs(card.regions or {}) do
      local rx0 = x0 + math.max(r.pos / card.duration, 0) * size
      local rx1 = x0 + math.min(r.fin / card.duration, 1) * size
      if rx1 - rx0 < 1 then rx1 = rx0 + 1 end
      local rh = fnv1a(r.name ~= '' and r.name or '?')
      ImGui.DrawList_AddRectFilled(dl, rx0, y0 + size - 4, rx1, y0 + size,
        hash_color(rh % 360, 0.6, 0.9))
    end
  elseif state.thumb_style == 1 then
    -- радикал, детерминированный от пути проекта
    local glyph = RADICALS[h % #RADICALS + 1]
    local col = hash_color(h % 360, 0.45, 0.95)
    local fs = size * 0.68
    ImGui.DrawList_AddTextEx(dl, big_font, fs,
      x0 + size * 0.16, y0 + size * 0.13, col, glyph)
  else
    -- 8-битный калейдоскоп: четверть 4x4 из хеша, зеркалим по обеим осям
    local cell = size / 8
    local col1 = hash_color(h % 360, 0.55, 0.95)
    local col2 = hash_color((h >> 8) % 360, 0.35, 0.65)
    for y = 0, 7 do
      for x = 0, 7 do
        local qx = x < 4 and x or 7 - x
        local qy = y < 4 and y or 7 - y
        local bit_i = qy * 4 + qx
        if (h >> bit_i) & 1 == 1 then
          local c = ((h >> ((bit_i + 16) % 32)) & 1) == 1 and col1 or col2
          ImGui.DrawList_AddRectFilled(dl,
            x0 + x * cell, y0 + y * cell,
            x0 + (x + 1) * cell, y0 + (y + 1) * cell, c)
        end
      end
    end
  end
  ImGui.Dummy(ctx, size, size)
end

-- ---------------------------------------------------------------------------
-- Сетка карточек

local function draw_card_details(card, meta)
  ImGui.Separator(ctx)
  ImGui.Text(ctx, string.format('%s BPM · %d/%d · %d трек(ов)',
    card.tempo and tostring(card.tempo) or '—',
    card.timesig_num or 4, card.timesig_den or 4, card.track_count or 0))

  if meta.desc ~= '' then
    ImGui.TextWrapped(ctx, meta.desc)
  end

  if #card.regions > 0 then
    ImGui.TextDisabled(ctx, 'Структура:')
    for _, r in ipairs(card.regions) do
      ImGui.BulletText(ctx, string.format('%s  [%s – %s]',
        r.name ~= '' and r.name or '(без имени)',
        fmt_duration(r.pos), fmt_duration(r.fin)))
    end
  end

  -- треки свёрнуты по умолчанию, как бэкапы
  if #card.track_names > 0 then
    if ImGui.TreeNode(ctx, string.format('Треки (%d)###trk', #card.track_names)) then
      local named = {}
      for _, n in ipairs(card.track_names) do
        named[#named + 1] = n ~= '' and n or '(без имени)'
      end
      ImGui.TextWrapped(ctx, table.concat(named, ', '))
      ImGui.TreePop(ctx)
    end
  end

  if meta.report_done ~= '' or meta.report_todo ~= '' then
    ImGui.TextDisabled(ctx, 'Отчёт (' .. fmt_date(meta.report_ts) .. '):')
    if meta.report_done ~= '' then
      ImGui.TextWrapped(ctx, 'Сделано: ' .. meta.report_done)
    end
    if meta.report_todo ~= '' then
      ImGui.TextWrapped(ctx, 'Дальше: ' .. meta.report_todo)
    end
  else
    ImGui.TextDisabled(ctx, 'Отчёта нет')
  end

  -- скрытая ветка: бэкапы (свёрнута по умолчанию)
  local backups = card.backups or {}
  if #backups > 0 then
    if ImGui.TreeNode(ctx, string.format('Бэкапы (%d)###bak', #backups)) then
      for _, b in ipairs(backups) do
        ImGui.BulletText(ctx, string.format('%s — %s, %s',
          b.file, fmt_date(b.mtime), fmt_size(b.size)))
      end
      ImGui.TreePop(ctx)
    end
  end

  if card.render_file ~= '' then
    ImGui.TextDisabled(ctx, 'Рендер: ' .. card.render_file)
  end
  -- назначение тегов: клик по чипу включает/выключает (хранится в индексе);
  -- теги из .rpp и Finder отсюда не снимаются
  ImGui.TextDisabled(ctx, 'Теги:')
  local cur = {}
  for _, t in ipairs(all_tags(card, meta)) do cur[t] = true end
  for i, e in ipairs(TAGS) do
    local t = e[1]
    local label = (cur[t] and '#' or '·') .. t
    ImGui.SameLine(ctx)
    if ImGui.CalcTextSize(ctx, label) + 12 > ImGui.GetContentRegionAvail(ctx) then
      ImGui.NewLine(ctx)
    end
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, cur[t] and e[2] or 0x9A9A9AFF)
    if ImGui.SmallButton(ctx, label .. '###tag' .. i) then
      local extra = card.tags_extra or {}
      local found
      for j, x in ipairs(extra) do if x == t then found = j end end
      if found then
        table.remove(extra, found)
      elseif not cur[t] then
        extra[#extra + 1] = t
      else
        state.status_msg = 'Тег из .rpp/Finder — снимай в проекте'
      end
      card.tags_extra = #extra > 0 and extra or nil
      search_cache[card.path] = nil
      core.save_index(state.index)
    end
    ImGui.PopStyleColor(ctx)
  end

  -- «+»: свой тег не из списка (цвет получит от хеша имени)
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, '+###tagadd') then
    if state.tag_add_path == card.path then
      state.tag_add_path = nil
    else
      state.tag_add_path, state.tag_add_text = card.path, ''
      state.tag_add_focus = true
    end
  end
  if state.tag_add_path == card.path then
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 120)
    if state.tag_add_focus then
      ImGui.SetKeyboardFocusHere(ctx)
      state.tag_add_focus = false
    end
    local done, v = ImGui.InputTextWithHint(ctx, '###newtag', 'тег + Enter',
      state.tag_add_text, ImGui.InputTextFlags_EnterReturnsTrue)
    if v then state.tag_add_text = v end
    if done and state.tag_add_text ~= '' then
      local t = state.tag_add_text
      local extra, dup = card.tags_extra or {}, cur[t]
      for _, x in ipairs(extra) do if x == t then dup = true end end
      if not dup then
        extra[#extra + 1] = t
        card.tags_extra = extra
        search_cache[card.path] = nil
        core.save_index(state.index)
      end
      state.tag_add_path = nil
    end
  end

  ImGui.TextDisabled(ctx, card.path)
  -- команды — маленькими иконками с тултипами
  local function icon(label, tip, col)
    if col then ImGui.PushStyleColor(ctx, ImGui.Col_Text, col) end
    local clicked = ImGui.SmallButton(ctx, label)
    if col then ImGui.PopStyleColor(ctx) end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, tip) end
    return clicked
  end
  if icon('▲###fold', 'свернуть') then state.expanded = nil end
  ImGui.SameLine(ctx)
  if icon((card.pinned and '●' or '○') .. '###pin',
      card.pinned and 'открепить' or 'закрепить',
      card.pinned and 0xD9B96CFF or nil) then
    toggle_pin(card)
  end
  ImGui.SameLine(ctx)
  local si = sel_index(card.path)
  if icon((si and '■' or '□') .. '###sel',
      si and 'снять выбор' or 'выбрать', si and 0xD9B96CFF or nil) then
    toggle_select(card.path)
  end
  ImGui.SameLine(ctx)
  if icon('×###del', 'удалить в Корзину…') then
    delete_project(card)
    return
  end
  ImGui.SameLine(ctx)
  if icon('▦###thumb', 'назначить картинку-превью…') then
    -- нативный диалог, без зависимостей от js_ReaScriptAPI
    local rv, fn = reaper.GetUserFileNameForRead('', 'Картинка-превью проекта', '')
    if rv and fn and fn ~= '' then
      card.thumb_user = fn
      img_cache[fn] = nil -- если раньше не загрузилась — пробуем заново
      core.save_index(state.index)
    end
  end
  if card.thumb_user then
    ImGui.SameLine(ctx)
    if icon('▧###unthumb', 'сбросить превью') then
      card.thumb_user = nil
      core.save_index(state.index)
    end
  end
end

local function draw_card(entry, i, card_w)
  local card, meta = entry.card, entry.meta
  local expanded = state.expanded == card.path
  local focused = state.focus == i
  local si = sel_index(card.path)
  local inner_click = false  -- клик по виджету внутри — не раскрывать карточку
  local h = expanded and 0 or 138  -- 0 = авто-высота по контенту

  local child_flags = ImGui.ChildFlags_Border
  if expanded then
    child_flags = child_flags | ImGui.ChildFlags_AutoResizeY
  end
  if focused then
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0xE8E8E8FF)
  elseif si then
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0xD9B96CFF)
  end
  if ImGui.BeginChild(ctx, card.path, card_w, h, child_flags) then
    draw_thumb(card, 64)
    ImGui.SameLine(ctx)
    ImGui.BeginGroup(ctx)
    ImGui.Text(ctx, trunc(card.name, 22))
    if card.pinned then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0xD9B96CFF, '●') -- закреплён
    end
    if si then
      ImGui.SameLine(ctx)
      -- номер в выборке = позиция в merge
      ImGui.TextColored(ctx, 0xD9B96CFF, '[' .. si .. ']')
    end
    -- ячейка выделения в правом верхнем углу
    ImGui.SameLine(ctx, card_w - 30)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, si and 0xD9B96CFF or 0x6A6A6AFF)
    if ImGui.SmallButton(ctx, (si and '■' or '□') .. '###selbox') then
      toggle_select(card.path)
      inner_click = true
    end
    ImGui.PopStyleColor(ctx)

    local color = core.STATUS_COLORS[meta.status]
    local stage = core.PIPELINE[meta.status]
    if stage then
      -- прогресс по пайплайну: ●●○○ = «в работе»
      local dots = string.rep('●', stage) ..
                   string.rep('○', core.PIPELINE_STEPS - stage)
      ImGui.TextColored(ctx, color or 0xAAAAAAFF, dots)
      ImGui.SameLine(ctx)
    end
    if meta.status ~= '' then
      ImGui.TextColored(ctx, color or 0xAAAAAAFF, meta.status)
    else
      ImGui.TextDisabled(ctx, '—')
    end
    if card.needs_report then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0xE06060FF, '· без отчёта')
    end

    ImGui.TextDisabled(ctx, fmt_date(card.mtime))
    ImGui.TextDisabled(ctx, fmt_duration(card.duration) .. '   ' ..
      (#card.regions) .. ' рег.' ..
      (card.dir_size and ('   ' .. fmt_size(card.dir_size)) or ''))
    ImGui.EndGroup(ctx)

    -- следующий шаг из последнего отчёта — открытая петля снаружи головы
    local next_action = meta.report_todo:match('^[^\n]+')
    if next_action then
      ImGui.TextColored(ctx, 0xD9B96CFF, '→ ' .. next_action)
    end

    -- теги цветными чипами с ручным переносом по ширине карточки
    local tags = all_tags(card, meta)
    for ti, t in ipairs(tags) do
      local label = '#' .. t
      if ti > 1 then
        ImGui.SameLine(ctx)
        if ImGui.CalcTextSize(ctx, label) > ImGui.GetContentRegionAvail(ctx) then
          ImGui.NewLine(ctx)
        end
      end
      ImGui.TextColored(ctx, tag_color(t), label)
    end

    if expanded then draw_card_details(card, meta) end
    ImGui.EndChild(ctx)
  end
  if focused or si then
    ImGui.PopStyleColor(ctx)
  end
  if focused and state.scroll_to_focus then
    ImGui.SetScrollHereY(ctx, 0.5)
    state.scroll_to_focus = false
  end

  if ImGui.IsItemHovered(ctx) then
    local mods = ImGui.GetKeyMods(ctx)
    local select_click = mods & ImGui.Mod_Ctrl ~= 0 or mods & ImGui.Mod_Super ~= 0
    if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
      open_project(card.path)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not inner_click then
      if select_click then
        toggle_select(card.path) -- cmd/ctrl+клик: в выборку для merge
        state.focus = i
      elseif not expanded then
        state.expanded = card.path
        state.focus = i
      end
    end
  end
end

local function draw_grid(cards)
  if #cards == 0 then
    ImGui.TextDisabled(ctx, 'Пусто. Rescan, или ослабь фильтры.')
    return 1
  end
  local avail = ImGui.GetContentRegionAvail(ctx)
  local card_w = 300
  local cols = math.max(1, math.floor(avail / (card_w + 8)))
  for i, entry in ipairs(cards) do
    if (i - 1) % cols ~= 0 then ImGui.SameLine(ctx) end
    draw_card(entry, i, card_w)
  end
  return cols
end

-- ---------------------------------------------------------------------------
-- Таймлайн: строка на проект, бар от старейшего бэкапа до последнего изменения

local TIMELINE_SPAN = 183 * 86400 -- полгода

local function draw_timeline(cards)
  if #cards == 0 then
    ImGui.TextDisabled(ctx, 'Пусто. Rescan, или ослабь фильтры.')
    return
  end
  local now = os.time()
  local min_t = now - TIMELINE_SPAN
  local label_w = 180
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local plot_w = math.max(100, avail_w - label_w - 10)
  local dl = ImGui.GetWindowDrawList(ctx)

  -- ось месяцев
  local ax, ay = ImGui.GetCursorScreenPos(ctx)
  local t = os.date('*t', min_t)
  t.day, t.hour, t.min, t.sec = 1, 12, 0, 0
  local mt = os.time(t)
  while mt < now do
    if mt >= min_t then
      local x = ax + label_w + (mt - min_t) / TIMELINE_SPAN * plot_w
      ImGui.DrawList_AddLine(dl, x, ay, x, ay + 14, 0x3A3A3AFF)
      ImGui.DrawList_AddText(dl, x + 3, ay, 0x777777FF, os.date('%m.%y', mt))
    end
    local nt = os.date('*t', mt)
    nt.month = nt.month + 1
    mt = os.time(nt)
  end
  ImGui.Dummy(ctx, avail_w, 16)

  for i, entry in ipairs(cards) do
    local card, meta = entry.card, entry.meta
    local rx, ry = ImGui.GetCursorScreenPos(ctx)
    ImGui.Selectable(ctx, '##tl' .. i, state.focus == i, 0, 0, 18)
    if state.focus == i and state.scroll_to_focus then
      ImGui.SetScrollHereY(ctx, 0.5)
      state.scroll_to_focus = false
    end
    if ImGui.IsItemHovered(ctx) then
      local next_action = meta.report_todo:match('^[^\n]+') or ''
      ImGui.SetTooltip(ctx, card.name ..
        (meta.status ~= '' and ('  [' .. meta.status .. ']') or '') ..
        (next_action ~= '' and ('\n→ ' .. next_action) or ''))
      if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
        open_project(card.path)
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) then
        state.focus = i
      end
    end

    ImGui.DrawList_AddText(dl, rx, ry + 1, 0xCCCCCCFF, trunc(card.name, 24))

    local t1 = card.mtime or now
    local t0 = t1
    local bks = card.backups or {}
    if #bks > 0 then
      t0 = bks[#bks].mtime or t1 -- отсортированы по убыванию, хвост — старейший
    end
    if t0 > t1 then t0 = t1 end
    if t1 >= min_t then
      t0 = math.max(t0, min_t)
      local bx0 = rx + label_w + (t0 - min_t) / TIMELINE_SPAN * plot_w
      local bx1 = rx + label_w + (t1 - min_t) / TIMELINE_SPAN * plot_w
      if bx1 - bx0 < 3 then bx0 = bx1 - 3 end
      local col = core.STATUS_COLORS[meta.status] or 0x8A8A8AFF
      ImGui.DrawList_AddRectFilled(dl, bx0, ry + 4, bx1, ry + 15, col, 2)
    else
      ImGui.DrawList_AddText(dl, rx + label_w, ry + 1, 0x555555FF,
        'старше полугода')
    end
  end
end

-- ---------------------------------------------------------------------------
-- Календарь: тепловая карта активности (mtime, отчёты, бэкапы) от старейшей
-- активности до сегодня; горизонтальный скролл, старт — на текущем месяце

local function day_key(ts)
  local d = os.date('*t', ts)
  d.hour, d.min, d.sec = 0, 0, 0
  return os.time(d)
end

local function draw_calendar(cards)
  local DAY = 86400
  local now = os.time()
  local act = {}
  local function mark(ts, name)
    if not ts or ts == 0 then return end
    local key = day_key(ts)
    local a = act[key]
    if not a then a = { n = 0, names = {} } act[key] = a end
    if not a.names[name] then
      a.names[name] = true
      a.n = a.n + 1
    end
  end
  for _, e in ipairs(cards) do
    mark(e.card.mtime, e.card.name)
    mark(e.meta.report_ts, e.card.name)
    for _, b in ipairs(e.card.backups or {}) do mark(b.mtime, e.card.name) end
  end

  -- диапазон: от старейшей активности (но не меньше 26 недель) до сегодня
  local oldest = now
  for k in pairs(act) do if k < oldest then oldest = k end end
  local WEEKS = math.max(26, math.ceil((day_key(now) - oldest) / (7 * DAY)) + 1)
  local cell, gap = 16, 3
  local wd = (os.date('*t', now).wday + 5) % 7 -- 0 = понедельник
  local monday = day_key(now) - wd * DAY
  local start = monday - (WEEKS - 1) * 7 * DAY

  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  y0 = y0 + 16 -- место под метки месяцев
  local dl = ImGui.GetWindowDrawList(ctx)
  local mx, my = ImGui.GetMousePos(ctx)
  local hover_key, hover_act
  local prev_month = ''
  for w = 0, WEEKS - 1 do
    for d = 0, 6 do
      local ts = start + (w * 7 + d) * DAY + DAY / 2
      if ts > now + DAY then break end
      local key = day_key(ts)
      local cx = x0 + w * (cell + gap)
      local cy = y0 + d * (cell + gap)
      local a = act[key]
      local col = 0x1B1B1BFF
      if a then
        col = a.n >= 3 and 0xE8E8E8FF or (a.n == 2 and 0x9A9A9AFF or 0x5C5C5CFF)
      end
      ImGui.DrawList_AddRectFilled(dl, cx, cy, cx + cell, cy + cell, col, 2)
      if mx >= cx and mx < cx + cell and my >= cy and my < cy + cell then
        hover_key, hover_act = key, a
      end
      if d == 0 then
        local m = os.date('%m', ts)
        if m ~= prev_month then
          ImGui.DrawList_AddText(dl, cx, y0 - 16, 0x777777FF, os.date('%m.%y', ts))
          prev_month = m
        end
      end
    end
  end
  ImGui.Dummy(ctx, WEEKS * (cell + gap), 7 * (cell + gap) + 18)
  -- при входе в календарь скроллим к сегодняшнему краю (2 кадра:
  -- GetScrollMaxX узнаёт новую ширину контента только со следующего)
  if (state.cal_scroll_end or 0) > 0 then
    ImGui.SetScrollX(ctx, ImGui.GetScrollMaxX(ctx))
    state.cal_scroll_end = state.cal_scroll_end - 1
  end
  ImGui.TextDisabled(ctx,
    'активность = сохранения, бэкапы, отчёты · ярче — больше проектов за день')
  if hover_key then
    local txt = os.date('%d.%m.%Y', hover_key + 3600)
    if hover_act then
      local names = {}
      for n in pairs(hover_act.names) do names[#names + 1] = n end
      table.sort(names)
      txt = txt .. '\n' .. table.concat(names, '\n')
    end
    ImGui.SetTooltip(ctx, txt)
  end
end

-- ---------------------------------------------------------------------------
-- Канбан: колонка на статус, перенос карточки — drag&drop или Shift+H/L.
-- Статус пишется в индекс (status_over), .rpp не трогается.

local function draw_kanban(cards)
  local cols = { { status = '', label = '—' } }
  for _, s in ipairs(core.STATUSES) do
    cols[#cols + 1] = { status = s, label = s }
  end
  local by_status = {}
  for _, c in ipairs(cols) do c.entries = {}; by_status[c.status] = c end
  for _, e in ipairs(cards) do
    local c = by_status[e.meta.status] or by_status['']
    c.entries[#c.entries + 1] = e
  end
  state.kb_cols = cols -- для vim-навигации в handle_keys

  local col_w = 200
  for ci, c in ipairs(cols) do
    if ci > 1 then ImGui.SameLine(ctx) end
    if ImGui.BeginChild(ctx, '##kb' .. ci, col_w, 0, ImGui.ChildFlags_Border) then
      ImGui.TextColored(ctx, core.STATUS_COLORS[c.status] or 0x8A8A8AFF,
        string.format('%s (%d)', c.label, #c.entries))
      ImGui.Separator(ctx)
      for ei, e in ipairs(c.entries) do
        local card = e.card
        local focused = state.kb_col == ci and state.kb_row == ei
        local si = sel_index(card.path)
        if focused then
          ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0xE8E8E8FF)
        elseif si then
          ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0xD9B96CFF)
        end
        local kx, ky = ImGui.GetCursorScreenPos(ctx)
        if ImGui.BeginChild(ctx, '##kbc' .. card.path, col_w - 16, 64,
            ImGui.ChildFlags_Border) then
          draw_thumb(card, 46)
          ImGui.SameLine(ctx)
          ImGui.BeginGroup(ctx)
          ImGui.Text(ctx, trunc(card.name, 14))
          if card.pinned then
            ImGui.SameLine(ctx)
            ImGui.TextColored(ctx, 0xD9B96CFF, '●')
          end
          if si then
            ImGui.SameLine(ctx)
            ImGui.TextColored(ctx, 0xD9B96CFF, '[' .. si .. ']')
          end
          ImGui.TextDisabled(ctx, fmt_date(card.mtime))
          local na = e.meta.report_todo:match('^[^\n]+')
          if na then
            ImGui.TextColored(ctx, 0xD9B96CFF, trunc('→ ' .. na, 16))
          end
          ImGui.EndGroup(ctx)
          ImGui.EndChild(ctx)
        end
        if focused or si then ImGui.PopStyleColor(ctx) end
        if focused and state.scroll_to_focus then
          ImGui.SetScrollHereY(ctx, 0.5)
          state.scroll_to_focus = false
        end
        -- невидимая кнопка поверх: child-окно — не item, без неё
        -- drag&drop с карточки не стартует
        ImGui.SetCursorScreenPos(ctx, kx, ky)
        ImGui.InvisibleButton(ctx, '##drag' .. card.path, col_w - 16, 64)
        if ImGui.BeginDragDropSource(ctx) then
          ImGui.SetDragDropPayload(ctx, 'JF_PM_CARD', card.path)
          ImGui.Text(ctx, card.name)
          ImGui.EndDragDropSource(ctx)
        end
        if ImGui.IsItemHovered(ctx) then
          local mods = ImGui.GetKeyMods(ctx)
          if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
            open_project(card.path)
          elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) then
            if mods & ImGui.Mod_Ctrl ~= 0 or mods & ImGui.Mod_Super ~= 0 then
              toggle_select(card.path)
            end
            state.kb_col, state.kb_row = ci, ei
          end
        end
      end
      ImGui.EndChild(ctx)
    end
    if ImGui.BeginDragDropTarget(ctx) then
      local ok, payload = ImGui.AcceptDragDropPayload(ctx, 'JF_PM_CARD')
      if ok and payload then
        local card = state.index.projects[payload]
        if card then set_status(card, c.status) end
      end
      ImGui.EndDragDropTarget(ctx)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Тулбар и настройки: всё чипами, без выпадашек

local function chip(label, active)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, active and 0x3D3D3DFF or 0x1E1E1EFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, active and 0xFFFFFFFF or 0x9A9A9AFF)
  local clicked = ImGui.SmallButton(ctx, label)
  ImGui.PopStyleColor(ctx, 2)
  return clicked
end

-- Нативный диалог выбора папки (Finder). Модальный — defer-цикл ждёт, ок.
local function pick_folder(title, initial)
  if not reaper.JS_Dialog_BrowseForFolder then
    state.status_msg = 'Finder-диалог: нужен js_ReaScriptAPI (ReaPack)'
    return nil
  end
  local rv, folder = reaper.JS_Dialog_BrowseForFolder(title, initial or '')
  if rv == 1 and folder and folder ~= '' then return folder end
  return nil
end

local function draw_settings()
  ImGui.SeparatorText(ctx, 'Пути')
  local changed, val

  ImGui.Text(ctx, 'Проекты (через ;):')
  ImGui.SetNextItemWidth(ctx, -86)
  changed, val = ImGui.InputText(ctx, '##paths', state.scan_paths)
  if changed then state.scan_paths = val end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, '+ Finder##scan') then
    local dir = pick_folder('Папка с проектами', state.scan_paths:match('([^;]+)'))
    if dir then
      state.scan_paths = state.scan_paths == '' and dir
        or (state.scan_paths .. ';' .. dir)
    end
  end

  ImGui.Text(ctx, 'Расслоение → мультитреки:')
  ImGui.SetNextItemWidth(ctx, -86)
  changed, val = ImGui.InputText(ctx, '##stems', state.stems_path)
  if changed then state.stems_path = val end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Finder##stems') then
    local dir = pick_folder('Папка мультитреков', state.stems_path)
    if dir then state.stems_path = dir end
  end

  ImGui.Text(ctx, 'Расслоение → регионы:')
  ImGui.SetNextItemWidth(ctx, -86)
  changed, val = ImGui.InputText(ctx, '##regions', state.regions_path)
  if changed then state.regions_path = val end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Finder##regions') then
    local dir = pick_folder('Папка регионов', state.regions_path)
    if dir then state.regions_path = dir end
  end

  ImGui.Text(ctx, 'Тамбнейлы:')
  ImGui.SameLine(ctx)
  if chip('калейдоскоп', state.thumb_style == 0) then state.thumb_style = 0 end
  ImGui.SameLine(ctx)
  if chip('иероглиф', state.thumb_style == 1) then state.thumb_style = 1 end
  ImGui.SameLine(ctx)
  if chip('навигатор', state.thumb_style == 2) then state.thumb_style = 2 end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, 'или <имя проекта>.png / jf_thumb.png в папке проекта')

  if ImGui.Button(ctx, 'Сохранить настройки') then
    core.set_setting('scan_paths', state.scan_paths)
    core.set_setting('stems_path', state.stems_path)
    core.set_setting('regions_path', state.regions_path)
    core.set_setting('thumb_style', tostring(state.thumb_style))
    state.show_settings = false
    state.status_msg = 'Настройки сохранены'
  end
  ImGui.Separator(ctx)
end

local function draw_toolbar()
  if ImGui.Button(ctx, 'Rescan') then rescan() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'настройки') then
    state.show_settings = not state.show_settings
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'галерея') then export_gallery() end

  -- блок выборки: порядок номеров = порядок склейки; при нескольких
  -- выделенных — те же команды, что на карточке, но на всю выборку
  if #state.sel > 0 then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0xD9B96CFF, string.format('выбрано: %d', #state.sel))
    if #state.sel >= 2 then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, 'merge') then merge_selected() end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, 'открыть') then
        for _, p in ipairs(state.sel) do open_project(p) end
      end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, 'закрепить') then pin_selected() end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, 'удалить…') then delete_selected() end
    end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, 'сброс') then state.sel = {} end
  end

  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  for i, label in ipairs(VIEW_CHIPS) do
    ImGui.SameLine(ctx)
    if chip(label, state.view == i - 1) then
      state.view = i - 1
      state.focus = 0
      state.cal_scroll_end = 2
    end
  end

  -- WIP-счётчик: >3 в работе — многовато, внимание расползается
  local wip, no_report = 0, 0
  for _, card in pairs(state.index.projects) do
    local s = (card.ext or {}).STATUS or ''
    if s == 'в работе' or s == 'к миксу' then wip = wip + 1 end
    if card.needs_report then no_report = no_report + 1 end
  end
  ImGui.SameLine(ctx)
  ImGui.TextColored(ctx, wip > 3 and 0xE06060FF or 0x8A8A8AFF,
    string.format('WIP: %d', wip))
  if no_report > 0 then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0xE06060FF, string.format('без отчёта: %d', no_report))
  end

  -- ряд фильтров
  if chip('активные', state.filter_status == 0) then state.filter_status = 0 end
  ImGui.SameLine(ctx)
  if chip('все', state.filter_status == 1) then state.filter_status = 1 end
  ImGui.SameLine(ctx)
  if chip('без отчёта', state.filter_status == 2) then state.filter_status = 2 end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  for i, s in ipairs(core.STATUSES) do
    ImGui.SameLine(ctx)
    if chip(s, state.filter_status == i + 2) then state.filter_status = i + 2 end
  end

  -- ряд сортировки + тег
  ImGui.TextDisabled(ctx, 'сорт:')
  for i, s in ipairs(SORT_CHIPS) do
    ImGui.SameLine(ctx)
    local active = state.sort_mode == i
    local label = s
    if active then
      local desc = SORT_DESC_NATURAL[i] ~= state.sort_rev
      label = s .. (desc and ' ↓' or ' ↑')
    end
    -- повторный клик по активному чипу — переворот порядка
    if chip(label .. '###sort' .. i, active) then
      if active then
        state.sort_rev = not state.sort_rev
      else
        state.sort_mode = i
        state.sort_rev = false
      end
    end
  end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 160)
  if state.focus_tag_input then
    ImGui.SetKeyboardFocusHere(ctx)
    state.focus_tag_input = false
  end
  local changed, val = ImGui.InputTextWithHint(ctx, '##tag',
    'fzf: имя, теги, треки ( / )', state.filter_text)
  if changed then state.filter_text = val end
end

-- ---------------------------------------------------------------------------
-- Vim-навигация

local function handle_keys(cards, cols)
  if ImGui.IsAnyItemActive(ctx) then return end -- набор текста в поле
  if not ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) then
    return
  end
  local shift = ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift ~= 0
  local entry

  if state.view == 3 then
    -- канбан: h/l — колонки, j/k — внутри, Shift+H/L — сменить статус
    local kcols = state.kb_cols or {}
    if #kcols == 0 then return end
    local ci, ri = state.kb_col, state.kb_row
    local moved = false
    local function clamp()
      if ci < 1 then ci = 1 end
      if ci > #kcols then ci = #kcols end
      local nn = #kcols[ci].entries
      if ri > nn then ri = nn end
      if ri < 1 then ri = 1 end
    end
    if ci == 0 then ci, ri = 1, 1 clamp() end
    local cur = kcols[ci] and kcols[ci].entries[ri]
    if shift and cur then
      local target
      if ImGui.IsKeyPressed(ctx, ImGui.Key_L) then target = ci + 1 end
      if ImGui.IsKeyPressed(ctx, ImGui.Key_H) then target = ci - 1 end
      if target and kcols[target] then
        set_status(cur.card, kcols[target].status)
        ci = target
        ri = #kcols[target].entries + 1 -- карточка встанет в конец колонки
        moved = true
      end
    else
      if ImGui.IsKeyPressed(ctx, ImGui.Key_L) then ci = ci + 1 moved = true end
      if ImGui.IsKeyPressed(ctx, ImGui.Key_H) then ci = ci - 1 moved = true end
      if ImGui.IsKeyPressed(ctx, ImGui.Key_J) then ri = ri + 1 moved = true end
      if ImGui.IsKeyPressed(ctx, ImGui.Key_K) then ri = ri - 1 moved = true end
    end
    clamp()
    state.kb_col, state.kb_row = ci, ri
    if moved then state.scroll_to_focus = true end
    entry = kcols[ci] and kcols[ci].entries[ri]
  else
    local n = #cards
    if n == 0 then return end
    local moved = false
    local step_h = state.view == 0 and 1 or 0
    local step_v = state.view == 0 and cols or 1

    local function move(delta)
      local f = state.focus
      if f == 0 then
        f = 1
      else
        f = f + delta
        if f < 1 then f = 1 end
        if f > n then f = n end
      end
      state.focus = f
      moved = true
    end

    if ImGui.IsKeyPressed(ctx, ImGui.Key_J) then move(step_v) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_K) then move(-step_v) end
    if step_h > 0 then
      if ImGui.IsKeyPressed(ctx, ImGui.Key_L) then move(step_h) end
      if ImGui.IsKeyPressed(ctx, ImGui.Key_H) then move(-step_h) end
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_G) then
      state.focus = shift and n or 1
      moved = true
    end
    if moved then state.scroll_to_focus = true end
    entry = state.focus > 0 and cards[state.focus] or nil
  end

  if entry then
    local path = entry.card.path
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) then
      if state.view == 0 then
        state.expanded = state.expanded ~= path and path or nil
      else
        open_project(path)
      end
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_O) then open_project(path) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_X) then toggle_select(path) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_P) then toggle_pin(entry.card) end
    if shift and ImGui.IsKeyPressed(ctx, ImGui.Key_D) then
      delete_project(entry.card)
    end
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_M) and #state.sel >= 2 then
    merge_selected()
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Slash) then
    state.focus_tag_input = true
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    if state.tag_add_path then
      state.tag_add_path = nil
    elseif state.expanded then
      state.expanded = nil
    elseif #state.sel > 0 then
      state.sel = {}
    else
      state.focus = 0
      state.kb_col, state.kb_row = 0, 0
    end
  end
end

-- ---------------------------------------------------------------------------

local function loop()
  ImGui.PushFont(ctx, font)
  ImGui.SetNextWindowSize(ctx, 980, 660, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'JF — проекты', true)
  if visible then
    draw_toolbar()
    if state.show_settings then draw_settings() end
    ImGui.Separator(ctx)

    local cards = collect_cards()
    local cols = 1
    -- контент в своём child: тулбар не скроллится, внизу место под статусбар
    local footer_h = ImGui.GetTextLineHeightWithSpacing(ctx) + 8
    local wflags = (state.view == 2 or state.view == 3)
      and ImGui.WindowFlags_HorizontalScrollbar or ImGui.WindowFlags_None
    if ImGui.BeginChild(ctx, '##content', 0, -footer_h,
        ImGui.ChildFlags_None, wflags) then
      if state.view == 0 then
        cols = draw_grid(cards)
      elseif state.view == 1 then
        draw_timeline(cards)
      elseif state.view == 2 then
        draw_calendar(cards)
      else
        draw_kanban(cards)
      end
      handle_keys(cards, cols)
      ImGui.EndChild(ctx)
    end

    -- статусбар: слева сообщение или сводка, справа версия
    ImGui.Separator(ctx)
    local total = 0
    for _ in pairs(state.index.projects) do total = total + 1 end
    ImGui.TextDisabled(ctx, state.status_msg ~= '' and state.status_msg
      or string.format('%d из %d проектов', #cards, total))
    local ver = 'JF PM v' .. VERSION
    ImGui.SameLine(ctx,
      ImGui.GetWindowWidth(ctx) - ImGui.CalcTextSize(ctx, ver) - 12)
    ImGui.TextDisabled(ctx, ver)
    ImGui.End(ctx)
  end
  ImGui.PopFont(ctx)
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
