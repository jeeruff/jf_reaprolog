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
-- g/G — в начало/конец, Esc — свернуть → сброс выборки → фокус → закрыть окно.
-- Канбан: Shift+H/L — перенести карточку в соседний статус, drag&drop мышью.

local VERSION = '0.3'

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

-- ===========================================================================
-- ЯЗЫК: 'ru' | 'en' — чипы в настройках. Данные (.rpp, индекс) каноничны
-- (русские классы), переводится только отображение.
-- ===========================================================================
local LANG = core.get_setting('lang') == 'en' and 'en' or 'ru'
local EN = {
  ['настройки'] = 'settings', ['галерея'] = 'gallery',
  ['выбрано: %d'] = 'selected: %d', ['сброс'] = 'clear',
  ['открыть'] = 'open', ['закрепить'] = 'pin', ['открепить'] = 'unpin',
  ['удалить…'] = 'delete…', ['subs → проект…'] = 'subs → project…',
  ['регионов: %d'] = 'regions: %d', ['собрать проект'] = 'build project',
  ['без отчёта: %d'] = 'no report: %d',
  ['активные'] = 'active', ['все'] = 'all', ['без отчёта'] = 'no report',
  ['сетка'] = 'grid', ['таймлайн'] = 'timeline', ['календарь'] = 'calendar',
  ['канбан'] = 'kanban',
  ['сорт:'] = 'sort:', ['дата'] = 'date', ['статус'] = 'class',
  ['длительность'] = 'length', ['имя'] = 'name', ['размер'] = 'size',
  ['fzf: всё — имя, треки, регионы, отчёты… ( / )'] =
    'fzf: everything — name, tracks, regions, reports… ( / )',
  ['Пути'] = 'Paths', ['Проекты (через ;):'] = 'Projects (separated by ;):',
  ['Расслоение → мультитреки:'] = 'Harvest → multitracks:',
  ['Расслоение → регионы:'] = 'Harvest → regions:',
  ['Тамбнейлы:'] = 'Thumbnails:', ['калейдоскоп'] = 'kaleidoscope',
  ['иероглиф'] = 'glyph', ['навигатор'] = 'navigator',
  ['или <имя проекта>.png / jf_thumb.png в папке проекта'] =
    'or <project name>.png / jf_thumb.png in the project folder',
  ['Аудио-пики:'] = 'Audio peaks:', ['волна'] = 'wave', ['спектр'] = 'spectrum',
  ['Сохранить настройки'] = 'Save settings',
  ['Настройки сохранены'] = 'Settings saved',
  ['Пусто. Rescan, или ослабь фильтры.'] = 'Empty. Rescan, or relax filters.',
  ['старше полугода'] = 'older than half a year',
  ['· без отчёта'] = '· no report',
  ['Дедлайн:'] = 'Deadline:', ['назначить'] = 'set', ['изменить'] = 'edit',
  ['снять'] = 'clear', ['просрочен'] = 'overdue', ['дн.'] = 'd.',
  ['ID трека:'] = 'Track ID:', ['Семплы:'] = 'Samples:',
  ['добавить'] = 'add',
  ['Структура:'] = 'Structure:', ['Треки'] = 'Tracks', ['Бэкапы'] = 'Backups',
  ['Заметки проекта'] = 'Project notes', ['Заметки треков'] = 'Track notes',
  ['Заметки айтемов'] = 'Item notes',
  ['Отчёт'] = 'Report', ['Отчёта нет'] = 'No report yet',
  ['Сделано:'] = 'Done:', ['Дальше:'] = 'Next:', ['Теги:'] = 'Tags:',
  ['Тег из .rpp/Finder — снимай в проекте'] =
    'Tag comes from .rpp/Finder — remove it at the source',
  ['тег + Enter'] = 'tag + Enter', ['новое имя + Enter'] = 'new name + Enter',
  ['свернуть'] = 'collapse', ['выбрать'] = 'select',
  ['снять выбор'] = 'deselect', ['удалить в Корзину…'] = 'move to Trash…',
  ['назначить картинку-превью…'] = 'set preview image…',
  ['сбросить превью'] = 'reset preview',
  ['отрендерить аудио-превью (jf_preview.wav)'] =
    'render audio preview (jf_preview.wav)',
  ['обновить карточку (перечитать .rpp)'] = 'refresh card (re-read .rpp)',
  ['обновить карточку'] = 'refresh card',
  ['переименовать проект…'] = 'rename project…',
  ['Обновлено: '] = 'Refreshed: ',
  ['нет аудио · ▸ в карточке отрендерит превью'] =
    'no audio · ▸ in the card renders a preview',
  ['пики не построились'] = 'peaks failed to build',
  ['клик — сик · пкм — стоп'] = 'click — seek · right click — stop',
  ['играть: '] = 'play: ',
  ['клик — с места клика · пкм — стоп'] =
    'click — play from here · right click — stop',
  ['клик — subproject в активный проект\nCmd+клик — в корзину регионов'] =
    'click — subproject into the active project\nCmd+click — into the region basket',
  ['В корзине регионов: %d'] = 'Region basket: %d',
  ['Язык / Language:'] = 'Язык / Language:',
  ['первый регион: '] = 'first region: ',
  [' (первые 5 мин)'] = ' (first 5 min)',
  ['Превью: у проекта нет ни конца, ни регионов'] =
    'Preview: project has neither an end nor regions',
  ['Превью-батч: %d/%d'] = 'Preview batch: %d/%d',
  ['Превью отрендерено'] = 'Preview rendered',
  ['Превью-батч: готово %d'] = 'Preview batch: %d done',
  ['Превью-батч: у всех уже есть аудио'] =
    'Preview batch: every project already has audio',
  ['Превью-батч остановлен'] = 'Preview batch stopped',
  ['стоп превью-батча (%d/%d)'] = 'stop preview batch (%d/%d)',
  ['Сделать превью всем проектам (у кого нет аудио)'] =
    'Render previews for all projects (missing audio)',
  ['лимит 5 мин · рендер offline · можно остановить'] =
    '5 min limit · offline render · can be stopped',
  ['активность = сохранения, бэкапы, отчёты · ярче — больше проектов' ..
   ' · рамка — дедлайн · белая рамка — сегодня'] =
    'activity = saves, backups, reports · brighter — more projects' ..
    ' · frame — deadline · white frame — today',
}
local function T(s)
  if LANG ~= 'en' then return s end
  return EN[s] or s
end
local function status_label(s)
  if LANG == 'en' then return core.STATUS_EN[s] or s end
  return s
end

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
  card_size = tonumber(core.get_setting('card_size')) or 2,     -- 1 S / 2 M / 3 L
  peak_style = tonumber(core.get_setting('peak_style')) or 0,   -- 0 волна / 1 спектр
  preview_vol = tonumber(core.get_setting('preview_vol')) or 1.0,
  view = 0,                 -- 0 сетка, 1 таймлайн, 2 календарь, 3 канбан
  filter_status = 0,        -- 0 активные, 1 все, 2 без отчёта, 3.. статусы
  filter_text = '',         -- fzf: имя, теги, треки
  sel = {},                 -- упорядоченный список путей — порядок = порядок merge
  basket = {},              -- корзина регионов: {path, region} для сборки проекта
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
  filter_tags = {},         -- активные теги-фильтры (AND)
}

local STATUS_ORDER = {}
for i, s in ipairs(core.STATUSES) do STATUS_ORDER[s] = i end

local SORT_CHIPS = { 'дата', 'статус', 'длительность', 'имя', 'размер' }
-- естественное направление: true = по убыванию (новое/большое сверху)
local SORT_DESC_NATURAL = { true, false, true, false, true }
local VIEW_CHIPS = { 'сетка', 'таймлайн', 'календарь', 'канбан' }

-- лейблы выпадашки классов: «—» + core.STATUSES (исключение из правила
-- «без выпадашек» — по просьбе владельца); кэш на язык
local CLASS_LABELS_CACHE = {}
local function class_labels()
  local l = CLASS_LABELS_CACHE[LANG]
  if not l then
    local names = {}
    for i, s in ipairs(core.STATUSES) do names[i] = status_label(s) end
    l = '—\0' .. table.concat(names, '\0') .. '\0'
    CLASS_LABELS_CACHE[LANG] = l
  end
  return l
end

-- размеры карточек в сетке: ширина, высота, тамбнейл, макс. символов имени
local CARD_SIZES = {
  { label = 'S', w = 220, h = 130, thumb = 40, name = 15 },
  { label = 'M', w = 300, h = 162, thumb = 64, name = 22 },
  { label = 'L', w = 390, h = 200, thumb = 96, name = 30 },
}

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

-- запрос из нескольких слов: каждое слово — своя подпоследовательность,
-- порядок слов не важен (как в fzf)
local function fuzzy_match_all(tokens, hay)
  for _, tk in ipairs(tokens) do
    if not fuzzy_match(tk, hay) then return false end
  end
  return true
end

-- кэш поисковой строки на карточку (не пересобирать каждый кадр);
-- инвалидация: rescan, правка тегов, смена статуса
local search_cache = {}
-- кэши превью/DAW-ссылок (объявлены здесь: их чистят rescan и refresh_card)
local audio_cache, wave_cache, daw_cache = {}, {}, {}
local function search_text(card, meta)
  local s = search_cache[card.path]
  if not s then
    local regions = {}
    for _, r in ipairs(card.regions or {}) do regions[#regions + 1] = r.name end
    s = ulower(table.concat({
      card.name,
      table.concat(all_tags(card, meta), ' '),
      table.concat(card.track_names or {}, ' '),
      table.concat(regions, ' '),
      meta.status or '',
      meta.track_id or '',
      meta.samples or '',
      meta.desc or '',
      meta.report_done or '',
      meta.report_todo or '',
      card.path,
    }, ' '))
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
  local needle_tokens
  if state.filter_text ~= '' then
    needle_tokens = {}
    for word in state.filter_text:gmatch('%S+') do
      local okc, codes = pcall(to_codes, ulower(word))
      if okc then needle_tokens[#needle_tokens + 1] = codes end
    end
    if #needle_tokens == 0 then needle_tokens = nil end
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
    -- фильтр по тегам-чипам: карточка должна иметь все активные (AND)
    if ok and next(state.filter_tags) then
      local have = {}
      for _, t in ipairs(all_tags(card, meta)) do have[t] = true end
      for t in pairs(state.filter_tags) do
        if not have[t] then ok = false break end
      end
    end
    if ok and needle_tokens then
      local okm, m = pcall(fuzzy_match_all, needle_tokens, search_text(card, meta))
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
  search_cache, audio_cache, wave_cache, daw_cache = {}, {}, {}, {}
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
  search_cache[card.path] = nil -- статус входит в поисковую строку
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
-- Сабпроекты: вставка .rpp айтемом (SOURCE RPP_PROJECT) через InsertMedia.
-- Исходные проекты не изменяются; звук — из прокси, который REAPER рендерит
-- при сохранении саба, открытого из родителя (поэтому 41816, а не openProject).

-- Вставить path сабпроектом на текущий трек у edit-курсора активного
-- проекта. region ~= nil — обрезать айтем до региона.
local function insert_subproject(path, region)
  reaper.Main_OnCommand(40289, 0) -- Unselect all items: InsertMedia выделит свой
  reaper.InsertMedia(path, 0)
  local item = reaper.GetSelectedMediaItem(0, 0)
  if item and region then
    reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', region.fin - region.pos)
    local take = reaper.GetActiveTake(item)
    if take then
      reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', region.pos)
    end
  end
  return item
end

-- «Item: Open associated project in new tab»: сверяем имя по id, при
-- несовпадении ищем перебором — id различается между версиями REAPER.
local open_assoc_cmd
local function find_open_assoc()
  if open_assoc_cmd then return open_assoc_cmd end
  local function name(id)
    return (reaper.kbd_getTextFromCmd and reaper.kbd_getTextFromCmd(id, 0) or ''):lower()
  end
  if name(41816):find('associated project') then
    open_assoc_cmd = 41816
    return open_assoc_cmd
  end
  for id = 40000, 46000 do
    local n = name(id)
    if n:find('open associated project') then
      open_assoc_cmd = id
      return id
    end
  end
  return nil
end

-- Авто-рендер прокси: открыть саб именно как associated project (это
-- помечает таб сабпроектом), сохранить — REAPER рендерит прокси — закрыть.
-- Если таб не переключился на саб, НИЧЕГО не сохраняем и не закрываем.
local function render_proxies(placed)
  local cmd = find_open_assoc()
  if not cmd then
    reaper.MB('Не нашёл экшн «Item: Open associated project in new tab».\n' ..
      'Прокси не отрендерены: открой каждый саб двойным кликом и сохрани.',
      'JF PM — subprojects', 0)
    return
  end
  local parent = reaper.EnumProjects(-1)
  local done, fail = 0, 0
  local seen = {}
  for _, pl in ipairs(placed) do
    if not seen[pl.path] then
      seen[pl.path] = true
      reaper.Main_OnCommand(40289, 0) -- Unselect all items
      reaper.SetMediaItemSelected(pl.item, true)
      reaper.UpdateArrange()
      reaper.Main_OnCommand(cmd, 0)
      local sub, sub_fn = reaper.EnumProjects(-1)
      if sub ~= parent and sub_fn == pl.path then
        reaper.Main_SaveProject(0, false) -- сохранение саба рендерит прокси
        reaper.Main_OnCommand(40860, 0)   -- Close current project tab
        done = done + 1
      else
        -- саб не открылся — не трогаем активный таб
        if sub ~= parent then reaper.Main_OnCommand(40860, 0) end
        fail = fail + 1
      end
    end
  end
  reaper.UpdateArrange()
  if fail > 0 then
    reaper.MB(string.format(
      'Прокси: %d ок, %d не удалось.\nДля оставшихся: двойной клик по айтему' ..
      ' (откроется саб) и Cmd+S — REAPER отрендерит прокси.', done, fail),
      'JF PM — subprojects', 0)
  end
end

-- «Трек на проект»: для каждого пути новый трек с именем проекта,
-- айтемы-сабпроекты последовательно по времени. Возвращает {item, path}.
local function subs_layout(paths)
  local pos = reaper.GetProjectLength(0)
  local placed = {}
  for _, p in ipairs(paths) do
    local card = state.index.projects[p]
    local ntr = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(ntr, true)
    local tr = reaper.GetTrack(0, ntr)
    local name = p:match('([^/\\]+)%.[rR][pP][pP]$') or p
    reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', name, true)
    reaper.SetOnlyTrackSelected(tr)
    reaper.SetEditCurPos(pos, false, false)
    local item = insert_subproject(p)
    if item then
      placed[#placed + 1] = { item = item, path = p }
      pos = pos + ((card and card.duration)
        or reaper.GetMediaItemInfo_Value(item, 'D_LENGTH'))
    end
  end
  reaper.UpdateArrange()
  return placed
end

-- a) target_path = nil: новый таб; b) target_path: вставка в конец проекта
local function merge_as_subprojects(target_path)
  if #state.sel < 2 then return end
  local paths = {}
  for i, p in ipairs(state.sel) do paths[i] = p end
  if target_path then
    open_project(target_path)
  else
    reaper.Main_OnCommand(40859, 0) -- New project tab
  end
  local placed = subs_layout(paths)
  local items = {}
  for i, pl in ipairs(placed) do items[i] = pl.item end
  render_proxies(items)
  state.status_msg = string.format('Subprojects: %d%s', #placed,
    target_path and (' → ' .. target_path) or ' в новом проекте (не сохранён)')
  state.sel = {}
end

-- Регион кликом → сабпроект в активный проект (обрезанный до региона)
local function insert_region_subproject(path, region)
  local _, active_fn = reaper.EnumProjects(-1)
  if active_fn == path then
    state.status_msg = 'Регион из активного проекта — рекурсия, нельзя'
    return
  end
  local item = insert_subproject(path, region)
  if not item then
    state.status_msg = 'Регион: вставка не удалась'
    return
  end
  render_proxies({ item })
  state.status_msg = 'Регион → активный проект: '
    .. (region.name ~= '' and region.name or '(без имени)')
end

-- Корзина регионов (cmd+клик по региону): собрать новый проект — один трек,
-- регионы последовательно; прокси — по разу на уникальный исходник
local function basket_build()
  if #state.basket == 0 then return end
  reaper.Main_OnCommand(40859, 0) -- New project tab
  reaper.InsertTrackAtIndex(0, true)
  local tr = reaper.GetTrack(0, 0)
  reaper.GetSetMediaTrackInfo_String(tr, 'P_NAME', 'regions', true)
  local pos = 0
  local placed = {}
  for _, b in ipairs(state.basket) do
    reaper.SetOnlyTrackSelected(tr)
    reaper.SetEditCurPos(pos, false, false)
    local item = insert_subproject(b.path, b.region)
    if item then
      placed[#placed + 1] = { item = item, path = b.path }
      pos = pos + (b.region.fin - b.region.pos)
    end
  end
  local seen, uniq = {}, {}
  for _, pl in ipairs(placed) do
    if not seen[pl.path] then
      seen[pl.path] = true
      uniq[#uniq + 1] = pl.item
    end
  end
  render_proxies(uniq)
  state.status_msg = string.format('Проект из %d регионов (не сохранён)', #placed)
  state.basket = {}
end

-- '#ambient #flute #+++ intro' → title='intro', tags={ambient,flute}, rating=3
local function parse_region_name(name)
  local tags, rating = {}, 0
  local title = name:gsub('#([^%s#]+)', function(tok)
    local plus = tok:match('^%++$')
    if plus then
      if #plus > rating then rating = #plus end
    else
      tags[#tags + 1] = tok
    end
    return ''
  end)
  title = title:gsub('%s+', ' '):match('^%s*(.-)%s*$')
  return { title = title, tags = tags, rating = rating }
end

-- Правки закрытых .rpp (rename, дедлайн, чекбоксы) требуют, чтобы проект
-- не был открыт: открытый перезапишет файл при сохранении.
local function project_is_open(path)
  local i = 0
  while true do
    local proj, fn = reaper.EnumProjects(i)
    if not proj then break end
    if fn == path then return true end
    i = i + 1
  end
  return false
end

local function warn_open(card, action)
  reaper.MB('Проект «' .. card.name .. '» открыт в REAPER.\n\n' ..
    'Закрой вкладку проекта и повтори: ' .. action .. '.',
    'JF PM', 0)
end

-- Перечитать карточку с диска после текстовой правки .rpp
local function refresh_card(path)
  local old = state.index.projects[path]
  local nc = core.build_card(path, old)
  if nc then state.index.projects[path] = nc end
  core.save_index(state.index)
  search_cache[path], audio_cache[path], daw_cache[path] = nil, nil, nil
  return nc
end

-- Переименование: всё с префиксом имени + папка проекта (см. core).
local function rename_project(card, new_name)
  new_name = new_name:match('^%s*(.-)%s*$')
  if new_name == '' or new_name == card.name then return end
  if project_is_open(card.path) then
    warn_open(card, 'переименование')
    return
  end
  local new_path, extra = core.rename_project(card.path, new_name)
  if not new_path then
    state.status_msg = 'Переименование: ' .. tostring(extra)
    return
  end
  local old = state.index.projects[card.path]
  state.index.projects[card.path] = nil
  if old and old.thumb_user then
    -- превью с префиксом имени переименовалось — авто-поиск найдёт новое;
    -- уцелевший внешний файл остаётся
    local f = io.open(old.thumb_user, 'rb')
    if f then f:close() else old.thumb_user = nil end
  end
  local newcard = core.build_card(new_path, old)
  if newcard then state.index.projects[new_path] = newcard end
  core.save_index(state.index)
  search_cache[card.path] = nil
  for i, p in ipairs(state.sel) do
    if p == card.path then state.sel[i] = new_path end
  end
  if state.expanded == card.path then state.expanded = new_path end
  state.status_msg = 'Переименовано → ' .. new_path
end

-- Переключить чекбокс todo: правка источника (REPORT_TODO либо project
-- notes) в тексте .rpp, затем перечитать карточку.
local function toggle_todo(card, meta, todo)
  if project_is_open(card.path) then
    warn_open(card, 'правка todo')
    return
  end
  local src_text
  if todo.src == 'todo' then
    src_text = core.decode_ml((card.ext or {}).REPORT_TODO or '')
  else
    src_text = card.notes or ''
  end
  local out, ln = {}, 0
  for line in (src_text .. '\n'):gmatch('(.-)\n') do
    ln = ln + 1
    if ln == todo.line then
      local toggled = line:gsub('%[([ xXхХ])%]', function(m)
        return m == ' ' and '[x]' or '[ ]'
      end, 1)
      out[#out + 1] = toggled
    else
      out[#out + 1] = line
    end
  end
  while #out > 0 and out[#out] == '' do out[#out] = nil end
  local new_text = table.concat(out, '\n')
  local ok, err
  if todo.src == 'todo' then
    ok, err = core.set_ext_in_rpp(card.path, 'REPORT_TODO',
      core.encode_ml(new_text))
  else
    ok, err = core.set_project_notes(card.path, new_text)
  end
  if not ok then
    state.status_msg = 'Todo: ' .. tostring(err)
    return
  end
  refresh_card(card.path)
end

-- Дедлайн с карточки: пишется в extstate закрытого .rpp
local function set_deadline(card, text)
  text = text:match('^%s*(.-)%s*$')
  if project_is_open(card.path) then
    warn_open(card, 'дедлайн')
    return
  end
  local val = ''
  if text ~= '' then
    local ts = core.parse_date(text)
    if not ts then
      reaper.MB('Не понял дату «' .. text .. '».\nФормат: дд.мм или дд.мм.гг',
        'JF PM — дедлайн', 0)
      return
    end
    val = tostring(ts)
  end
  local ok, err = core.set_ext_in_rpp(card.path, 'DEADLINE', val)
  if not ok then
    state.status_msg = 'Дедлайн: ' .. tostring(err)
    return
  end
  refresh_card(card.path)
  state.status_msg = val == '' and 'Дедлайн снят'
    or ('Дедлайн: ' .. os.date('%d.%m.%y', tonumber(val)))
end

-- ---------------------------------------------------------------------------
-- Аудио-превью: микро-плеер на карточке. Волна/спектральные пики — из
-- PCM_Source_GetPeaks (кэш на файл), плейбек — SWS CF_Preview.
-- Источник звука: jf_preview.wav → прокси саба → RENDER_FILE проекта.

local AUDIO_EXT = { wav = true, aiff = true, aif = true, flac = true,
                    mp3 = true, ogg = true }

-- audio_cache: card.path -> путь к аудио | false (объявлен выше)
local function find_preview_audio(card)
  local hit = audio_cache[card.path]
  if hit ~= nil then return hit or nil end
  local dir = card.path:match('^(.*)[/\\]') or '.'
  local cands = {
    dir .. '/' .. card.name .. '_preview.wav',
    dir .. '/jf_preview.wav', -- легаси-имя до перехода на имя проекта
    card.path .. '-PROX.wav',
  }
  local rf = card.render_file or ''
  if rf ~= '' then
    if not rf:match('^/') then rf = dir .. '/' .. rf end
    local ext = rf:lower():match('%.([%w]+)$')
    if ext and AUDIO_EXT[ext] then cands[#cands + 1] = rf end
  end
  for _, p in ipairs(cands) do
    local f = io.open(p, 'rb')
    if f then
      f:close()
      audio_cache[card.path] = p
      return p
    end
  end
  audio_cache[card.path] = false
  return nil
end

-- пики: {n, max={}, min={}, spec={}|nil, len}; кэш на аудиофайл+режим (объявлен выше)
local WAVE_COLS = 160
local function get_wave(audio)
  local key = audio .. '|' .. state.peak_style
  local w = wave_cache[key]
  if w ~= nil then return w or nil end
  local src = reaper.PCM_Source_CreateFromFile(audio)
  if not src then wave_cache[key] = false return nil end
  local len = reaper.GetMediaSourceLength(src)
  if len <= 0 then
    reaper.PCM_Source_Destroy(src)
    wave_cache[key] = false
    return nil
  end
  local want_spec = state.peak_style == 1
  local mult = want_spec and 3 or 2
  local buf = reaper.new_array(WAVE_COLS * mult)
  local function fetch()
    buf.clear()
    local rv = reaper.PCM_Source_GetPeaks(src, WAVE_COLS / len, 0, 1,
      WAVE_COLS, want_spec and 115 or 0, buf)
    return rv & 0xfffff
  end
  local spl = fetch()
  if spl == 0 then
    -- пиков нет (.reapeaks не построен) — строим, с потолком итераций
    reaper.PCM_Source_BuildPeaks(src, 0)
    for _ = 1, 3000 do
      if reaper.PCM_Source_BuildPeaks(src, 1) == 0 then break end
    end
    reaper.PCM_Source_BuildPeaks(src, 2)
    spl = fetch()
  end
  if spl == 0 then
    reaper.PCM_Source_Destroy(src)
    wave_cache[key] = false
    return nil
  end
  local t = buf.table()
  local w2 = { n = spl, max = {}, min = {}, len = len,
               spec = want_spec and {} or nil }
  for i = 1, spl do
    w2.max[i] = t[i]
    w2.min[i] = t[spl + i]
    if want_spec then w2.spec[i] = t[2 * spl + i] end
  end
  reaper.PCM_Source_Destroy(src)
  wave_cache[key] = w2
  return w2
end

-- плейбек через SWS CF_Preview; одновременно играет один
local playing = { audio = nil, cfp = nil }
local function preview_stop()
  if playing.cfp then
    reaper.CF_Preview_Stop(playing.cfp)
    playing.audio, playing.cfp = nil, nil
  end
end

local function preview_toggle(audio)
  if not reaper.CF_CreatePreview then
    state.status_msg = 'Плеер: нужен SWS (CF_Preview)'
    return
  end
  if playing.audio == audio then
    preview_stop()
    return
  end
  preview_stop()
  local src = reaper.PCM_Source_CreateFromFile(audio)
  if not src then return end
  local cfp = reaper.CF_CreatePreview(src)
  reaper.PCM_Source_Destroy(src) -- CF_Preview держит свою копию
  reaper.CF_Preview_SetValue(cfp, 'D_VOLUME', state.preview_vol)
  reaper.CF_Preview_Play(cfp)
  playing.audio, playing.cfp = audio, cfp
end

-- цвет спектрального пика: частота (нижние 15 бит) → hue от красного к синему
local function spec_color(spec)
  local freq = math.max(spec & 0x7FFF, 30)
  local h = math.min(math.log(freq / 60) / math.log(16000 / 60), 1)
  return hash_color(10 + h * 230, 0.6, 0.95)
end

-- полоска-плеер: клик — play/stop; вернуть true, если клик был по полоске
local function draw_wave_strip(card, width, height)
  local audio = find_preview_audio(card)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + width, y0 + height,
    0x141414FF, 3)
  local clicked = false
  if not audio then
    ImGui.DrawList_AddText(dl, x0 + 6, y0 + height / 2 - 7, 0x5A5A5AFF,
      T('нет аудио · ▸ в карточке отрендерит превью'))
    ImGui.Dummy(ctx, width, height)
    return false
  end
  local w = get_wave(audio)
  if w then
    local mid = y0 + height / 2
    local step = width / w.n
    local is_playing = playing.audio == audio
    for i = 1, w.n do
      local x = x0 + (i - 1) * step
      local col = w.spec and spec_color(w.spec[i])
        or (is_playing and 0xD9B96CFF or 0x8A8F93FF)
      local hi = math.min(math.max(w.max[i], 0), 1) * (height / 2 - 1)
      local lo = math.min(math.max(-w.min[i], 0), 1) * (height / 2 - 1)
      ImGui.DrawList_AddRectFilled(dl, x, mid - hi, x + math.max(step - 1, 1),
        mid + lo + 1, col)
    end
    if is_playing and playing.cfp then
      local ok, pos = reaper.CF_Preview_GetValue(playing.cfp, 'D_POSITION')
      if ok and w.len > 0 then
        local px = x0 + math.min(pos / w.len, 1) * width
        ImGui.DrawList_AddLine(dl, px, y0, px, y0 + height, 0xFFFFFFDD, 1)
      end
      -- дошёл до конца — сброс
      local ok2, st2 = reaper.CF_Preview_GetValue(playing.cfp, 'B_PLAY')
      if ok2 and st2 == 0 then preview_stop() end
    end
  else
    ImGui.DrawList_AddText(dl, x0 + 6, y0 + height / 2 - 7, 0x5A5A5AFF,
      T('пики не построились'))
  end
  ImGui.InvisibleButton(ctx, '###wave' .. card.path, width, height)
  -- клик — играть с места клика / сик; правый клик — стоп
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
    local mx = ImGui.GetMousePos(ctx)
    local frac = math.min(math.max((mx - x0) / width, 0), 1)
    if playing.audio ~= audio then preview_toggle(audio) end
    if playing.cfp and w and w.len > 0 then
      reaper.CF_Preview_SetValue(playing.cfp, 'D_POSITION', frac * w.len)
    end
    clicked = true
  end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
    preview_stop()
    clicked = true
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, playing.audio == audio
      and T('клик — сик · пкм — стоп')
      or (T('играть: ') .. (audio:match('([^/\\]+)$') or audio)
        .. '\n' .. T('клик — с места клика · пкм — стоп')))
  end
  return clicked
end

-- «Грамотный рендер»: открыть проект, отрендерить jf_preview.wav целиком,
-- вернуть рендер-настройки на место, сохранить, закрыть таб.
local function render_preview(card)
  if project_is_open(card.path) then
    warn_open(card, 'рендер превью')
    return
  end
  local dir = card.path:match('^(.*)[/\\]') or '.'
  -- превью зовётся по имени проекта: у двух .rpp в одной папке — свои файлы
  local pv_name = card.name:gsub('%$', '') .. '_preview'
  local pv_path = dir .. '/' .. pv_name .. '.wav'
  os.remove(pv_path) -- иначе рендер спросит про перезапись

  -- рендер на полной скорости: RENDER_1X 0 правится в тексте .rpp до
  -- открытия (в API поля скорости нет), после закрытия возвращается
  local old_1x = core.set_project_token(card.path, 'RENDER_1X', '0')

  reaper.Main_OnCommand(40859, 0)
  reaper.Main_openProject(card.path)
  local proj = reaper.EnumProjects(-1)
  local function gets(k)
    local _, v = reaper.GetSetProjectInfo_String(proj, k, '', false)
    return v
  end
  local old = {
    file = gets('RENDER_FILE'), pat = gets('RENDER_PATTERN'),
    fmt = gets('RENDER_FORMAT'),
    bounds = reaper.GetSetProjectInfo(proj, 'RENDER_BOUNDSFLAG', 0, false),
    settings = reaper.GetSetProjectInfo(proj, 'RENDER_SETTINGS', 0, false),
    spos = reaper.GetSetProjectInfo(proj, 'RENDER_STARTPOS', 0, false),
    epos = reaper.GetSetProjectInfo(proj, 'RENDER_ENDPOS', 0, false),
  }
  local function restore_1x()
    core.set_project_token(card.path, 'RENDER_1X',
      old_1x ~= false and old_1x or nil)
  end
  -- вернуть mtime .rpp как был: рендер превью (и правка RENDER_1X) — не
  -- «работа над проектом», батч не должен ломать сортировку по дате
  local function restore_mtime()
    if card.mtime and card.mtime > 0 then
      reaper.ExecProcess('/usr/bin/touch -m -t '
        .. os.date('%Y%m%d%H%M.%S', card.mtime)
        .. ' "' .. card.path .. '"', 5000)
    end
  end

  -- границы: весь проект, но не длиннее лимита превью; если конца нет
  -- (нулевая длина) — первый регион (тоже с лимитом)
  local PREVIEW_MAX = 300 -- лимит длины превью: 5 минут
  local plen = reaper.GetProjectLength(proj)
  local bounds_note = ''
  if plen <= 0.05 then
    local rgn_start, rgn_end, rgn_name
    local idx = 0
    while true do
      local rv, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers2(proj, idx)
      if rv == 0 then break end
      if isrgn then rgn_start, rgn_end, rgn_name = pos, rgnend, name break end
      idx = idx + 1
    end
    if not rgn_start then
      reaper.Main_OnCommand(40860, 0) -- закрыть таб, рендерить нечего
      restore_1x()
      restore_mtime()
      state.status_msg = T('Превью: у проекта нет ни конца, ни регионов')
      return
    end
    rgn_end = math.min(rgn_end, rgn_start + PREVIEW_MAX)
    reaper.GetSetProjectInfo(proj, 'RENDER_BOUNDSFLAG', 0, true) -- custom
    reaper.GetSetProjectInfo(proj, 'RENDER_STARTPOS', rgn_start, true)
    reaper.GetSetProjectInfo(proj, 'RENDER_ENDPOS', rgn_end, true)
    bounds_note = ' (' .. T('первый регион: ') ..
      (rgn_name ~= '' and rgn_name or '?') .. ')'
  elseif plen > PREVIEW_MAX then
    reaper.GetSetProjectInfo(proj, 'RENDER_BOUNDSFLAG', 0, true) -- custom
    reaper.GetSetProjectInfo(proj, 'RENDER_STARTPOS', 0, true)
    reaper.GetSetProjectInfo(proj, 'RENDER_ENDPOS', PREVIEW_MAX, true)
    bounds_note = T(' (первые 5 мин)')
  else
    reaper.GetSetProjectInfo(proj, 'RENDER_BOUNDSFLAG', 1, true) -- весь проект
  end

  reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', dir, true)
  reaper.GetSetProjectInfo_String(proj, 'RENDER_PATTERN', pv_name, true)
  reaper.GetSetProjectInfo_String(proj, 'RENDER_FORMAT', 'evaw', true)
  reaper.GetSetProjectInfo(proj, 'RENDER_SETTINGS', 0, true) -- master mix
  reaper.Main_OnCommand(41824, 0) -- File: Render project, using the most recent render settings
  -- REAPER часто видит конец проекта сильно дальше звука (огибающие,
  -- маркеры) — отрезаем цифровую тишину в хвосте, оставляя секунду
  local trimmed, cut = core.trim_wav_tail(pv_path, 1.0)
  if trimmed then
    bounds_note = bounds_note .. string.format(' · хвост −%d c', math.floor(cut + 0.5))
  end
  reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', old.file, true)
  reaper.GetSetProjectInfo_String(proj, 'RENDER_PATTERN', old.pat, true)
  reaper.GetSetProjectInfo_String(proj, 'RENDER_FORMAT', old.fmt, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_BOUNDSFLAG', old.bounds, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_SETTINGS', old.settings, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_STARTPOS', old.spos, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_ENDPOS', old.epos, true)
  reaper.Main_SaveProject(0, false)
  reaper.Main_OnCommand(40860, 0) -- Close current project tab
  restore_1x()
  restore_mtime()
  audio_cache[card.path] = nil
  for k in pairs(wave_cache) do
    if k:find(pv_path, 1, true) == 1 then wave_cache[k] = nil end
  end
  state.status_msg = T('Превью отрендерено') .. bounds_note .. ': ' .. pv_path
end

-- Батч «превью всем»: очередь путей, по одному проекту на кадр defer-цикла
-- (каждый рендер — модальный, но между ними UI дышит и кнопка «стоп» жива)
local function batch_step()
  local bq = state.batch
  if not bq then return end
  local path = table.remove(bq.queue, 1)
  if not path then
    state.status_msg = string.format(T('Превью-батч: готово %d'), bq.done)
    state.batch = nil
    return
  end
  local card = state.index.projects[path]
  if card and not project_is_open(path) then
    render_preview(card)
    bq.done = bq.done + 1
  end
  state.status_msg = string.format(T('Превью-батч: %d/%d'),
    bq.done, bq.total)
end

local function batch_start()
  local queue = {}
  for path, card in pairs(state.index.projects) do
    if not find_preview_audio(card) then queue[#queue + 1] = path end
  end
  table.sort(queue, function(a, b)
    return (state.index.projects[a].mtime or 0)
         > (state.index.projects[b].mtime or 0)
  end)
  if #queue == 0 then
    state.status_msg = T('Превью-батч: у всех уже есть аудио')
    return
  end
  state.batch = { queue = queue, done = 0, total = #queue }
end

-- ---------------------------------------------------------------------------
-- dawsync: ссылки на проекты других DAW в заметках и именах регионов.
-- «мой трек.als» в item/track/project notes или имени региона → кнопка,
-- открывающая связанный проект (папка проекта, иначе mdfind).

local DAW_EXTS = 'als|ptx|ptf|logicx|lpx|rns|reason|flp|cpr|song|bwproject|dawproject'

local function daw_links(card)
  local hit = daw_cache[card.path]
  if hit then return hit end
  local seen, out = {}, {}
  local function scan(text)
    if not text or text == '' then return end
    for line in (text .. '\n'):gmatch('(.-)\n') do
      for ext in DAW_EXTS:gmatch('[^|]+') do
        for name in line:gmatch('([^%s#][^#|]-%.' .. ext .. ')') do
          name = name:match('^%s*(.-)%s*$')
          if name ~= '' and not seen[name:lower()] then
            seen[name:lower()] = true
            out[#out + 1] = name
          end
        end
      end
    end
  end
  scan(card.notes)
  for _, r in ipairs(card.regions or {}) do scan(r.name) end
  for _, n in ipairs(card.track_notes or {}) do scan(n.s) end
  for _, n in ipairs(card.item_notes or {}) do scan(n.s) end
  daw_cache[card.path] = out
  return out
end

local function open_daw_project(card, name)
  local path
  if name:match('^/') then
    path = name
  else
    local dir = card.path:match('^(.*)[/\\]') or '.'
    local local_p = dir .. '/' .. name
    local f = io.open(local_p, 'rb')
    if f then
      f:close()
      path = local_p
    else
      -- Spotlight: ищем по имени файла по всему диску
      local out = reaper.ExecProcess(
        '/usr/bin/mdfind -name "' .. name .. '"', 5000)
      if out then
        path = out:gsub('^%d+\n', ''):match('([^\n]+)')
      end
    end
  end
  if not path or path == '' then
    state.status_msg = 'DAW-проект не найден: ' .. name
    return
  end
  if reaper.CF_ShellExecute then
    reaper.CF_ShellExecute(path)
  else
    reaper.ExecProcess('/usr/bin/open "' .. path .. '"', -1)
  end
  state.status_msg = 'Открываю: ' .. path
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

-- md-lite: # заголовки, - буллеты; строки-чекбоксы пропускаются
-- (они рисуются интерактивно в блоке TODO)
local function draw_md(text)
  for line in (text .. '\n'):gmatch('(.-)\n') do
    local todo = line:match('^%s*[-*]%s*%[[ xXхХ]%]')
    local h = line:match('^#+%s*(.+)')
    local b = line:match('^%s*[-*]%s+(.+)')
    if todo then -- пропуск
    elseif h then
      ImGui.TextColored(ctx, 0xD9B96CFF, h)
    elseif b then
      ImGui.BulletText(ctx, b)
    elseif line ~= '' then
      ImGui.TextWrapped(ctx, line)
    end
  end
end

local function deadline_color(ts, now)
  if ts < now then return 0xE06060FF end                -- просрочен
  if ts < now + 7 * 86400 then return 0xD9B96CFF end    -- неделя
  return 0x8A8F93FF
end

local function draw_card_details(card, meta)
  ImGui.Separator(ctx)
  ImGui.Text(ctx, string.format('%s BPM · %d/%d · %d трек(ов)',
    card.tempo and tostring(card.tempo) or '—',
    card.timesig_num or 4, card.timesig_den or 4, card.track_count or 0))

  if meta.desc ~= '' then
    ImGui.TextWrapped(ctx, meta.desc)
  end

  -- дедлайн: показ + инлайн-правка (пишется в .rpp закрытого проекта)
  local now = os.time()
  ImGui.TextDisabled(ctx, T('Дедлайн:'))
  ImGui.SameLine(ctx)
  if meta.deadline > 0 then
    local left = math.floor((meta.deadline - now) / 86400)
    ImGui.TextColored(ctx, deadline_color(meta.deadline, now),
      os.date('%d.%m.%y', meta.deadline) ..
      (left < 0 and ('  (' .. T('просрочен') .. ')') or ('  (' .. left .. ' ' .. T('дн.') .. ')')))
    ImGui.SameLine(ctx)
  end
  if state.dl_path == card.path then
    ImGui.SetNextItemWidth(ctx, 110)
    if state.dl_focus then
      ImGui.SetKeyboardFocusHere(ctx)
      state.dl_focus = false
    end
    local done, v = ImGui.InputTextWithHint(ctx, '###dl', 'дд.мм[.гг]',
      state.dl_text, ImGui.InputTextFlags_EnterReturnsTrue)
    if v then state.dl_text = v end
    if done then
      set_deadline(card, state.dl_text)
      state.dl_path = nil
      return
    end
  else
    if ImGui.SmallButton(ctx, (meta.deadline > 0 and T('изменить')
        or T('назначить')) .. '###dl') then
      state.dl_path = card.path
      state.dl_text = meta.deadline > 0 and os.date('%d.%m.%y', meta.deadline) or ''
      state.dl_focus = true
    end
    if meta.deadline > 0 then
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, T('снять') .. '###dlx') then
        set_deadline(card, '')
        return
      end
    end
  end

  -- ID трека (каталожный/площадка) и использованные семплы — extstate,
  -- пишется в закрытый .rpp; семплы ищутся в fzf
  local function ext_field(title, key, val)
    ImGui.TextDisabled(ctx, title)
    ImGui.SameLine(ctx)
    local ek = card.path .. '|' .. key
    if state.ext_edit == ek then
      ImGui.SetNextItemWidth(ctx, -70)
      if state.ext_focus then
        ImGui.SetKeyboardFocusHere(ctx)
        state.ext_focus = false
      end
      local done, v = ImGui.InputText(ctx, '###ef' .. key, state.ext_text,
        ImGui.InputTextFlags_EnterReturnsTrue)
      if v then state.ext_text = v end
      if done then
        if project_is_open(card.path) then
          warn_open(card, title)
        else
          core.set_ext_in_rpp(card.path, key, state.ext_text)
          refresh_card(card.path)
        end
        state.ext_edit = nil
        return true -- карточка перечитана — перерисовать
      end
    else
      if val ~= '' then
        ImGui.Text(ctx, val)
        ImGui.SameLine(ctx)
      end
      if ImGui.SmallButton(ctx,
          (val ~= '' and T('изменить') or T('добавить')) .. '###ef' .. key) then
        state.ext_edit, state.ext_text, state.ext_focus = ek, val, true
      end
    end
    return false
  end
  if ext_field(T('ID трека:'), 'TRACKID', meta.track_id) then return end
  if ext_field(T('Семплы:'), 'SAMPLES', meta.samples) then return end

  -- TODO: чекбоксы из отчёта и project notes (md: - [ ] / - [x])
  if #meta.todos > 0 then
    ImGui.TextDisabled(ctx, 'TODO:')
    for ti, td in ipairs(meta.todos) do
      local changed = ImGui.Checkbox(ctx, td.text .. '###td' .. ti, td.done)
      if changed then
        toggle_todo(card, meta, td)
        return
      end
    end
  end

  -- регионы кликабельны: клик — subproject-айтем региона в активный проект,
  -- cmd/ctrl+клик — в корзину регионов; #хэштеги из имени цветные, #+++ рейтинг
  if #card.regions > 0 then
    ImGui.TextDisabled(ctx, T('Структура:'))
    for ri, r in ipairs(card.regions) do
      local pr = parse_region_name(r.name or '')
      local label = string.format('%s  [%s – %s]',
        pr.title ~= '' and pr.title or '(без имени)',
        fmt_duration(r.pos), fmt_duration(r.fin))
      if ImGui.SmallButton(ctx, label .. '###reg' .. ri) then
        local mods = ImGui.GetKeyMods(ctx)
        if mods & ImGui.Mod_Ctrl ~= 0 or mods & ImGui.Mod_Super ~= 0 then
          state.basket[#state.basket + 1] = { path = card.path, region = r }
          state.status_msg = string.format(T('В корзине регионов: %d'), #state.basket)
        else
          insert_region_subproject(card.path, r)
        end
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx,
          T('клик — subproject в активный проект\nCmd+клик — в корзину регионов'))
      end
      for _, t in ipairs(pr.tags) do
        ImGui.SameLine(ctx)
        ImGui.TextColored(ctx, tag_color(t), '#' .. t)
      end
      if pr.rating > 0 then
        ImGui.SameLine(ctx)
        ImGui.TextColored(ctx, 0xD9B96CFF, string.rep('+', pr.rating))
      end
    end
  end

  -- треки свёрнуты по умолчанию, как бэкапы
  if #card.track_names > 0 then
    if ImGui.TreeNode(ctx, string.format('%s (%d)###trk', T('Треки'), #card.track_names)) then
      local named = {}
      for _, n in ipairs(card.track_names) do
        named[#named + 1] = n ~= '' and n or '(без имени)'
      end
      ImGui.TextWrapped(ctx, table.concat(named, ', '))
      ImGui.TreePop(ctx)
    end
  end

  -- заметки: проект / треки / айтемы — свёрнуты, как бэкапы
  if (card.notes or '') ~= '' then
    if ImGui.TreeNode(ctx, T('Заметки проекта') .. '###pnotes') then
      draw_md(card.notes)
      ImGui.TreePop(ctx)
    end
  end
  local tnotes = card.track_notes or {}
  if #tnotes > 0 then
    if ImGui.TreeNode(ctx, string.format('%s (%d)###tnotes', T('Заметки треков'),
        #tnotes)) then
      for _, n in ipairs(tnotes) do
        local tname = (card.track_names or {})[n.t] or ''
        ImGui.BulletText(ctx, (tname ~= '' and tname or ('трек ' .. n.t)) .. ':')
        ImGui.Indent(ctx)
        draw_md(n.s)
        ImGui.Unindent(ctx)
      end
      ImGui.TreePop(ctx)
    end
  end
  local inotes = card.item_notes or {}
  if #inotes > 0 then
    if ImGui.TreeNode(ctx, string.format('%s (%d)###inotes', T('Заметки айтемов'),
        #inotes)) then
      for _, n in ipairs(inotes) do
        ImGui.BulletText(ctx, string.format('[%s, трек %d]',
          fmt_duration(n.p), n.t))
        ImGui.Indent(ctx)
        draw_md(n.s)
        ImGui.Unindent(ctx)
      end
      ImGui.TreePop(ctx)
    end
  end

  if meta.report_done ~= '' or meta.report_todo ~= '' then
    ImGui.TextDisabled(ctx, T('Отчёт') .. ' (' .. fmt_date(meta.report_ts) .. '):')
    if meta.report_done ~= '' then
      ImGui.TextDisabled(ctx, T('Сделано:'))
      draw_md(meta.report_done)
    end
    if meta.report_todo ~= '' then
      ImGui.TextDisabled(ctx, T('Дальше:'))
      draw_md(meta.report_todo)
    end
  else
    ImGui.TextDisabled(ctx, T('Отчёта нет'))
  end

  -- скрытая ветка: бэкапы (свёрнута по умолчанию)
  local backups = card.backups or {}
  if #backups > 0 then
    if ImGui.TreeNode(ctx, string.format('%s (%d)###bak', T('Бэкапы'), #backups)) then
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
  ImGui.TextDisabled(ctx, T('Теги:'))
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
        state.status_msg = T('Тег из .rpp/Finder — снимай в проекте')
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
    local done, v = ImGui.InputTextWithHint(ctx, '###newtag', T('тег + Enter'),
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

  -- dawsync: связанные проекты других DAW из заметок/регионов
  local links = daw_links(card)
  if #links > 0 then
    ImGui.TextDisabled(ctx, 'DAW:')
    for li, name in ipairs(links) do
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, name .. '###daw' .. li) then
        open_daw_project(card, name)
      end
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
  if icon('▲###fold', T('свернуть')) then state.expanded = nil end
  ImGui.SameLine(ctx)
  if icon((card.pinned and '●' or '○') .. '###pin',
      card.pinned and T('открепить') or T('закрепить'),
      card.pinned and 0xD9B96CFF or nil) then
    toggle_pin(card)
  end
  ImGui.SameLine(ctx)
  local si = sel_index(card.path)
  if icon((si and '■' or '□') .. '###sel',
      si and T('снять выбор') or T('выбрать'), si and 0xD9B96CFF or nil) then
    toggle_select(card.path)
  end
  ImGui.SameLine(ctx)
  if icon('×###del', T('удалить в Корзину…')) then
    delete_project(card)
    return
  end
  ImGui.SameLine(ctx)
  if icon('▦###thumb', T('назначить картинку-превью…')) then
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
    if icon('▧###unthumb', T('сбросить превью')) then
      card.thumb_user = nil
      core.save_index(state.index)
    end
  end
  ImGui.SameLine(ctx)
  if icon('▸###rprev', T('отрендерить аудио-превью (jf_preview.wav)')) then
    render_preview(card)
    return
  end
  ImGui.SameLine(ctx)
  if icon('↻###refr', T('обновить карточку (перечитать .rpp)')) then
    refresh_card(card.path)
    state.status_msg = T('Обновлено: ') .. card.name
    return
  end
  ImGui.SameLine(ctx)
  if icon('Aa###ren', T('переименовать проект…')) then
    if state.ren_path == card.path then
      state.ren_path = nil
    else
      state.ren_path, state.ren_text = card.path, card.name
      state.ren_focus = true
    end
  end
  if state.ren_path == card.path then
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 200)
    if state.ren_focus then
      ImGui.SetKeyboardFocusHere(ctx)
      state.ren_focus = false
    end
    local done, v = ImGui.InputTextWithHint(ctx, '###rename',
      T('новое имя + Enter'), state.ren_text, ImGui.InputTextFlags_EnterReturnsTrue)
    if v then state.ren_text = v end
    if done then
      rename_project(card, state.ren_text)
      state.ren_path = nil
      return
    end
  end
end

local function draw_card(entry, i, card_w)
  local card, meta = entry.card, entry.meta
  local expanded = state.expanded == card.path
  local focused = state.focus == i
  local si = sel_index(card.path)
  local inner_click = false  -- клик по виджету внутри — не раскрывать карточку
  local cs = CARD_SIZES[state.card_size]
  local h = expanded and 0 or cs.h  -- 0 = авто-высота по контенту

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
    draw_thumb(card, cs.thumb)
    ImGui.SameLine(ctx)
    ImGui.BeginGroup(ctx)
    ImGui.Text(ctx, trunc(card.name, cs.name))
    if card.pinned then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0xD9B96CFF, '●') -- закреплён
    end
    if si then
      ImGui.SameLine(ctx)
      -- номер в выборке = позиция в merge
      ImGui.TextColored(ctx, 0xD9B96CFF, '[' .. si .. ']')
    end
    -- обновить одну карточку (перечитать .rpp) и ячейка выделения — в углу
    ImGui.SameLine(ctx, card_w - 56)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x6A6A6AFF)
    if ImGui.SmallButton(ctx, '↻###refr1') then
      refresh_card(card.path)
      state.status_msg = T('Обновлено: ') .. card.name
      inner_click = true
    end
    ImGui.PopStyleColor(ctx)
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, T('обновить карточку'))
    end
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
      -- прогресс по пайплайну: ●●○○○ = «отмиксить»
      local dots = string.rep('●', stage) ..
                   string.rep('○', core.PIPELINE_STEPS - stage)
      ImGui.TextColored(ctx, color or 0xAAAAAAFF, dots)
      ImGui.SameLine(ctx)
    end
    -- класс — выпадашкой прямо на карточке (пишется в индекс, как канбан)
    local cur_idx = 0
    for si2, s2 in ipairs(core.STATUSES) do
      if s2 == meta.status then cur_idx = si2 end
    end
    ImGui.SetNextItemWidth(ctx, 96)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, color or 0x9A9A9AFF)
    local chg, ni = ImGui.Combo(ctx, '###cls' .. i, cur_idx, class_labels())
    ImGui.PopStyleColor(ctx)
    if ImGui.IsItemHovered(ctx) or ImGui.IsItemActive(ctx) then
      inner_click = true
    end
    if chg then
      set_status(card, ni == 0 and '' or core.STATUSES[ni])
      inner_click = true
    end
    if card.needs_report then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0xE06060FF, T('· без отчёта'))
    end

    ImGui.TextDisabled(ctx, fmt_date(card.mtime))
    if (meta.deadline or 0) > 0 then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, deadline_color(meta.deadline, os.time()),
        '→ ' .. os.date('%d.%m', meta.deadline))
    end
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

    -- микро-плеер: волна/спектр, клик — play/stop
    if draw_wave_strip(card, ImGui.GetContentRegionAvail(ctx), 20) then
      inner_click = true
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
    ImGui.TextDisabled(ctx, T('Пусто. Rescan, или ослабь фильтры.'))
    return 1
  end
  local avail = ImGui.GetContentRegionAvail(ctx)
  local card_w = CARD_SIZES[state.card_size].w
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
    ImGui.TextDisabled(ctx, T('Пусто. Rescan, или ослабь фильтры.'))
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
        T('старше полугода'))
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
  -- дедлайны — отдельным слоем, они в будущем
  local dl_days = {}
  for _, e in ipairs(cards) do
    mark(e.card.mtime, e.card.name)
    mark(e.meta.report_ts, e.card.name)
    for _, b in ipairs(e.card.backups or {}) do mark(b.mtime, e.card.name) end
    if (e.meta.deadline or 0) > 0 then
      local key = day_key(e.meta.deadline)
      local t = dl_days[key]
      if not t then t = {} dl_days[key] = t end
      t[#t + 1] = e.card.name
    end
  end

  -- диапазон: от старейшей активности (но не меньше 26 недель) до сегодня,
  -- дальше в будущее — до самого позднего дедлайна (минимум 2 недели)
  local oldest, latest = now, now + 13 * DAY
  for k in pairs(act) do if k < oldest then oldest = k end end
  for k in pairs(dl_days) do if k > latest then latest = k end end
  local WEEKS = math.max(26, math.ceil((day_key(now) - oldest) / (7 * DAY)) + 1)
  local cell, gap = 16, 3
  local wd = (os.date('*t', now).wday + 5) % 7 -- 0 = понедельник
  local monday = day_key(now) - wd * DAY
  local start = monday - (WEEKS - 1) * 7 * DAY
  local FUT_WEEKS = math.ceil((day_key(latest) - monday) / (7 * DAY)) + 1
  WEEKS = WEEKS + FUT_WEEKS

  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  y0 = y0 + 16 -- место под метки месяцев
  local dl = ImGui.GetWindowDrawList(ctx)
  local mx, my = ImGui.GetMousePos(ctx)
  local hover_key, hover_act, hover_dl
  local prev_month = ''
  local today_key = day_key(now)
  for w = 0, WEEKS - 1 do
    for d = 0, 6 do
      local ts = start + (w * 7 + d) * DAY + DAY / 2
      if ts > day_key(latest) + DAY then break end
      local key = day_key(ts)
      local cx = x0 + w * (cell + gap)
      local cy = y0 + d * (cell + gap)
      local a = act[key]
      local future = key > today_key
      local col = future and 0x141414FF or 0x1B1B1BFF
      if a then
        col = a.n >= 3 and 0xE8E8E8FF or (a.n == 2 and 0x9A9A9AFF or 0x5C5C5CFF)
      end
      ImGui.DrawList_AddRectFilled(dl, cx, cy, cx + cell, cy + cell, col, 2)
      if dl_days[key] then
        -- дедлайн: янтарная рамка (просроченный — красная)
        ImGui.DrawList_AddRect(dl, cx, cy, cx + cell, cy + cell,
          key < today_key and 0xE06060FF or 0xD9B96CFF, 2, 0, 2)
      end
      if key == today_key then
        ImGui.DrawList_AddRect(dl, cx, cy, cx + cell, cy + cell, 0xE8E8E8FF, 2)
      end
      if mx >= cx and mx < cx + cell and my >= cy and my < cy + cell then
        hover_key, hover_act, hover_dl = key, a, dl_days[key]
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
  -- при входе в календарь скроллим к сегодняшнему дню (2 кадра:
  -- GetScrollMaxX узнаёт новую ширину контента только со следующего);
  -- будущее с дедлайнами остаётся справа за краем
  if (state.cal_scroll_end or 0) > 0 then
    local today_x = (WEEKS - FUT_WEEKS + 2) * (cell + gap)
    local target = math.max(0, today_x - ImGui.GetWindowWidth(ctx) + 60)
    ImGui.SetScrollX(ctx, math.min(target, ImGui.GetScrollMaxX(ctx)))
    state.cal_scroll_end = state.cal_scroll_end - 1
  end
  ImGui.TextDisabled(ctx, T('активность = сохранения, бэкапы, отчёты' ..
    ' · ярче — больше проектов · рамка — дедлайн · белая рамка — сегодня'))
  if hover_key then
    local txt = os.date('%d.%m.%Y', hover_key + 3600)
    if hover_dl then
      txt = txt .. '\nдедлайн: ' .. table.concat(hover_dl, ', ')
    end
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
        string.format('%s (%d)', c.status ~= '' and status_label(c.status)
          or c.label, #c.entries))
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
  ImGui.SeparatorText(ctx, T('Пути'))
  local changed, val

  ImGui.Text(ctx, T('Проекты (через ;):'))
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

  ImGui.Text(ctx, T('Расслоение → мультитреки:'))
  ImGui.SetNextItemWidth(ctx, -86)
  changed, val = ImGui.InputText(ctx, '##stems', state.stems_path)
  if changed then state.stems_path = val end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Finder##stems') then
    local dir = pick_folder('Папка мультитреков', state.stems_path)
    if dir then state.stems_path = dir end
  end

  ImGui.Text(ctx, T('Расслоение → регионы:'))
  ImGui.SetNextItemWidth(ctx, -86)
  changed, val = ImGui.InputText(ctx, '##regions', state.regions_path)
  if changed then state.regions_path = val end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Finder##regions') then
    local dir = pick_folder('Папка регионов', state.regions_path)
    if dir then state.regions_path = dir end
  end

  ImGui.Text(ctx, T('Тамбнейлы:'))
  ImGui.SameLine(ctx)
  if chip(T('калейдоскоп') .. '###th0', state.thumb_style == 0) then state.thumb_style = 0 end
  ImGui.SameLine(ctx)
  if chip(T('иероглиф') .. '###th1', state.thumb_style == 1) then state.thumb_style = 1 end
  ImGui.SameLine(ctx)
  if chip(T('навигатор') .. '###th2', state.thumb_style == 2) then state.thumb_style = 2 end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, T('или <имя проекта>.png / jf_thumb.png в папке проекта'))
  ImGui.Text(ctx, T('Аудио-пики:'))
  ImGui.SameLine(ctx)
  if chip(T('волна') .. '###pk0', state.peak_style == 0) then
    state.peak_style = 0
    core.set_setting('peak_style', '0')
  end
  ImGui.SameLine(ctx)
  if chip(T('спектр') .. '###pk1', state.peak_style == 1) then
    state.peak_style = 1
    core.set_setting('peak_style', '1')
  end
  ImGui.Text(ctx, T('Язык / Language:'))
  ImGui.SameLine(ctx)
  if chip('RU###lru', LANG == 'ru') then
    LANG = 'ru'
    core.set_setting('lang', 'ru')
  end
  ImGui.SameLine(ctx)
  if chip('EN###len', LANG == 'en') then
    LANG = 'en'
    core.set_setting('lang', 'en')
  end
  if state.batch then
    if ImGui.Button(ctx, string.format(T('стоп превью-батча (%d/%d)'),
        state.batch.done, state.batch.total)) then
      state.batch = nil
      state.status_msg = T('Превью-батч остановлен')
    end
  else
    if ImGui.Button(ctx, T('Сделать превью всем проектам (у кого нет аудио)')) then
      batch_start()
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, T('лимит 5 мин · рендер offline · можно остановить'))
  end

  if ImGui.Button(ctx, T('Сохранить настройки')) then
    core.set_setting('scan_paths', state.scan_paths)
    core.set_setting('stems_path', state.stems_path)
    core.set_setting('regions_path', state.regions_path)
    core.set_setting('thumb_style', tostring(state.thumb_style))
    state.show_settings = false
    state.status_msg = T('Настройки сохранены')
  end
  ImGui.Separator(ctx)
end

local function draw_toolbar()
  if ImGui.Button(ctx, 'Rescan') then rescan() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, T('настройки')) then
    state.show_settings = not state.show_settings
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, T('галерея')) then export_gallery() end
  -- громкость превью (слайдер — согласованное исключение, как выпадашка)
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 90)
  local vchg, nv = ImGui.SliderDouble(ctx, '###pvol', state.preview_vol,
    0.0, 1.0, 'vol %.2f')
  if vchg then
    state.preview_vol = nv
    if playing.cfp then
      reaper.CF_Preview_SetValue(playing.cfp, 'D_VOLUME', nv)
    end
  end
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then
    core.set_setting('preview_vol', string.format('%.3f', state.preview_vol))
  end

  -- блок выборки: порядок номеров = порядок склейки; при нескольких
  -- выделенных — те же команды, что на карточке, но на всю выборку
  if #state.sel > 0 then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0xD9B96CFF, string.format(T('выбрано: %d'), #state.sel))
    if #state.sel >= 2 then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, 'merge') then merge_selected() end
      ImGui.SameLine(ctx)
      -- сабпроектами: исходники не трогаются, звук — прокси
      if ImGui.Button(ctx, 'merge as subs') then merge_as_subprojects(nil) end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, T('subs → проект…')) then
        local rv, fn = reaper.GetUserFileNameForRead('', 'Целевой проект', 'rpp')
        if rv and fn and fn ~= '' then merge_as_subprojects(fn) end
      end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, T('открыть') .. '###selopen') then
        for _, p in ipairs(state.sel) do open_project(p) end
      end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, T('закрепить') .. '###selpin') then pin_selected() end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, T('удалить…') .. '###seldel') then delete_selected() end
    end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, T('сброс') .. '###selclr') then state.sel = {} end
  end

  -- корзина регионов (cmd+клик по региону в карточке)
  if #state.basket > 0 then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0xD9B96CFF,
      string.format(T('регионов: %d'), #state.basket))
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, T('собрать проект') .. '###bskgo') then basket_build() end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, T('сброс') .. '###bsk') then state.basket = {} end
  end

  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  for i, label in ipairs(VIEW_CHIPS) do
    ImGui.SameLine(ctx)
    if chip(T(label) .. '###view' .. i, state.view == i - 1) then
      state.view = i - 1
      state.focus = 0
      state.cal_scroll_end = 2
    end
  end

  -- WIP-счётчик: >3 в активной работе — многовато, внимание расползается
  local wip, no_report = 0, 0
  for _, card in pairs(state.index.projects) do
    local s = (card.ext or {}).STATUS or ''
    s = core.STATUS_ALIASES[s] or s
    if s == 'доделать' or s == 'отмиксить' or s == 'мастеринг' then wip = wip + 1 end
    if card.needs_report then no_report = no_report + 1 end
  end
  ImGui.SameLine(ctx)
  ImGui.TextColored(ctx, wip > 3 and 0xE06060FF or 0x8A8A8AFF,
    string.format('WIP: %d', wip))
  if no_report > 0 then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0xE06060FF, string.format(T('без отчёта: %d'), no_report))
  end

  -- ряд фильтров
  if chip(T('активные') .. '###fact', state.filter_status == 0) then state.filter_status = 0 end
  ImGui.SameLine(ctx)
  if chip(T('все') .. '###fall', state.filter_status == 1) then state.filter_status = 1 end
  ImGui.SameLine(ctx)
  if chip(T('без отчёта') .. '###fnr', state.filter_status == 2) then state.filter_status = 2 end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  for i, s in ipairs(core.STATUSES) do
    ImGui.SameLine(ctx)
    if chip(status_label(s) .. '###fst' .. i, state.filter_status == i + 2) then
      state.filter_status = i + 2
    end
  end

  -- ряд сортировки + размер карточек + тег
  ImGui.TextDisabled(ctx, T('сорт:'))
  for i, s in ipairs(SORT_CHIPS) do
    ImGui.SameLine(ctx)
    local active = state.sort_mode == i
    local label = T(s)
    if active then
      local desc = SORT_DESC_NATURAL[i] ~= state.sort_rev
      label = T(s) .. (desc and ' ↓' or ' ↑')
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
  -- размер карточек в сетке
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  for i, cs in ipairs(CARD_SIZES) do
    ImGui.SameLine(ctx)
    if chip(cs.label .. '###csize' .. i, state.card_size == i) then
      state.card_size = i
      core.set_setting('card_size', tostring(i))
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
    T('fzf: всё — имя, треки, регионы, отчёты… ( / )'), state.filter_text)
  if changed then state.filter_text = val end

  -- все теги (из списка + встретившиеся в проектах) чипами справа от поиска:
  -- клик — фильтр (AND по нескольким), повторный клик — снять
  local seen, tags_all = {}, {}
  for _, e in ipairs(TAGS) do
    seen[e[1]] = true; tags_all[#tags_all + 1] = e[1]
  end
  for _, card in pairs(state.index.projects) do
    for _, t in ipairs(all_tags(card, core.card_meta(card))) do
      if not seen[t] then seen[t] = true; tags_all[#tags_all + 1] = t end
    end
  end
  for _, t in ipairs(tags_all) do
    local label = '#' .. t
    local active = state.filter_tags[t]
    ImGui.SameLine(ctx)
    if ImGui.CalcTextSize(ctx, label) + 12 > ImGui.GetContentRegionAvail(ctx) then
      ImGui.NewLine(ctx)
    end
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, active and tag_color(t) or 0x777777FF)
    if ImGui.SmallButton(ctx, label .. '###ftag' .. t) then
      state.filter_tags[t] = not active or nil
    end
    ImGui.PopStyleColor(ctx)
  end
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
    -- каскад: инпут → карточка → выборка → фокус → закрыть окно
    if state.tag_add_path or state.dl_path or state.ren_path then
      state.tag_add_path, state.dl_path, state.ren_path = nil, nil, nil
    elseif state.expanded then
      state.expanded = nil
    elseif #state.sel > 0 then
      state.sel = {}
    elseif state.focus > 0 or state.kb_col > 0 then
      state.focus = 0
      state.kb_col, state.kb_row = 0, 0
    else
      state.quit = true
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
      batch_step() -- очередь «превью всем»: один проект за кадр
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
  if open and not state.quit then
    reaper.defer(loop)
  else
    preview_stop() -- не оставлять играющий плеер после закрытия окна
  end
end

reaper.defer(loop)
