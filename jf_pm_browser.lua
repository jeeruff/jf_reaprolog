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
-- Cmd/Ctrl+Z — отмена; f — vim-хинты (буквы — фокус, Shift+метка — выделить
-- и остаться, Esc — выход); Ctrl/Cmd+1..5 — лупы активного превью.
-- Консоль — внизу окна: журнал, прогрессы, мини-bash команды.

local VERSION = '1.0'

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
  ['нет айтемов'] = 'no items',
  ['нет аудио в папке проекта'] = 'no audio in project folder',
  ['аудиофайлов: '] = 'audio files: ',
  ['пустые'] = 'empty',
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
  ['Демо отрендерено'] = 'Demo rendered',
  ['открыт'] = 'opened',
  ['сохранён'] = 'saved',
  ['консоль'] = 'console',
  ['цепочка'] = 'chain',
  ['найти превью'] = 'find previews',
  ['нет такого лупа'] = 'no such loop', ['лупов: %d'] = 'loops: %d',
  ['повтор'] = 'repeat', ['в проект'] = 'to project',
  ['питч, полутоны · двойной клик — ввод'] =
    'pitch, semitones · double click to type',
  ['анализ: тональность и BPM (по wav-превью)'] =
    'analyze key and BPM (from wav preview)',
  ['Анализ готов: %d'] = 'Analysis done: %d',
  ['(нужен wav-превью)'] = '(wav preview required)',
  ['анализ %d/%d'] = 'analysis %d/%d',
  ['мастер-BPM'] = 'master BPM',
  ['плейлист'] = 'playlist', ['выборка'] = 'selection',
  ['теги'] = 'tags', ['играет'] = 'playing', ['тишина'] = 'silence',
  ['дубли'] = 'dups', ['корзина'] = 'trash',
  ['в корзину: %s · %d дней до удаления'] =
    'to trash: %s · %d days before deletion',
  ['в корзину: %d · %d дней до удаления'] =
    'to trash: %d · %d days before deletion',
  ['в корзину: '] = 'to trash: ', ['в корзину: %d'] = 'to trash: %d',
  ['возвращено из корзины: '] = 'restored from trash: ',
  ['в корзине · %d дней до удаления · × — вернуть'] =
    'in trash · %d days before deletion · × to restore',
  ['вернуть все'] = 'restore all',
  ['удалить просроченные'] = 'purge expired',
  ['корзина очищена — всё возвращено'] = 'trash emptied — all restored',
  ['корзина: удалено %d просроченных'] = 'trash: %d expired purged',
  ['в корзине нет просроченных'] = 'no expired items in trash',
  ['в корзине: %d'] = 'in trash: %d', ['возвращено: %d'] = 'restored: %d',
  ['побайтная копия — можно удалять'] = 'byte-identical copy — safe to delete',
  ['версия того же проекта'] = 'version of the same project',
  ['групп: %d · побайтных копий: %d · версий: %d'] =
    'groups: %d · byte copies: %d · versions: %d',
  ['проекты с похожими именами (версии, копии)'] =
    'projects with similar names (versions, copies)',
  ['удачные тейки: %s'] = 'good takes: %s',
  ['подсказка по содержимому · клик — принять'] =
    'guess from content · click to accept',
  ['групп дублей: %d'] = 'duplicate groups: %d',
  ['фильтр категории снят'] = 'category filter off',
  ['классов проставлено: %d'] = 'classes set: %d',
  ['собрать #todo из регионов и заметок'] =
    'collect #todo from regions and notes',
  ['#todo: %d проектов'] = '#todo: %d projects',
  ['сохранить'] = 'save', ['TODO сохранён'] = 'TODO saved',
  ['собранное'] = 'collected',
  ['очистить плейлист'] = 'clear playlist',
  ['играть по очереди'] = 'play in sequence',
  ['стартовать все одновременно'] = 'start all at once',
  ['sync play: %d'] = 'sync play: %d',
  ['перетащи сюда карточки'] = 'drag cards here',
  ['в плейлист: '] = 'to playlist: ',
  ['стоп всех превью (глобальный)'] = 'stop all previews (global)',
  ['мастер тональности (scale sync)'] = 'key master (scale sync)',
  ['слейв: подстроить тональность под мастера'] =
    'slave: pitch this clip to the master key',
  ['это мастер — подстраивай другие клипы'] =
    'this is the master — tune the other clips',
  ['нет мастера или его тональности (M + analyze)'] =
    'no master or its key (press M + analyze)',
  ['у клипа нет тональности — жми analyze'] =
    'clip has no key — press analyze',
  ['подгонять темп играющих под мастер-BPM (питч сохраняется)'] =
    'match playing previews to master BPM (pitch preserved)',
  ['в плейлисте нечего экспортировать'] = 'nothing to export in playlist',
  ['обновить превью выделенных; нет файла — Spotlight по всему диску'] =
    'refresh previews of selected; if missing — Spotlight search disk-wide',
  ['Поиск превью: найдено %d из %d'] = 'Preview search: found %d of %d',
  ['поиск %d/%d'] = 'search %d/%d',
  ['плеер: '] = 'player: ', ['луп'] = 'loop',
  ['снэп'] = 'snap', [' (нет bpm)'] = ' (no bpm)',
  ['…ещё %d выбрано'] = '…%d more selected',
  ['луп %s: %s–%s'] = 'loop %s: %s–%s',
  ['собрать из лупов'] = 'build from loops',
  ['у выбранных нет лупов (плеер → драг по волне → + луп)'] =
    'selection has no loops (player → drag on wave → + loop)',
  ['новый проект: каждый луп — сабпроджект-айтем, порядок = выборка'] =
    'new project: each loop becomes a subproject item, order = selection',
  ['играть выбранные по очереди'] = 'play selected in sequence',
  ['развернуть'] = 'expand',
  ['нет превью'] = 'no preview',
  ['Rescan остановлен'] = 'Rescan stopped',
  ['Rescan: %d путей, фоном'] = 'Rescan: %d paths, in background',
  ['Rescan: %d проектов за %.1f c'] = 'Rescan: %d projects in %.1f s',
  ['команда… help — список, && — цепочка'] =
    'command… help — list, && — chain',
  ['превью %d/%d'] = 'preview %d/%d',
  ['всего: %d'] = 'total: %d', ['совпадений: %d'] = 'matches: %d',
  ['фильтр: «%s», карточек: %d'] = 'filter: "%s", cards: %d',
  ['карточек: %d, выбрано: %d'] = 'cards: %d, selected: %d',
  ['выборка очищена'] = 'selection cleared',
  ['в выборке: %d'] = 'selected: %d',
  ['фильтры и выборка сброшены'] = 'filters and selection cleared',
  ['не найдено'] = 'not found', ['открываю: '] = 'opening: ',
  ['выборка пуста (sel <pat>)'] = 'selection is empty (sel <pat>)',
  ['нет класса: '] = 'no such class: ',
  ['класс «%s»: %d проектов'] = 'class "%s": %d projects',
  ['тег: '] = 'tag: ', ['тег снят: '] = 'tag removed: ',
  ['нечего рендерить'] = 'nothing to render',
  ['превью-батч: %d'] = 'preview batch: %d',
  ['фильтр DAW: %s, карточек: %d'] = 'DAW filter: %s, cards: %d',
  ['все'] = 'all', ['сортировка: '] = 'sort: ',
  ['нет команды: '] = 'no such command: ',
  ['только для REAPER-проектов'] = 'REAPER projects only',
  ['двойной клик — открыть в этой программе'] =
    'double click — open in its app',
  ['открыть в '] = 'open in ',
  ['рендер'] = 'render', ['дедлайн'] = 'deadline',
  ['переименование'] = 'rename',
  ['merge: в выборке проект другой DAW — убери его'] =
    'merge: selection contains a foreign DAW project — remove it',
  ['открыть проект'] = 'open project',
  ['журнал'] = 'log', ['отменить'] = 'undo',
  ['Отменять нечего'] = 'Nothing to undo', ['Отменено: '] = 'Undone: ',
  ['класс «%s» → %s'] = 'class "%s" → %s',
  ['закреп «%s»'] = 'pin "%s"',
  ['закреплён «%s»'] = 'pinned "%s"', ['откреплён «%s»'] = 'unpinned "%s"',
  ['тег #%s на «%s»'] = 'tag #%s on "%s"',
  ['в Корзину: '] = 'to Trash: ',
  ['вернуть можно из Корзины Finder'] = 'restore from Finder Trash',
  ['открыть бэкап в новой вкладке'] = 'open backup in a new tab',
  ['восстановить проект из этого бэкапа…'] = 'restore project from this backup…',
  ['Открыт бэкап: '] = 'Backup opened: ',
  ['Бэкап не найден: '] = 'Backup not found: ',
  ['Восстановить проект из бэкапа?'] = 'Restore project from backup?',
  ['Текущий .rpp сохранится рядом как _before-restore.rpp'] =
    'The current .rpp will be kept as _before-restore.rpp',
  ['Восстановлено из: '] = 'Restored from: ',
  ['Восстановление: не могу записать .rpp'] = 'Restore: cannot write .rpp',
  ['восстановление бэкапа'] = 'backup restore',
  ['Открыт: '] = 'Opened: ',
  ['Подсказки кнопок:'] = 'Button tooltips:',
  ['вкл'] = 'on', ['выкл'] = 'off',
  ['отрендерить аудио-превью'] = 'render audio preview',
  ['отрендерить полное демо (весь проект)'] = 'render full demo (whole project)',
  ['Починить легаси-превью'] = 'Fix legacy previews',
  ['Легаси-превью: переименовано %d, общих на папку %d (батч дорендерит)'] =
    'Legacy previews: %d renamed, %d shared per folder (batch will re-render)',
  ['на расслоение'] = 'to harvest',
  ['На расслоение: %d'] = 'To harvest: %d',
  ['Пропавшие файлы (%d):'] = 'Missing files (%d):',
  ['Рендерить всё равно? (REAPER спросит про поиск файлов)'] =
    'Render anyway? (REAPER will ask to search for files)',
  [' · пропущено (нет файлов): %d'] = ' · skipped (missing media): %d',
  [' · тишина −%d c'] = ' · silence −%d s',
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
  card_size = tonumber(core.get_setting('card_size')) or 2, -- 1 S / 2 M / 3 L
  peak_style = tonumber(core.get_setting('peak_style')) or 0,   -- 0 волна / 1 спектр
  btn_tips = core.get_setting('btn_tips') ~= '0',               -- подсказки кнопок
  preview_vol = tonumber(core.get_setting('preview_vol')) or 1.0,
  loop_snap = core.get_setting('loop_snap') ~= '0', -- снэп лупов к битам
  master_bpm = tonumber(core.get_setting('master_bpm')) or 120,
  bpm_sync = false,         -- подгонять rate играющих под мастер-BPM
  view = 0,                 -- 0 сетка, 1 таймлайн, 2 календарь, 3 канбан
  filter_status = 0,        -- 0 активные, 1 все, 2 без отчёта, 3.. статусы
  filter_daw = nil,         -- nil все | 'reaper' | 'ableton' | …
  filter_text = '',         -- fzf: имя, теги, треки
  sel = {},                 -- упорядоченный список путей — порядок = порядок merge
  basket = {},              -- корзина регионов: {path, region} для сборки проекта
  playq = {},               -- плейлист: пути проектов (drag&drop, порядок)
  show_playq = false,       -- панель плейлиста открыта
  recent = core.recent_projects(), -- порядок открытия из reaper.ini
  log = {},                 -- консоль: последние действия (новые сверху)
  con_text = '',            -- ввод консоли
  con_hist = {},            -- история команд
  con_focus = false,
  undo = {},                -- стек отмены: {label, fn}
  kb_col = 0, kb_row = 0,   -- фокус в канбане
  sort_mode = 1,            -- 1 дата, 2 открыт, 3 сохранён (с бэкапами),
                            -- 4 статус, 5 длительность, 6 имя, 7 размер, 8 bpm
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
  filter_empty = false,
  filter_dups = false,      -- только вероятные дубли
  filter_trash = false,     -- показывать корзину вместо каталога
  filter_cat = nil,         -- авто-категория: тест/семпл/скетч/джем/аранжировка     -- показывать только пустышки (∅)
}

local STATUS_ORDER = {}
for i, s in ipairs(core.STATUSES) do STATUS_ORDER[s] = i end

local SORT_CHIPS = { 'дата', 'открыт', 'сохранён', 'статус', 'длительность',
                     'имя', 'размер', 'bpm', 'daw' }
-- естественное направление: true = по убыванию (новое/большое сверху)
local SORT_DESC_NATURAL = { true, true, true, false, true, false, true, false, false }
local VIEW_CHIPS = { 'сетка', 'таймлайн', 'календарь', 'канбан' }

-- лейблы выпадашки классов: «—» + core.STATUSES (исключение из правила
-- «без выпадашек» — по просьбе владельца); кэш на язык
local CLASS_LABELS_CACHE = {}
local function class_labels()
  local l = CLASS_LABELS_CACHE[LANG]
  if not l then
    local names = {}
    for i, s in ipairs(core.STATUSES) do names[i] = status_label(s) end
    names[#names + 1] = T('удалить…') -- действие, не класс
    l = '—\0' .. table.concat(names, '\0') .. '\0'
    CLASS_LABELS_CACHE[LANG] = l
  end
  return l
end

-- размеры карточек в сетке: ширина, высота, тамбнейл, макс. символов имени
-- размеры: S — микро-строка (логотип+волна, play по ховеру логотипа),
-- M — горизонтальный клип, L — обычная карточка.
-- Режима «все развёрнуты» больше нет: 2000 развёрнутых карточек без
-- виртуализации подвесили REAPER.
local CARD_SIZES = {
  { label = 'S', w = 240, h = 32, thumb = 22, name = 16, micro = true },
  { label = 'M', w = 280, h = 96, thumb = 56, name = 18, mini = true },
  -- L: высота ровно под контент (шапка+класс+мета+теги+волна+кнопки),
  -- без пустой середины — раньше было 198 и треть карточки пустовала
  { label = 'L', w = 340, h = 150, thumb = 56, name = 20 },
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

-- '[160]' в имени → 160 BPM; огибающая темпа → span '90-160 BPM'
local function fmt_bpm(card)
  local function n(x) return math.floor(x + 0.5) end
  local tag = core.name_bpm(card.name)
  local lo, hi = card.bpm_min, card.bpm_max
  if lo and hi and n(hi) - n(lo) >= 1 then
    return n(lo) .. '-' .. n(hi) .. ' BPM'
  end
  local b = tag or card.tempo
  if not b then return nil end
  return n(b) .. ' BPM' .. (tag and card.tempo and n(tag) ~= n(card.tempo)
    and (' (rpp ' .. n(card.tempo) .. ')') or '')
end

local function fmt_keys(card)
  local k = card.keys
  if not k or #k == 0 then return nil end
  return table.concat(k, ' ', 1, math.min(#k, 3))
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
-- meta-кэш: card_meta() парсит todos/ml-поля — не считать 2000 раз за кадр
local meta_cache = {}
-- поколение данных: любой bump сбрасывает собранный список и агрегаты
local data_gen = 0
local function bump_gen()
  data_gen = data_gen + 1
end
-- Отложенная запись индекса: 2000-карточный JSON не пишем на каждый клик.
-- Любое изменение данных проходит здесь же: сброс меты и поколения.
local function save_index_soon()
  state.index_dirty = reaper.time_precise()
  meta_cache = {}
  bump_gen()
end

local function flush_index(force)
  if state.index_dirty and (force
      or reaper.time_precise() - state.index_dirty > 1.5) then
    core.save_index(state.index) -- единственное место настоящей записи
    state.index_dirty = nil
  end
end

local function cached_meta(card)
  local m = meta_cache[card.path]
  if not m then
    m = core.card_meta(card)
    meta_cache[card.path] = m
  end
  return m
end
local dir_count_cache = {} -- dir -> число .rpp (для легаси-превью)
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
      card.daw or 'reaper',
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

-- последнее сохранение: сам .rpp либо свежайший бэкап
local function last_save(card)
  local t = card.mtime or 0
  for _, bk in ipairs(card.backups or {}) do
    if (bk.mtime or 0) > t then t = bk.mtime end
  end
  return t
end

local collect_cache = { key = nil, gen = -1, cards = nil }

local function collect_cards()
  -- группы дублей — по поколению данных (дорого, но редко)
  if state.filter_dups and state.dup_gen ~= data_gen then
    -- проверяем содержимым: в фильтр попадают только подтверждённые
    -- копии и версии (и их «оригинал»), похожие имена отсеиваются
    local groups = core.duplicate_groups(state.index.projects)
    local marks = {}
    for _, list in pairs(groups) do
      local r = core.classify_group(list)
      if #r.copies > 0 or #r.versions > 0 then
        marks[r.newest.path] = 'newest'
        for _, c in ipairs(r.copies) do marks[c.path] = 'copy' end
        for _, c in ipairs(r.versions) do marks[c.path] = 'version' end
      end
    end
    state.dup_marks, state.dup_gen = marks, data_gen
  end
  -- ключ пересборки: все входы, влияющие на состав и порядок; плюс
  -- data_gen — любое изменение данных индекса
  local tags_key = {}
  for t in pairs(state.filter_tags) do tags_key[#tags_key + 1] = t end
  table.sort(tags_key)
  local ckey = table.concat({
    state.filter_status, state.filter_text, state.filter_daw or '',
    state.filter_empty and 1 or 0, state.filter_dups and 1 or 0,
    state.filter_trash and 1 or 0,
    state.filter_cat or '', state.sort_mode,
    state.sort_rev and 1 or 0, table.concat(tags_key, ','), LANG,
  }, '|')
  if collect_cache.gen == data_gen and collect_cache.key == ckey then
    return collect_cache.cards
  end
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
    local meta = cached_meta(card)
    local ok = true
    local f = state.filter_status
    if f == 0 then
      ok = meta.status ~= 'покой'
    elseif f == 2 then
      ok = card.needs_report or meta.report_ts == 0
    elseif f >= 3 then
      ok = meta.status == core.STATUSES[f - 2]
    end
    if ok and state.filter_empty then ok = core.is_empty_project(card) end
    if ok and state.filter_daw then
      ok = (card.daw or 'reaper') == state.filter_daw
    end
    if ok and state.filter_cat then
      ok = core.auto_category(card) == state.filter_cat
    end
    if ok and state.filter_dups then
      ok = (state.dup_marks or {})[card.path] ~= nil
    end
    -- корзина: скрыта везде, кроме собственного фильтра
    if ok then
      if state.filter_trash then
        ok = card.trashed ~= nil
      else
        ok = card.trashed == nil
      end
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
      -- дата открытия: recent-список REAPER точнее (ранг 1 — последний
      -- открытый), для остальных — atime файла
      local ra = state.recent[a.card.path:lower()]
      local rb = state.recent[b.card.path:lower()]
      if ra and rb then
        if ra ~= rb then return ra < rb end
      elseif ra or rb then
        return ra ~= nil -- бывшие в recent новее любого atime
      else
        local aa, ab = a.card.atime or 0, b.card.atime or 0
        if aa ~= ab then return aa > ab end
      end
    elseif m == 3 then
      -- последнее сохранение с учётом бэкапов: свежий .rpp-bak значит,
      -- что проект трогали, даже если сам .rpp старше
      local sa = last_save(a.card)
      local sb = last_save(b.card)
      if sa ~= sb then return sa > sb end
    elseif m == 4 then
      local oa = STATUS_ORDER[a.meta.status] or 99
      local ob = STATUS_ORDER[b.meta.status] or 99
      if oa ~= ob then return oa < ob end
    elseif m == 5 then
      if (a.card.duration or 0) ~= (b.card.duration or 0) then
        return (a.card.duration or 0) > (b.card.duration or 0)
      end
    elseif m == 6 then
      if a.card.name:lower() ~= b.card.name:lower() then
        return a.card.name:lower() < b.card.name:lower()
      end
    elseif m == 7 then
      local sa = a.card.dir_size or a.card.size or 0
      local sb = b.card.dir_size or b.card.size or 0
      if sa ~= sb then return sa > sb end
    elseif m == 8 then
      local ba, bb = core.card_bpm(a.card), core.card_bpm(b.card)
      if ba ~= bb and ba and bb then return ba < bb end
    elseif m == 9 then
      -- по DAW: REAPER первым (пустой ключ), дальше алфавит; внутри — дата
      local da = a.card.daw or ''
      local db = b.card.daw or ''
      if da ~= db then return da < db end
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
    if m == 8 then
      -- проекты без темпа — всегда в конец, реверс их не поднимает
      local ha = core.card_bpm(a.card) and 1 or 0
      local hb = core.card_bpm(b.card) and 1 or 0
      if ha ~= hb then return ha > hb end
    end
    if state.sort_rev then return less(b, a) end
    return less(a, b)
  end)
  collect_cache.key, collect_cache.gen, collect_cache.cards =
    ckey, data_gen, cards
  return cards
end

-- ---------------------------------------------------------------------------
-- Консоль действий и отмена. В журнал (5 строк справа сверху) пишется всё
-- заметное; в undo-стек — только обратимое (класс, теги, закреп, дедлайн).
-- Удаление в Корзину отменяется через Finder («Put Back» руками) — в undo
-- не кладём, но в консоли отмечаем.

local LOG_MAX = 200
local function logf(kind, fmt, ...)
  local msg = select('#', ...) > 0 and string.format(fmt, ...) or fmt
  table.insert(state.log, 1, { kind = kind, msg = msg, t = os.time() })
  while #state.log > LOG_MAX do state.log[#state.log] = nil end
  state.log_scroll = true
  state.status_msg = msg
end

local UNDO_MAX = 30
local function push_undo(label, fn)
  table.insert(state.undo, 1, { label = label, fn = fn })
  while #state.undo > UNDO_MAX do state.undo[#state.undo] = nil end
end

local function do_undo()
  local u = table.remove(state.undo, 1)
  if not u then
    logf('warn', T('Отменять нечего'))
    return
  end
  u.fn()
  logf('undo', T('Отменено: ') .. u.label)
end

-- Rescan — фоновый: скан дерева быстрый (нативные Enumerate), а карточки
-- строятся порциями по ~30 мс на кадр defer-цикла. UI живёт на старом
-- индексе, пока новый собирается; в конце — атомарная подмена.
local function rescan()
  if state.rescan then
    state.rescan = nil
    logf('warn', T('Rescan остановлен'))
    return
  end
  local paths = core.get_scan_paths()
  if #paths == 0 then
    state.status_msg = 'Укажи директории проектов (кнопка «настройки»)'
    state.show_settings = true
    return
  end
  for _, p in ipairs(paths) do
    local ok = reaper.EnumerateFiles(p, 0) ~= nil
      or reaper.EnumerateSubdirectories(p, 0) ~= nil
    logf(ok and 'act' or 'warn', (ok and '✓ ' or '✗ ') .. p)
  end
  local t0 = reaper.time_precise()
  local rpp, foreign = core.scan_projects(paths)
  local queue = {}
  for _, p in ipairs(rpp) do queue[#queue + 1] = { path = p } end
  for _, f in ipairs(foreign) do
    queue[#queue + 1] = { path = f.path, ext = f.ext }
  end
  state.rescan = {
    queue = queue, i = 0, total = #queue, t0 = t0,
    idx = { version = 1, updated = 0, projects = {} },
    dir_sizes = {}, dir_audio = {},
  }
  logf('act', string.format(T('Rescan: %d путей, фоном'), #queue))
end

local function rescan_step()
  local rs = state.rescan
  if not rs then return end
  local frame_end = reaper.time_precise() + 0.03
  local old = state.index.projects
  while rs.i < rs.total and reaper.time_precise() < frame_end do
    rs.i = rs.i + 1
    local it = rs.queue[rs.i]
    local card
    if it.ext then
      card = core.build_foreign_card(it.path, it.ext, old[it.path], rs.dir_sizes)
    else
      card = core.build_card(it.path, old[it.path], rs.dir_sizes, rs.dir_audio)
    end
    if card then rs.idx.projects[it.path] = card end
  end
  if rs.i >= rs.total then
    state.index = rs.idx
    save_index_soon()
    search_cache, audio_cache, wave_cache, daw_cache = {}, {}, {}, {}
    dir_count_cache = {}
    state.recent = core.recent_projects()
    logf('ok', string.format(T('Rescan: %d проектов за %.1f c'), rs.total,
      reaper.time_precise() - rs.t0))
    state.rescan = nil
  end
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
  if not path:lower():match('%.rpp$') then
    -- проект чужой DAW: открыть приложением по расширению (как jf_dawsync)
    if reaper.CF_ShellExecute then
      reaper.CF_ShellExecute(path)
    else
      reaper.ExecProcess('/usr/bin/open "' .. path .. '"', -1)
    end
    return
  end
  reaper.Main_OnCommand(40859, 0) -- New project tab
  reaper.Main_openProject(path)
end

-- Статус из канбана: живёт в индексе, пока проект не открыт и отчёт
-- не перезаписал STATUS в .rpp (см. build_card).
local function set_status(card, status, silent)
  local prev = card.status_over
  local prev_base = card.status_over_base
  if status == '' then
    card.status_over, card.status_over_base = nil, nil
  else
    card.status_over = status
    card.status_over_base = (card.ext or {}).STATUS or ''
  end
  search_cache[card.path] = nil -- статус входит в поисковую строку
  save_index_soon()
  if not silent then
    local path = card.path
    push_undo(string.format(T('класс «%s» → %s'), card.name,
      status ~= '' and status or '—'), function()
      local c = state.index.projects[path] or card
      c.status_over, c.status_over_base = prev, prev_base
      search_cache[path] = nil
      save_index_soon()
    end)
    logf('act', string.format(T('класс «%s» → %s'), card.name,
      status ~= '' and status or '—'))
  end
end

local function toggle_pin(card)
  local prev = card.pinned
  card.pinned = not card.pinned or nil
  save_index_soon()
  local path = card.path
  push_undo(string.format(T('закреп «%s»'), card.name), function()
    local c = state.index.projects[path] or card
    c.pinned = prev
    save_index_soon()
  end)
  logf('act', string.format(card.pinned and T('закреплён «%s»')
    or T('откреплён «%s»'), card.name))
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
-- Физическое удаление в Корзину macOS (Finder «Положить обратно» работает).
-- Зовётся из очистки просроченной корзины и по «удалить навсегда».
local function purge_project(card, whole_dir)
  local dir = card.path:match('^(.*)[/\\]')
  local roots = {}
  for _, p in ipairs(core.get_scan_paths()) do roots[(p:gsub('/+$', ''))] = true end
  local dir_ok = dir and not roots[dir]
  local target = (whole_dir and dir_ok) and dir or card.path

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
  save_index_soon()
  logf('del', T('в Корзину: ') .. target ..
    ' — ' .. T('вернуть можно из Корзины Finder'))
end

-- Виртуальная корзина: файлы не двигаются, карточка помечается временем.
-- Скрыта из каталога, восстанавливается кликом, через месяц уезжает
-- в Корзину macOS (см. trash_sweep).
local function delete_project(card)
  if card.trashed then
    card.trashed = nil
    save_index_soon()
    logf('undo', T('возвращено из корзины: ') .. card.name)
    return
  end
  card.trashed = os.time()
  save_index_soon()
  if state.expanded == card.path then state.expanded = nil end
  local i = sel_index(card.path)
  if i then table.remove(state.sel, i) end
  local path = card.path
  push_undo(T('в корзину: ') .. card.name, function()
    local c = state.index.projects[path] or card
    c.trashed = nil
    save_index_soon()
  end)
  logf('del', string.format(T('в корзину: %s · %d дней до удаления'),
    card.name, core.TRASH_DAYS))
end

-- Просроченные (>30 дней) — физически в Корзину macOS. Раз в сессию.
local function trash_sweep(force)
  local due = {}
  for _, card in pairs(state.index.projects) do
    if core.trash_expired(card) then due[#due + 1] = card end
  end
  if #due == 0 then
    if force then logf('ok', T('в корзине нет просроченных')) end
    return
  end
  for _, card in ipairs(due) do
    purge_project(card, false) -- только .rpp: папку не трогаем без спроса
  end
  logf('del', string.format(T('корзина: удалено %d просроченных'), #due))
end

-- Массовое удаление выделенных — в виртуальную корзину
local function delete_selected()
  local n = #state.sel
  if n == 0 then return end
  local marked = {}
  for _, path in ipairs({table.unpack(state.sel)}) do
    local card = state.index.projects[path]
    if card and not card.trashed then
      card.trashed = os.time()
      marked[#marked + 1] = path
    end
  end
  state.sel = {}
  save_index_soon()
  push_undo(string.format(T('в корзину: %d'), #marked), function()
    for _, p in ipairs(marked) do
      local c = state.index.projects[p]
      if c then c.trashed = nil end
    end
    save_index_soon()
  end)
  logf('del', string.format(T('в корзину: %d · %d дней до удаления'),
    #marked, core.TRASH_DAYS))
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
  save_index_soon()
end

-- Merge: выделенные соединяются последовательно в порядке выделения.
local function merge_selected()
  for _, p in ipairs(state.sel) do
    local cc = state.index.projects[p]
    if cc and cc.daw then
      logf('warn', T('merge: в выборке проект другой DAW — убери его'))
      return
    end
  end
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
    save_index_soon()
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
  for _, p in ipairs(state.sel) do
    local cc = state.index.projects[p]
    if cc and cc.daw then
      logf('warn', T('merge: в выборке проект другой DAW — убери его'))
      return
    end
  end
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

-- Операции, знающие формат .rpp, для чужих DAW недоступны
local function reaper_only(card, what)
  if card.daw then
    logf('warn', (what or '') .. ': ' .. T('только для REAPER-проектов'))
    return true
  end
  return false
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
  save_index_soon()
  search_cache[path], audio_cache[path], daw_cache[path] = nil, nil, nil
  dir_count_cache = {}
  return nc
end

-- Открыть бэкап: .rpp-bak REAPER открывает как обычный проект.
local function open_backup(card, bk)
  local dir = card.path:match('^(.*)[/\\]') or '.'
  local full = bk.dir and (bk.dir .. '/' .. bk.file) or (dir .. '/' .. bk.file)
  local f = io.open(full, 'rb')
  if not f then
    -- бэкап мог лежать в Backups/ — пробуем там
    full = dir .. '/Backups/' .. bk.file
    f = io.open(full, 'rb')
    if not f then
      state.status_msg = T('Бэкап не найден: ') .. bk.file
      return
    end
  end
  f:close()
  open_project(full)
  state.status_msg = T('Открыт бэкап: ') .. bk.file
end

-- Восстановить бэкап: текущий .rpp отходит в <имя>_before-restore.rpp,
-- бэкап копируется на его место. Проект не должен быть открыт.
local function restore_backup(card, bk)
  if project_is_open(card.path) then
    warn_open(card, T('восстановление бэкапа'))
    return
  end
  local dir = card.path:match('^(.*)[/\\]') or '.'
  local src = bk.dir and (bk.dir .. '/' .. bk.file) or (dir .. '/' .. bk.file)
  local sf = io.open(src, 'rb')
  if not sf then
    src = dir .. '/Backups/' .. bk.file
    sf = io.open(src, 'rb')
    if not sf then
      state.status_msg = T('Бэкап не найден: ') .. bk.file
      return
    end
  end
  local r = reaper.MB(
    T('Восстановить проект из бэкапа?') .. '\n\n' .. bk.file ..
    '\n\n' .. T('Текущий .rpp сохранится рядом как _before-restore.rpp'),
    'JF PM', 1)
  if r ~= 1 then sf:close() return end
  local data = sf:read('*a')
  sf:close()
  local keep = dir .. '/' .. card.name .. '_before-restore.rpp'
  os.remove(keep)
  local cf = io.open(card.path, 'rb')
  if cf then
    local cur = cf:read('*a')
    cf:close()
    local kf = io.open(keep, 'wb')
    if kf then kf:write(cur) kf:close() end
  end
  local out = io.open(card.path, 'wb')
  if not out then
    state.status_msg = T('Восстановление: не могу записать .rpp')
    return
  end
  out:write(data)
  out:close()
  refresh_card(card.path)
  state.status_msg = T('Восстановлено из: ') .. bk.file
end

-- Переименование: всё с префиксом имени + папка проекта (см. core).
local function rename_project(card, new_name)
  if reaper_only(card, T('переименование')) then return end
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
  save_index_soon()
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
  if reaper_only(card, 'todo') then return end
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
  if reaper_only(card, T('дедлайн')) then return end
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
                    mp3 = true, ogg = true, m4a = true }

-- audio_cache: card.path -> путь к аудио | false (объявлен выше)
local function find_preview_audio(card)
  local hit = audio_cache[card.path]
  if hit ~= nil then return hit or nil end
  local dir = card.path:match('^(.*)[/\\]') or '.'
  -- сколько проектов в папке: легаси jf_preview.wav общий на папку —
  -- при нескольких .rpp он делил бы одно превью между проектами (баг
  -- «басс1/басс2 играют одно и то же»), поэтому принимаем его только
  -- для единственного проекта в папке
  local nproj = dir_count_cache[dir]
  if not nproj then
    nproj = 0
    for p in pairs(state.index.projects) do
      if (p:match('^(.*)[/\\]') or '.') == dir then nproj = nproj + 1 end
    end
    dir_count_cache[dir] = nproj
  end
  local cands = {}
  if card.preview_found then
    cands[#cands + 1] = card.preview_found -- найден Spotlight-поиском
  end
  cands[#cands + 1] = dir .. '/' .. card.name .. '_preview.wav'
  if card.daw then
    -- чужая DAW: экспорт обычно лежит рядом с проектом под тем же именем
    for _, e in ipairs({ 'wav', 'mp3', 'aiff', 'aif', 'flac', 'm4a', 'ogg' }) do
      cands[#cands + 1] = dir .. '/' .. card.name .. '.' .. e
    end
  end
  if nproj <= 1 then
    cands[#cands + 1] = dir .. '/jf_preview.wav'
  end
  cands[#cands + 1] = card.path .. '-PROX.wav'
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
  -- точных нет — фаззи: лучший аудиофайл папки, похожий на имя проекта
  -- («трек v3.wav» для «трек.rpp»); нормализуем до букв/цифр
  local function norm(s)
    return (s:lower():gsub('[%s%p_]+', ''))
  end
  local want = norm(card.name)
  if #want >= 3 then
    local best, best_score
    local i = 0
    while true do
      local fn = reaper.EnumerateFiles(dir, i)
      if not fn then break end
      local ext = fn:lower():match('%.([%w]+)$')
      if ext and AUDIO_EXT[ext] then
        local base = norm(fn:gsub('%.[%w]+$', ''))
        local score
        if base == want then score = 100
        elseif base:find(want, 1, true) then score = 80 - (#base - #want)
        elseif want:find(base, 1, true) and #base >= 4 then
          score = 60 - (#want - #base)
        end
        if score and (not best_score or score > best_score) then
          best, best_score = dir .. '/' .. fn, score
        end
      end
      i = i + 1
    end
    if best then
      audio_cache[card.path] = best
      return best
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

-- Плейбек через SWS CF_Preview. Несколько превью могут играть
-- одновременно (мини-плейлист выбранных — как сешн-грид Ableton);
-- playlist — последовательный режим: следующий стартует, когда кончился
-- текущий.
local players = {}   -- audio -> cfp
local playlist = nil -- { queue = {audio…}, i, started }

local function is_playing(audio)
  return players[audio] ~= nil
end

local function preview_stop(audio)
  if audio then
    local c = players[audio]
    if c then
      reaper.CF_Preview_Stop(c)
      players[audio] = nil
    end
  else
    for _, c in pairs(players) do reaper.CF_Preview_Stop(c) end
    players = {}
    playlist = nil
  end
end

local function preview_play(audio, keep_others)
  if not reaper.CF_CreatePreview then
    state.status_msg = 'Плеер: нужен SWS (CF_Preview)'
    return
  end
  if not keep_others then
    for a, c in pairs(players) do
      if a ~= audio then
        reaper.CF_Preview_Stop(c)
        players[a] = nil
      end
    end
  end
  -- один плеер на файл: повторный запуск переиспользует существующий
  -- (иначе старый cfp сиротел и играл до конца мимо любого стопа)
  local ex = players[audio]
  if ex then
    reaper.CF_Preview_SetValue(ex, 'D_POSITION', 0)
    return
  end
  local src = reaper.PCM_Source_CreateFromFile(audio)
  if not src then return end
  local cfp = reaper.CF_CreatePreview(src)
  reaper.PCM_Source_Destroy(src) -- CF_Preview держит свою копию
  reaper.CF_Preview_SetValue(cfp, 'D_VOLUME', state.preview_vol)
  reaper.CF_Preview_Play(cfp)
  players[audio] = cfp
end

local function preview_toggle(audio, keep_others)
  if is_playing(audio) then
    preview_stop(audio)
  else
    preview_play(audio, keep_others)
  end
end

local loop_bounds = {} -- audio -> {a, b} сек: активный луп-плейбек
local pitch_map = {}   -- card.path -> полутоны (перформанс-параметр, RAM)

-- bpm карточки: тег в имени > найденный анализом > TEMPO из .rpp
local function eff_bpm(card)
  return core.name_bpm(card.name) or card.bpm_detected or card.tempo
end

-- тональность карточки: анализ приоритетнее парсинга имён
local KEY_IDX = { A = 0, ['A#'] = 1, B = 2, C = 3, ['C#'] = 4, D = 5,
                  ['D#'] = 6, E = 7, F = 8, ['F#'] = 9, G = 10, ['G#'] = 11 }
local function card_key(card)
  return (card.keys_detected and card.keys_detected[1])
    or (card.keys and card.keys[1])
end
local function key_root(k)
  if not k then return nil end
  local root = k:match('^([A-G]#?)m?$')
  return root and KEY_IDX[root]
end

-- применить питч и BPM-синк к только что запущенному превью
local function apply_play_fx(card, audio)
  local c = players[audio]
  if not c then return end
  reaper.CF_Preview_SetValue(c, 'D_PITCH', pitch_map[card.path] or 0)
  if state.bpm_sync and state.master_bpm > 0 then
    local pb = eff_bpm(card)
    if pb and pb > 0 then
      reaper.CF_Preview_SetValue(c, 'B_PPITCH', 1) -- питч не плывёт
      reaper.CF_Preview_SetValue(c, 'D_PLAYRATE', state.master_bpm / pb)
    end
  end
end

-- каждый кадр: убрать доигравшие, вернуть луп на начало, продвинуть плейлист
local function players_step()
  for a, c in pairs(players) do
    local ok, st = reaper.CF_Preview_GetValue(c, 'B_PLAY')
    if ok and st == 0 then
      players[a] = nil
      loop_bounds[a] = nil
    end
  end
  for a, lb in pairs(loop_bounds) do
    local c = players[a]
    if not c then
      loop_bounds[a] = nil
    else
      local ok, pos = reaper.CF_Preview_GetValue(c, 'D_POSITION')
      if ok and pos >= lb.b then
        reaper.CF_Preview_SetValue(c, 'D_POSITION', lb.a)
      end
    end
  end
  if playlist then
    local cur = playlist.queue[playlist.i]
    local function start(el)
      preview_play(el.audio, true) -- поверх параллельных лупов
      if el.card then apply_play_fx(el.card, el.audio) end
      if players[el.audio] and el.a then
        reaper.CF_Preview_SetValue(players[el.audio], 'D_POSITION', el.a)
      end
    end
    local function advance()
      if playlist.i < #playlist.queue then
        playlist.i = playlist.i + 1
        start(playlist.queue[playlist.i])
      elseif playlist.rep then
        playlist.i = 1
        start(playlist.queue[1])
      else
        playlist = nil
      end
    end
    if not cur then
      playlist = nil
    elseif not playlist.started then
      playlist.started = true
      start(cur)
    elseif not players[cur.audio] then
      advance() -- элемент доиграл до конца файла
    elseif cur.b then
      local ok, pos = reaper.CF_Preview_GetValue(players[cur.audio],
        'D_POSITION')
      if ok and pos >= cur.b then
        preview_stop(cur.audio)
        advance()
      end
    end
  end
end

-- цвет спектрального пика: частота (нижние 15 бит) → hue от красного к синему
local function spec_color(spec)
  local freq = math.max(spec & 0x7FFF, 30)
  local h = math.min(math.log(freq / 60) / math.log(16000 / 60), 1)
  return hash_color(10 + h * 230, 0.6, 0.95)
end

-- полоска-плеер: клик — play/stop; вернуть true, если клик был по полоске
local function draw_wave_strip(card, width, height, multi)
  local audio = find_preview_audio(card)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + width, y0 + height,
    0x141414FF, 3)
  local clicked = false
  if not audio then
    ImGui.DrawList_AddText(dl, x0 + 6, y0 + height / 2 - 7, 0x5A5A5AFF,
      T('нет превью'))
    ImGui.Dummy(ctx, width, height)
    return false
  end
  local w = get_wave(audio)
  if w then
    local mid = y0 + height / 2
    local step = width / w.n
    local now_playing = is_playing(audio)
    for i = 1, w.n do
      local x = x0 + (i - 1) * step
      local col = w.spec and spec_color(w.spec[i])
        or (now_playing and 0xD9B96CFF or 0x8A8F93FF)
      local hi = math.min(math.max(w.max[i], 0), 1) * (height / 2 - 1)
      local lo = math.min(math.max(-w.min[i], 0), 1) * (height / 2 - 1)
      ImGui.DrawList_AddRectFilled(dl, x, mid - hi, x + math.max(step - 1, 1),
        mid + lo + 1, col)
    end
    if now_playing then
      local ok, pos = reaper.CF_Preview_GetValue(players[audio], 'D_POSITION')
      if ok and w.len > 0 then
        local px = x0 + math.min(pos / w.len, 1) * width
        ImGui.DrawList_AddLine(dl, px, y0, px, y0 + height, 0xFFFFFFDD, 1)
      end
    end
  else
    ImGui.DrawList_AddText(dl, x0 + 6, y0 + height / 2 - 7, 0x5A5A5AFF,
      T('пики не построились'))
  end
  ImGui.InvisibleButton(ctx, '###wave' .. card.path, width, height)
  local wmods = ImGui.GetKeyMods(ctx)
  local sel_mod = wmods & ImGui.Mod_Ctrl ~= 0 or wmods & ImGui.Mod_Super ~= 0
  -- клик — играть с места клика / сик; Cmd+клик — мимо плеера, карточке
  -- (выделение → карточка попадает в плейлист); правый клик — стоп
  if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left)
     and ImGui.IsItemHovered(ctx) then
    -- двойной клик по волне — открыть проект (как по карточке)
    open_project(card.path)
    clicked = true
  elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not sel_mod then
    local mx = ImGui.GetMousePos(ctx)
    local frac = math.min(math.max((mx - x0) / width, 0), 1)
    -- параллельно всегда: чужой луп в большом плеере не гасится
    if not is_playing(audio) then preview_play(audio, true) end
    if players[audio] and w and w.len > 0 then
      reaper.CF_Preview_SetValue(players[audio], 'D_POSITION', frac * w.len)
    end
    clicked = true
  end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
    preview_stop()
    clicked = true
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, is_playing(audio)
      and T('клик — сик · пкм — стоп')
      or (T('играть: ') .. (audio:match('([^/\\]+)$') or audio)
        .. '\n' .. T('клик — с места клика · пкм — стоп')))
  end
  return clicked
end

-- «Грамотный рендер»: открыть проект, отрендерить jf_preview.wav целиком,
-- вернуть рендер-настройки на место, сохранить, закрыть таб.
-- kind: 'preview' (лимит 5 мин, суффикс _preview) | 'demo' (весь проект,
-- суффикс _demo). Нормализация −18 LUFS и брикволл — в обоих случаях.
local function render_audio(card, kind)
  if reaper_only(card, T('рендер')) then return end
  if project_is_open(card.path) then
    warn_open(card, 'рендер превью')
    return
  end
  -- пропавшие медиа: открытие покажет модальный диалог REAPER — спросим
  if not state.batch then
    local missing = core.missing_media(card.path)
    if #missing > 0 then
      local r = reaper.MB(string.format(
        T('Пропавшие файлы (%d):') .. '\n%s\n\n' ..
        T('Рендерить всё равно? (REAPER спросит про поиск файлов)'),
        #missing, table.concat(missing, '\n', 1, math.min(#missing, 8))),
        'JF PM', 4)
      if r ~= 6 then return end
    end
  end
  local dir = card.path:match('^(.*)[/\\]') or '.'
  -- превью зовётся по имени проекта: у двух .rpp в одной папке — свои файлы
  local pv_name = card.name:gsub('%$', '')
    .. (kind == 'demo' and '_demo' or '_preview')
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
    norm = reaper.GetSetProjectInfo(proj, 'RENDER_NORMALIZE', 0, false),
    norm_t = reaper.GetSetProjectInfo(proj, 'RENDER_NORMALIZE_TARGET', 0, false),
    brick = reaper.GetSetProjectInfo(proj, 'RENDER_BRICKWALL', 0, false),
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
  -- демо рендерится целиком, превью — не длиннее 5 минут
  local PREVIEW_MAX = kind == 'demo' and math.huge or 300
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
  -- нормализация -18 LUFS-I + брикволл-лимит -0.5 dBTP («клипануть»);
  -- флаги: &1 норм. вкл (режим 0 = LUFS-I), &64 брикволл, &128 true peak —
  -- проверить биты на железе. Значения — линейные, не dB.
  reaper.GetSetProjectInfo(proj, 'RENDER_NORMALIZE', 1 | 64 | 128, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_NORMALIZE_TARGET', 10 ^ (-18 / 20), true)
  reaper.GetSetProjectInfo(proj, 'RENDER_BRICKWALL', 10 ^ (-0.5 / 20), true)
  reaper.Main_OnCommand(41824, 0) -- File: Render project, using the most recent render settings
  -- REAPER часто видит конец проекта сильно дальше звука (огибающие,
  -- маркеры) — отрезаем цифровую тишину в хвосте, оставляя секунду
  local trimmed, lead_cut, tail_cut = core.trim_wav_silence(pv_path, 0.5, 1.0)
  -- сэмпл-точная привязка лупов: сколько срезано с начала — на столько
  -- время превью отстаёт от времени проекта
  card.pv_offset = trimmed and lead_cut or 0
  if trimmed then
    bounds_note = bounds_note .. string.format(T(' · тишина −%d c'),
      math.floor(lead_cut + tail_cut + 0.5))
  end
  reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', old.file, true)
  reaper.GetSetProjectInfo_String(proj, 'RENDER_PATTERN', old.pat, true)
  reaper.GetSetProjectInfo_String(proj, 'RENDER_FORMAT', old.fmt, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_BOUNDSFLAG', old.bounds, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_SETTINGS', old.settings, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_STARTPOS', old.spos, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_ENDPOS', old.epos, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_NORMALIZE', old.norm, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_NORMALIZE_TARGET', old.norm_t, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_BRICKWALL', old.brick, true)
  reaper.Main_SaveProject(0, false)
  reaper.Main_OnCommand(40860, 0) -- Close current project tab
  restore_1x()
  restore_mtime()
  audio_cache[card.path] = nil
  for k in pairs(wave_cache) do
    if k:find(pv_path, 1, true) == 1 then wave_cache[k] = nil end
  end
  state.status_msg = (kind == 'demo' and T('Демо отрендерено')
    or T('Превью отрендерено')) .. bounds_note .. ': ' .. pv_path
end

-- ---------------------------------------------------------------------------
-- Анализ аудио превью: тональность и BPM. Чанками в defer — не виснем.
-- Тональность: хрома Гёрцелем по 36 нотам (A2..G#5) на окнах 4096@8кГц,
-- корреляция с профилями Крумхансла (24 ключа), топ-2.
-- BPM: RMS-огибающая (шаг 32 мс) → автокорреляция 60–180 BPM.

local KRUMHANSL_MAJ = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
                        2.52, 5.19, 2.39, 3.66, 2.29, 2.88 }
local KRUMHANSL_MIN = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
                        2.54, 4.75, 3.98, 2.69, 3.34, 3.17 }
local NOTE_NAMES = { 'A', 'A#', 'B', 'C', 'C#', 'D', 'D#', 'E', 'F',
                     'F#', 'G', 'G#' }

-- Разбор WAV → функция чтения кадра в моно [-1..1]; PCM 16/24/32 и float32
local function wav_open(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local data = f:read('*a')
  f:close()
  if data:sub(1, 4) ~= 'RIFF' or data:sub(9, 12) ~= 'WAVE' then return nil end
  local pos = 13
  local fmt, ch, srate, bits, doff, dsize
  while pos + 8 <= #data do
    local id = data:sub(pos, pos + 3)
    local sz = string.unpack('<I4', data, pos + 4)
    if id == 'fmt ' then
      fmt = string.unpack('<I2', data, pos + 8)
      ch = string.unpack('<I2', data, pos + 10)
      srate = string.unpack('<I4', data, pos + 12)
      bits = string.unpack('<I2', data, pos + 22)
    elseif id == 'data' then
      doff, dsize = pos + 8, sz
      break
    end
    pos = pos + 8 + sz + (sz % 2)
  end
  if not (fmt and doff) or (fmt ~= 1 and fmt ~= 3) then return nil end
  local bytes = bits // 8
  local frame = bytes * ch
  local nframes = dsize // frame
  local function sample(i) -- i: 0-based кадр → моно
    local off = doff + i * frame
    local s = 0
    if fmt == 3 then
      s = string.unpack('<f', data, off)
    elseif bits == 16 then
      s = string.unpack('<i2', data, off) / 32768
    elseif bits == 24 then
      local b1, b2, b3 = data:byte(off, off + 2)
      local v = b1 + b2 * 256 + b3 * 65536
      if v >= 8388608 then v = v - 16777216 end
      s = v / 8388608
    elseif bits == 32 then
      s = string.unpack('<i4', data, off) / 2147483648
    end
    return s
  end
  return { sample = sample, srate = srate, nframes = nframes }
end

-- состояние анализа одной карточки
local function an_begin(card, audio)
  local wav = wav_open(audio)
  if not wav then return nil end
  local step = math.max(1, wav.srate // 8000) -- децимация до ~8кГц
  local sr = wav.srate / step
  local WIN = 4096
  local total = math.min(wav.nframes // step, math.floor(sr * 90)) -- ≤90 c
  -- частоты 36 нот A2..G#5 (110..~830 Гц) → коэффициенты Гёрцеля
  local coef = {}
  for n = 0, 35 do
    local freq = 110 * 2 ^ (n / 12)
    coef[n] = 2 * math.cos(2 * math.pi * freq / sr)
  end
  return {
    card = card, audio = audio, wav = wav, step = step, sr = sr,
    WIN = WIN, total = total, pos = 0, coef = coef,
    chroma = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    env = {}, -- RMS каждые 256 децимированных сэмплов (32 мс)
  }
end

local function an_window(an)
  -- одно окно: Гёрцель 36 нот + под-RMS в огибающую
  local WIN = an.WIN
  local n0 = an.pos
  if n0 + WIN > an.total then return false end
  local s = {}
  local wav, step = an.wav, an.step
  for i = 0, WIN - 1 do
    s[i] = wav.sample((n0 + i) * step)
  end
  for note = 0, 35 do
    local c = an.coef[note]
    local q0, q1, q2 = 0, 0, 0
    for i = 0, WIN - 1 do
      q0 = c * q1 - q2 + s[i]
      q2 = q1
      q1 = q0
    end
    local power = q1 * q1 + q2 * q2 - c * q1 * q2
    local pc = (note % 12) + 1
    an.chroma[pc] = an.chroma[pc] + math.sqrt(math.max(power, 0))
  end
  for sub = 0, WIN // 256 - 1 do
    local acc = 0
    for i = sub * 256, sub * 256 + 255 do acc = acc + s[i] * s[i] end
    an.env[#an.env + 1] = math.sqrt(acc / 256)
  end
  an.pos = n0 + WIN
  return true
end

local function an_finish(an)
  -- тональности: корреляция хромы с 24 профилями
  local function corr(profile, rot)
    local acc = 0
    for i = 1, 12 do
      acc = acc + profile[i] * an.chroma[((i - 1 + rot) % 12) + 1]
    end
    return acc
  end
  local scored = {}
  for rot = 0, 11 do
    scored[#scored + 1] = { s = corr(KRUMHANSL_MAJ, rot),
      name = NOTE_NAMES[rot + 1] }
    scored[#scored + 1] = { s = corr(KRUMHANSL_MIN, rot),
      name = NOTE_NAMES[rot + 1] .. 'm' }
  end
  table.sort(scored, function(x, y) return x.s > y.s end)
  local keys = { scored[1].name }
  -- вторая тональность — если почти не уступает первой
  if scored[2].s > scored[1].s * 0.97 then keys[2] = scored[2].name end

  -- BPM: автокорреляция огибающей (убираем среднее)
  local env, n = an.env, #an.env
  local bpm
  if n > 64 then
    local mean = 0
    for i = 1, n do mean = mean + env[i] end
    mean = mean / n
    for i = 1, n do env[i] = env[i] - mean end
    local dt = 256 / an.sr -- шаг огибающей, сек
    local best, best_lag = -math.huge, nil
    local lag_min = math.max(2, math.floor(60 / 180 / dt))
    local lag_max = math.min(n // 2, math.ceil(60 / 60 / dt))
    for lag = lag_min, lag_max do
      local acc = 0
      for i = 1, n - lag do acc = acc + env[i] * env[i + lag] end
      acc = acc / (n - lag)
      if acc > best then best, best_lag = acc, lag end
    end
    if best_lag then
      bpm = math.floor(60 / (best_lag * dt) + 0.5)
    end
  end
  return keys, bpm
end

-- очередь анализа: карточка за карточкой, окна порциями по бюджету кадра
local function analyze_start(paths)
  local queue = {}
  for _, p in ipairs(paths) do queue[#queue + 1] = p end
  if #queue == 0 then
    logf('warn', T('выборка пуста (sel <pat>)'))
    return
  end
  state.analysis = { queue = queue, cur = nil, done = 0, total = #queue }
end

local function analyze_step()
  local A = state.analysis
  if not A then return end
  if not A.cur then
    local p = table.remove(A.queue, 1)
    if not p then
      logf('ok', string.format(T('Анализ готов: %d'), A.done))
      state.analysis = nil
      return
    end
    local c = state.index.projects[p]
    local audio = c and find_preview_audio(c)
    if not (audio and audio:lower():match('%.wav$')) then
      if c then logf('warn', '✗ ' .. c.name .. ' ' .. T('(нужен wav-превью)')) end
      return
    end
    A.cur = an_begin(c, audio)
    if not A.cur then
      logf('warn', '✗ ' .. c.name)
      return
    end
    return
  end
  local an = A.cur
  local frame_end = reaper.time_precise() + 0.015
  local more = true
  while more and reaper.time_precise() < frame_end do
    more = an_window(an)
  end
  if not more then
    local keys, bpm = an_finish(an)
    an.card.keys_detected = keys
    an.card.bpm_detected = bpm
    save_index_soon()
    logf('ok', string.format('♪ %s: %s%s', an.card.name,
      table.concat(keys, '/'), bpm and (' · ' .. bpm .. 'bpm') or ''))
    A.done = A.done + 1
    A.cur = nil
  end
end

-- Поиск готового рендера по всей ФС (Spotlight). mdfind блокирует на
-- десятки миллисекунд — зовётся только из очереди, по одному на кадр.
local function fs_find_preview(card)
  local clean = card.name:gsub('%[.-%]', ''):gsub('%s+', ' ')
    :match('^%s*(.-)%s*$')
  if #clean < 4 then return nil end
  local out = reaper.ExecProcess(
    '/usr/bin/mdfind -name "' .. clean .. '"', 8000)
  if not out then return nil end
  out = out:gsub('^%d+\n', '')
  local function norm(s) return (s:lower():gsub('[%s%p_]+', '')) end
  local full_n, clean_n = norm(card.name), norm(clean)
  local best, best_score
  for line in out:gmatch('[^\n]+') do
    local ext = line:lower():match('%.([%w]+)$')
    if ext and AUDIO_EXT[ext]
       and not line:find('/Backup', 1, true)
       and not line:find('%.app/')
       and not line:find('_preview%.wav$') then
      local base = norm((line:match('([^/]+)$') or ''):gsub('%.[%w]+$', ''))
      local score
      if base == full_n then score = 100
      elseif base == clean_n then score = 95
      elseif base:find(clean_n, 1, true) then
        score = 80 - math.min(#base - #clean_n, 40)
      end
      if score and (not best_score or score > best_score) then
        best, best_score = line, score
      end
    end
  end
  return best
end

local function findprev_start()
  if #state.sel == 0 then
    logf('warn', T('выборка пуста (sel <pat>)'))
    return
  end
  local queue = {}
  for i, p in ipairs(state.sel) do queue[i] = p end
  state.findprev = { queue = queue, done = 0, hit = 0, total = #queue }
end

local function findprev_step()
  local q = state.findprev
  if not q then return end
  local p = table.remove(q.queue, 1)
  if not p then
    logf('ok', string.format(T('Поиск превью: найдено %d из %d'),
      q.hit, q.total))
    state.findprev = nil
    return
  end
  local c = state.index.projects[p]
  if c then
    audio_cache[p] = nil -- перечитать диск: вдруг превью появилось
    if find_preview_audio(c) then
      q.hit = q.hit + 1
    else
      local hit = fs_find_preview(c)
      if hit then
        c.preview_found = hit
        audio_cache[p] = nil
        save_index_soon()
        q.hit = q.hit + 1
        logf('ok', '✓ ' .. c.name .. ' → ' .. hit)
      else
        logf('warn', '✗ ' .. c.name)
      end
    end
  end
  q.done = q.done + 1
end

-- Батч «превью всем»: очередь путей, по одному проекту на кадр defer-цикла
-- (каждый рендер — модальный, но между ними UI дышит и кнопка «стоп» жива)
local function batch_step()
  local bq = state.batch
  if not bq then return end
  local path = table.remove(bq.queue, 1)
  if not path then
    state.status_msg = string.format(T('Превью-батч: готово %d'), bq.done)
      .. ((bq.skipped or 0) > 0
        and string.format(T(' · пропущено (нет файлов): %d'), bq.skipped) or '')
    state.batch = nil
    return
  end
  local card = state.index.projects[path]
  if card and not project_is_open(path) then
    if #core.missing_media(path) > 0 then
      -- модальный диалог «файлы не найдены» повесил бы очередь
      bq.skipped = (bq.skipped or 0) + 1
    else
      render_audio(card, 'preview')
      bq.done = bq.done + 1
    end
  end
  state.status_msg = string.format(T('Превью-батч: %d/%d'),
    bq.done + (bq.skipped or 0), bq.total)
end

-- Миграция: легаси jf_preview.wav → <имя>_preview.wav. В однопроектных
-- папках переименовываем; в многопроектных общий файл принадлежал всем
-- сразу — его нельзя присвоить одному проекту, поэтому только сообщаем.
local function migrate_legacy_previews()
  local by_dir = {}
  for path, card in pairs(state.index.projects) do
    local dir = path:match('^(.*)[/\\]') or '.'
    local d = by_dir[dir]
    if not d then d = {} by_dir[dir] = d end
    d[#d + 1] = card
  end
  local moved, shared = 0, 0
  for dir, cards in pairs(by_dir) do
    local legacy = dir .. '/jf_preview.wav'
    local f = io.open(legacy, 'rb')
    if f then
      f:close()
      if #cards == 1 then
        local target = dir .. '/' .. cards[1].name:gsub('%$', '') .. '_preview.wav'
        local tf = io.open(target, 'rb')
        if tf then
          tf:close()
          os.remove(legacy) -- именное превью уже есть, легаси лишний
        elseif os.rename(legacy, target) then
          moved = moved + 1
        end
        audio_cache[cards[1].path] = nil
      else
        shared = shared + 1 -- батч дорендерит именные каждому
      end
    end
  end
  wave_cache, dir_count_cache = {}, {}
  state.status_msg = string.format(
    T('Легаси-превью: переименовано %d, общих на папку %d (батч дорендерит)'),
    moved, shared)
end

local function batch_start()
  local queue = {}
  for path, card in pairs(state.index.projects) do
    local audio = find_preview_audio(card)
    if not audio then
      queue[#queue + 1] = path -- превью нет — рендерим
    elseif audio:match('_preview%.wav$') or audio:match('jf_preview%.wav$') then
      -- своё превью есть, но сплошная тишина — битый рендер, перерендерить
      if core.wav_is_silent(audio) == true then
        audio_cache[path] = nil
        queue[#queue + 1] = path
      end
    end
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

-- DAW-метка тамбнейла: только цветная рамка — плашка закрывала картинку
-- (текстовый бейдж [Ab] и так стоит перед именем карточки)
local function draw_daw_overlay(card, x0, y0, size)
  if not card.daw then return end
  local dt = core.DAW_TYPES[card.daw_ext] or {}
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRect(dl, x0, y0, x0 + size, y0 + size,
    dt.color or 0x8A8F93FF, 4, 0, 1.5)
end

local function draw_thumb(card, size)
  -- превью: назначенное вручную → <имя проекта>.png / jf_thumb.png в папке
  local img = card.thumb_user and get_image(card.thumb_user) or nil
  if not img and card.thumb_file then img = get_image(card.thumb_file) end
  if img then
    local ix, iy = ImGui.GetCursorScreenPos(ctx)
    ImGui.Image(ctx, img, size, size)
    draw_daw_overlay(card, ix, iy, size)
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
  draw_daw_overlay(card, x0, y0, size)
  ImGui.Dummy(ctx, size, size)
end

-- ---------------------------------------------------------------------------
-- Сетка карточек

-- Ряд команд карточки (всегда наверху). true — был клик по кнопке.
-- Нижний ряд команд карточки: прозрачные значки без фона.
-- Порядок: свернуть/развернуть и выбрать — первыми слева, деструктив — справа.
local function draw_card_icons(card, meta, i, expanded, compact)
  local hit = false
  local foreign = card.daw ~= nil
  local function icon(glyph, id, tip, col)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x00000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xFFFFFF22)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xFFFFFF3A)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col or 0x8A8F93FF)
    local clicked = ImGui.SmallButton(ctx, glyph .. '###' .. id .. i)
    ImGui.PopStyleColor(ctx, 4)
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, tip)
    end
    if clicked then hit = true end
    return clicked
  end

  if icon(expanded and '▴' or '▾', 'fold',
      expanded and T('свернуть') or T('развернуть')) then
    state.expanded = expanded and nil or card.path
    state.focus = i
  end
  ImGui.SameLine(ctx)
  local si = sel_index(card.path)
  if icon(si and '■' or '□', 'sel',
      si and T('снять выбор') or T('выбрать'),
      si and 0xD9B96CFF or nil) then
    toggle_select(card.path)
  end
  ImGui.SameLine(ctx)
  if icon(card.pinned and '●' or '○', 'pin',
      card.pinned and T('открепить') or T('закрепить'),
      card.pinned and 0xD9B96CFF or nil) then
    toggle_pin(card)
  end
  ImGui.SameLine(ctx)
  if foreign then
    local dt = core.DAW_TYPES[card.daw_ext] or {}
    if icon('▸', 'dopen', T('открыть в ') .. (dt.daw or 'DAW'), dt.color) then
      open_project(card.path)
    end
    if compact then
      -- S: ещё картинка, обновление и удаление
      ImGui.SameLine(ctx)
      if icon('▦', 'thumb', T('назначить картинку-превью…')) then
        local rv, fn = reaper.GetUserFileNameForRead('',
          'Картинка-превью проекта', '')
        if rv and fn and fn ~= '' then
          card.thumb_user = fn
          img_cache[fn] = nil
          save_index_soon()
        end
      end
      ImGui.SameLine(ctx)
      if icon('↻', 'refr', T('обновить карточку (перечитать .rpp)')) then
        refresh_card(card.path)
      end
      ImGui.SameLine(ctx)
      if icon('×', 'del', T('удалить в Корзину…'), 0xB06060FF) then
        delete_project(card)
      end
      return hit
    end
  elseif compact then
    if icon('▸', 'prev', T('отрендерить аудио-превью')) then
      render_audio(card, 'preview')
    end
    ImGui.SameLine(ctx)
    if icon('▶', 'demo', T('отрендерить полное демо (весь проект)')) then
      render_audio(card, 'demo')
    end
    ImGui.SameLine(ctx)
    if icon('▦', 'thumb', T('назначить картинку-превью…')) then
      local rv, fn = reaper.GetUserFileNameForRead('',
        'Картинка-превью проекта', '')
      if rv and fn and fn ~= '' then
        card.thumb_user = fn
        img_cache[fn] = nil
        save_index_soon()
      end
    end
    ImGui.SameLine(ctx)
    if icon('↻', 'refr', T('обновить карточку (перечитать .rpp)')) then
      refresh_card(card.path)
    end
    ImGui.SameLine(ctx)
    if icon('×', 'del', T('удалить в Корзину…'), 0xB06060FF) then
      delete_project(card)
    end
    return hit
  else
    if icon('▸', 'prev', T('отрендерить аудио-превью')) then
      render_audio(card, 'preview')
    end
    ImGui.SameLine(ctx)
    if icon('▶', 'demo', T('отрендерить полное демо (весь проект)')) then
      render_audio(card, 'demo')
    end
    ImGui.SameLine(ctx)
    if icon('Aa', 'ren', T('переименовать проект…')) then
      if state.ren_path == card.path then
        state.ren_path = nil
      else
        state.ren_path, state.ren_text = card.path, card.name
        state.ren_focus = true
      end
    end
  end
  ImGui.SameLine(ctx)
  if icon('▦', 'thumb', T('назначить картинку-превью…')) then
    local rv, fn = reaper.GetUserFileNameForRead('', 'Картинка-превью проекта', '')
    if rv and fn and fn ~= '' then
      card.thumb_user = fn
      img_cache[fn] = nil
      save_index_soon()
    end
  end
  if card.thumb_user then
    ImGui.SameLine(ctx)
    if icon('▧', 'unthumb', T('сбросить превью')) then
      card.thumb_user = nil
      save_index_soon()
    end
  end
  ImGui.SameLine(ctx)
  if icon('↻', 'refr', T('обновить карточку (перечитать .rpp)')) then
    refresh_card(card.path)
    state.status_msg = T('Обновлено: ') .. card.name
  end
  ImGui.SameLine(ctx)
  if icon('×', 'del', T('удалить в Корзину…'), 0xB06060FF) then
    delete_project(card)
  end

  -- инлайн-поле переименования — под рядом
  if state.ren_path == card.path then
    ImGui.SetNextItemWidth(ctx, -1)
    if state.ren_focus then
      ImGui.SetKeyboardFocusHere(ctx)
      state.ren_focus = false
    end
    local done, v = ImGui.InputTextWithHint(ctx, '###rename' .. i,
      T('новое имя + Enter'), state.ren_text, ImGui.InputTextFlags_EnterReturnsTrue)
    if v then state.ren_text = v end
    if done then
      rename_project(card, state.ren_text)
      state.ren_path = nil
    end
    hit = true
  end
  return hit
end

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
  ImGui.Text(ctx, string.format('%s · %d/%d · %d трек(ов) · %d айтем(ов)',
    fmt_bpm(card) or '— BPM',
    card.timesig_num or 4, card.timesig_den or 4, card.track_count or 0,
    card.item_count or 0))
  local keys_str = fmt_keys(card)
  if keys_str then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0x7BD9D0FF, '· ' .. keys_str)
  end
  if core.is_empty_project(card) then
    ImGui.TextColored(ctx, 0x8A8F93FF, '∅ ' ..
      ((card.item_count == 0) and T('нет айтемов') or T('нет аудио в папке проекта')) ..
      ((card.audio_files ~= nil)
        and ('  ·  ' .. T('аудиофайлов: ') .. card.audio_files) or ''))
  end

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
      for bi, bk in ipairs(backups) do
        -- клик — открыть бэкап в новой вкладке, «↩» — восстановить
        if ImGui.SmallButton(ctx, string.format('%s — %s, %s###bko%d',
            bk.file, fmt_date(bk.mtime), fmt_size(bk.size), bi)) then
          open_backup(card, bk)
        end
        if state.btn_tips and ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, T('открыть бэкап в новой вкладке'))
        end
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, '↩###bkr' .. bi) then
          restore_backup(card, bk)
          ImGui.TreePop(ctx)
          return
        end
        if state.btn_tips and ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, T('восстановить проект из этого бэкапа…'))
        end
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
      local prev_extra = {}
      for _, x in ipairs(card.tags_extra or {}) do prev_extra[#prev_extra + 1] = x end
      card.tags_extra = #extra > 0 and extra or nil
      search_cache[card.path] = nil
      save_index_soon()
      local upath = card.path
      push_undo(string.format(T('тег #%s на «%s»'), t, card.name), function()
        local c = state.index.projects[upath] or card
        c.tags_extra = #prev_extra > 0 and prev_extra or nil
        search_cache[upath] = nil
        save_index_soon()
      end)
      logf('act', string.format(T('тег #%s на «%s»'), t, card.name))
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
        save_index_soon()
      end
      state.tag_add_path = nil
    end
  end

  if (card.atime or 0) > 0 then
    ImGui.TextDisabled(ctx, T('Открыт: ') .. fmt_date(card.atime))
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
end

local function draw_card(entry, i, card_w)
  local card, meta = entry.card, entry.meta
  local cs = CARD_SIZES[state.card_size]
  local expanded = state.expanded == card.path
  local focused = state.focus == i
  local si = sel_index(card.path)
  local inner_click = false  -- клик по виджету внутри — не менять фокус
  local h = expanded and 0 or cs.h  -- 0 = авто-высота по контенту

  local child_flags = ImGui.ChildFlags_Border
  if expanded then
    child_flags = child_flags | ImGui.ChildFlags_AutoResizeY
  end
  -- без скроллбаров: в свёрнутом виде контент подгоняется под высоту,
  -- в раскрытом карточка растёт сама (AutoResizeY)
  local win_flags = ImGui.WindowFlags_NoScrollbar
    | ImGui.WindowFlags_NoScrollWithMouse
  local hilite = focused or si
  if hilite then
    -- жирная рамка выделения/фокуса
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildBorderSize, 2.5)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border,
      focused and 0xE8E8E8FF or 0xD9B96CFF)
  end
  if ImGui.BeginChild(ctx, card.path, card_w, h, child_flags, win_flags) then
    -- vim-хинт (режим f): жёлтый прямоугольник справа от иконки, на
    -- первой линии карточки; foreground-слой — ничто его не перекроет
    if state.hints and state.hints.labels[i] then
      local hx, hy = ImGui.GetCursorScreenPos(ctx)
      local fdl = ImGui.GetForegroundDrawList(ctx)
      local lbl = state.hints.labels[i]
      local tw = ImGui.CalcTextSize(ctx, lbl)
      local bx = hx + cs.thumb + 8
      ImGui.DrawList_AddRectFilled(fdl, bx, hy,
        bx + tw + 10, hy + 17, 0xE8D44DFF, 3)
      ImGui.DrawList_AddRect(fdl, bx, hy, bx + tw + 10, hy + 17,
        0x111213FF, 3)
      ImGui.DrawList_AddText(fdl, bx + 5, hy + 1, 0x111213FF, lbl)
    end
    if cs.micro then
      -- S: микро-логотип слева + волна; ховер по логотипу — play/stop
      local lx, ly = ImGui.GetCursorScreenPos(ctx)
      draw_thumb(card, cs.thumb)
      local over_logo = ImGui.IsItemHovered(ctx)
      local audio = find_preview_audio(card)
      if over_logo then
        local pdl = ImGui.GetWindowDrawList(ctx)
        ImGui.DrawList_AddRectFilled(pdl, lx, ly,
          lx + cs.thumb, ly + cs.thumb, 0x000000AA, 3)
        ImGui.DrawList_AddText(pdl, lx + 6, ly + 3, 0xFFFFFFFF,
          (audio and is_playing(audio)) and '■' or '▶')
        ImGui.SetTooltip(ctx, card.name)
        local lm = ImGui.GetKeyMods(ctx)
        local lsel = lm & ImGui.Mod_Ctrl ~= 0 or lm & ImGui.Mod_Super ~= 0
        if ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
          open_project(card.path) -- двойной клик по логотипу — открыть
          inner_click = true
        elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left)
           and not lsel then
          -- cmd+клик пропускаем карточке: выделение вместо плей
          if audio then preview_toggle(audio, true) end
          inner_click = true
        end
      end
      ImGui.SameLine(ctx)
      if draw_wave_strip(card, ImGui.GetContentRegionAvail(ctx),
          cs.thumb, true) then
        inner_click = true
      end
      ImGui.EndChild(ctx)
      goto card_done
    end
    if cs.mini then
      -- M: клип — тамбнейл слева, имя и волна справа, кнопки снизу
      draw_thumb(card, cs.thumb)
      ImGui.SameLine(ctx)
      ImGui.BeginGroup(ctx)
      if card.daw then
        local dt = core.DAW_TYPES[card.daw_ext] or {}
        ImGui.TextColored(ctx, dt.color or 0x9A9A9AFF,
          '[' .. (dt.label or '?') .. ']')
        ImGui.SameLine(ctx)
        ImGui.Text(ctx, trunc(card.name, cs.name - 4))
      else
        ImGui.Text(ctx, trunc(card.name, cs.name))
      end
      if draw_wave_strip(card, ImGui.GetContentRegionAvail(ctx), 18) then
        inner_click = true
      end
      ImGui.EndGroup(ctx)
      if draw_card_icons(card, meta, i, false, true) then inner_click = true end
      ImGui.EndChild(ctx)
      goto card_done
    end
    draw_thumb(card, cs.thumb)
    ImGui.SameLine(ctx)
    ImGui.BeginGroup(ctx)
    if card.daw then
      -- цветной бейдж DAW перед именем: после длинного имени он бы уехал
      local dt = core.DAW_TYPES[card.daw_ext] or {}
      ImGui.TextColored(ctx, dt.color or 0x9A9A9AFF, '[' .. (dt.label or '?') .. ']')
      if state.btn_tips and ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, (dt.daw or '') .. ' · ' ..
          T('двойной клик — открыть в этой программе'))
      end
      ImGui.SameLine(ctx)
      ImGui.Text(ctx, trunc(card.name, cs.name - 4))
    else
      ImGui.Text(ctx, trunc(card.name, cs.name))
    end
    -- дата и bpm — справа от имени, той же строкой
    local right = os.date('%d.%m.%y', card.mtime or 0)
    local bpm_str = fmt_bpm(card)
    if bpm_str then right = right .. ' · ' .. bpm_str end
    ImGui.SameLine(ctx,
      card_w - ImGui.CalcTextSize(ctx, right) - 12)
    ImGui.TextDisabled(ctx, right)
    if card.trashed then
      local left = core.trash_days_left(card)
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0xE06060FF, '🗑' .. (left or 0))
      if state.btn_tips and ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, string.format(
          T('в корзине · %d дней до удаления · × — вернуть'), left or 0))
      end
    end
    -- метка дубля (когда включён фильтр «дубли»)
    local dmark = state.filter_dups and (state.dup_marks or {})[card.path]
    if dmark and dmark ~= 'newest' then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, dmark == 'copy' and 0xE06060FF or 0xD9B96CFF,
        dmark == 'copy' and '⧉' or '⧉v')
      if state.btn_tips and ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, dmark == 'copy'
          and T('побайтная копия — можно удалять')
          or T('версия того же проекта'))
      end
    end
    -- рейтинг тейков: смайлик, если в регионах есть #+
    local rating = core.take_rating(card)
    if rating > 0 then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0x7FD98AFF, rating >= 3 and '★' or '☺')
      if state.btn_tips and ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, string.format(T('удачные тейки: %s'),
          string.rep('+', rating)))
      end
    end
    if core.is_empty_project(card) then
      -- пустышка: ни одного айтема или ни одного аудиофайла в папке
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0x7A7A7AFF, '∅')
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, (card.item_count == 0 and T('нет айтемов') or
          T('нет аудио в папке проекта')))
      end
    end
    if card.pinned then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0xD9B96CFF, '●') -- закреплён
    end
    if si then
      ImGui.SameLine(ctx)
      -- номер в выборке = позиция в merge
      ImGui.TextColored(ctx, 0xD9B96CFF, '[' .. si .. ']')
    end
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
      if ni == #core.STATUSES + 1 then
        delete_project(card) -- последний пункт выпадашки — удаление
      else
        set_status(card, ni == 0 and '' or core.STATUSES[ni])
      end
      inner_click = true
    end
    if (meta.deadline or 0) > 0 then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, deadline_color(meta.deadline, os.time()),
        '→ ' .. os.date('%d.%m', meta.deadline))
    end
    if meta.status == '' then
      -- класса нет — показываем догадку по содержимому
      local cat = core.auto_category(card)
      if cat then
        ImGui.SameLine(ctx)
        ImGui.TextColored(ctx, CAT_COLORS[cat] or 0x8A8F93FF, '~' .. cat)
        if state.btn_tips and ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, T('подсказка по содержимому · клик — принять'))
        end
        if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
          set_status(card, cat)
          inner_click = true
        end
      end
    end
    if card.needs_report then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0xE06060FF, T('· без отчёта'))
    end

    local keys_str = fmt_keys(card)
    -- компактная строка: длительность · размер · тональности
    ImGui.TextDisabled(ctx, fmt_duration(card.duration)
      .. (card.dir_size and ('   ' .. fmt_size(card.dir_size)) or '')
      .. (keys_str and ('   ' .. keys_str) or ''))
    ImGui.EndGroup(ctx)

    -- следующий шаг из последнего отчёта — открытая петля снаружи головы
    local next_action = meta.report_todo:match('^[^\n]+')
    if next_action then
      ImGui.TextColored(ctx, 0xD9B96CFF,
        trunc('→ ' .. next_action, cs.name + 8))
    end

    -- теги: в свёрнутом виде одной строкой (без переносов — иначе
    -- карточка перерастает высоту и появляется скроллбар)
    local tags = all_tags(card, meta)
    if #tags > 0 then
      if expanded then
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
      else
        ImGui.TextColored(ctx, tag_color(tags[1]),
          trunc('#' .. table.concat(tags, ' #'), cs.name + 10))
      end
    end

    -- превью всегда видно: волна прижата к низу, под ней ряд кнопок
    if not expanded then
      -- прижать волну и кнопки к низу, но карточка уже подогнана
      -- по высоте — большого пустого поля не остаётся
      local _, resty = ImGui.GetContentRegionAvail(ctx)
      if resty and resty > 50 then ImGui.Dummy(ctx, 1, resty - 50) end
    end
    if draw_wave_strip(card, ImGui.GetContentRegionAvail(ctx), 20) then
      inner_click = true
    end

    if expanded then draw_card_details(card, meta) end
    if draw_card_icons(card, meta, i, expanded) then inner_click = true end
    ImGui.EndChild(ctx)
  end
  -- карточку можно перетащить в плейлист (payload как в канбане)
  if ImGui.BeginDragDropSource(ctx) then
    ImGui.SetDragDropPayload(ctx, 'JF_PM_CARD', card.path)
    ImGui.Text(ctx, card.name)
    ImGui.EndDragDropSource(ctx)
  end
  ::card_done::
  if hilite then
    ImGui.PopStyleColor(ctx)
    ImGui.PopStyleVar(ctx)
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
      end
      -- обычный клик — только фокус; раскрытие — стрелкой ▾ или Enter
      state.focus = i
    end
  end
end

local function draw_grid(cards)
  if #cards == 0 then
    ImGui.TextDisabled(ctx, T('Пусто. Rescan, или ослабь фильтры.'))
    return 1
  end
  local cs = CARD_SIZES[state.card_size]
  local avail = ImGui.GetContentRegionAvail(ctx)
  local card_w = cs.w
  local cols = math.max(1, math.floor(avail / (card_w + 8)))

  -- Виртуализация: на 2000 карточках рисуем только видимые строки.
  -- Раскрытая карточка или режим L ломают равновысотность — тогда
  -- честный полный проход (редкий случай).
  if state.expanded then
    -- одна раскрытая ломает равновысотность — честный полный проход
    state.vis_first, state.vis_last = 1, #cards
    for i, entry in ipairs(cards) do
      if (i - 1) % cols ~= 0 then ImGui.SameLine(ctx) end
      draw_card(entry, i, card_w)
    end
    return cols
  end

  local _, spacing_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local row_h = cs.h + spacing_y
  local total_rows = math.ceil(#cards / cols)

  -- фокус вне окна: подскроллить до отрисовки, чтобы строка попала в кадр
  if state.scroll_to_focus and state.focus > 0 then
    local frow = math.floor((state.focus - 1) / cols)
    local vis_h = ImGui.GetWindowHeight(ctx)
    local target = frow * row_h - vis_h / 2 + row_h / 2
    ImGui.SetScrollY(ctx, math.max(0, target))
    state.scroll_to_focus = false
  end

  local scroll = ImGui.GetScrollY(ctx)
  local vis_h = ImGui.GetWindowHeight(ctx)
  local first_row = math.max(0, math.floor(scroll / row_h) - 1)
  local last_row = math.min(total_rows - 1,
    math.ceil((scroll + vis_h) / row_h) + 1)
  state.vis_first = first_row * cols + 1
  state.vis_last = math.min(#cards, (last_row + 1) * cols)

  if first_row > 0 then
    ImGui.Dummy(ctx, 1, first_row * row_h - spacing_y)
  end
  for row = first_row, last_row do
    for col = 0, cols - 1 do
      local i = row * cols + col + 1
      local entry = cards[i]
      if entry then
        if col > 0 then ImGui.SameLine(ctx) end
        draw_card(entry, i, card_w)
      end
    end
  end
  if last_row < total_rows - 1 then
    ImGui.Dummy(ctx, 1, (total_rows - 1 - last_row) * row_h - spacing_y)
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
          ImGui.SameLine(ctx)
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x7BB8D9FF)
          if ImGui.SmallButton(ctx, '▸###kbopen' .. ci .. '_' .. ei) then
            open_project(card.path)
          end
          ImGui.PopStyleColor(ctx)
          if state.btn_tips and ImGui.IsItemHovered(ctx) then
            ImGui.SetTooltip(ctx, T('открыть проект'))
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

local function chip(label, active, col)
  -- col — акцент активного чипа (цветовое кодирование групп)
  local on = col or 0x3D3D3DFF
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, active and on or 0x1E1E1EFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered,
    active and on or 0x2E2E2EFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text,
    active and (col and 0x111213FF or 0xFFFFFFFF) or 0x9A9A9AFF)
  local clicked = ImGui.SmallButton(ctx, label)
  ImGui.PopStyleColor(ctx, 3)
  return clicked
end

-- Вкладка вида: крупная кнопка со скруглением сверху, активная — цветная
local VIEW_COLORS = { 0x7BB8D9FF, 0xD9B96CFF, 0x7FD98AFF, 0xC98AD9FF }
local function view_tab(label, active, col)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 12, 6)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, active and col or 0x232425FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered,
    active and col or 0x323334FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, active and 0x111213FF or 0xB5B8BAFF)
  local clicked = ImGui.Button(ctx, label)
  ImGui.PopStyleColor(ctx, 4)
  ImGui.PopStyleVar(ctx, 2)
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
  -- как скрипт разбирает строку: каждая папка отдельно, с проверкой
  for p in state.scan_paths:gmatch('[^;]+') do
    p = p:match('^%s*(.-)%s*$')
    if p ~= '' then
      local ok = reaper.EnumerateFiles(p, 0) ~= nil
        or reaper.EnumerateSubdirectories(p, 0) ~= nil
      ImGui.TextColored(ctx, ok and 0x7FD98AFF or 0xE06060FF,
        (ok and '✓ ' or '✗ ') .. p)
    end
  end
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
  ImGui.Text(ctx, T('Подсказки кнопок:'))
  ImGui.SameLine(ctx)
  if chip(T('вкл') .. '###tip1', state.btn_tips) then
    state.btn_tips = true
    core.set_setting('btn_tips', '1')
  end
  ImGui.SameLine(ctx)
  if chip(T('выкл') .. '###tip0', not state.btn_tips) then
    state.btn_tips = false
    core.set_setting('btn_tips', '0')
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
    if ImGui.Button(ctx, T('Починить легаси-превью')) then
      migrate_legacy_previews()
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

local CAT_COLORS = {
  ['тест'] = 0x8A8F93FF, ['семпл'] = 0x7BD9D0FF, ['скетч'] = 0x9A9AD9FF,
  ['джем'] = 0xD9A87BFF, ['аранжировка'] = 0xD9B96CFF,
}

local LOG_COLORS = {
  act = 0xB5B8BAFF, undo = 0x7BB8D9FF, del = 0xE06060FF,
  warn = 0xD9B96CFF, ok = 0x7FD98AFF, cmd = 0x7BD9D0FF, ['in'] = 0xD9B96CFF,
}

-- ---------------------------------------------------------------------------
-- Большой плеер сфокусированной карточки: волна во всю ширину, drag мышью —
-- выделение луп-региона, «+ луп» сохраняет его в карточку (индекс, переживает
-- Rescan). Лупы — черновые маркеры для сборки сабпроектами: время превью ≈
-- времени проекта (обрезка тишины в начале даёт сдвиг до ~0.5 c).

local bigsel = {}  -- path -> {a, b} выделение в долях 0..1
local bigdrag = nil

local function draw_big_player(entry)
  if not entry then return end
  local card = entry.card
  local audio = find_preview_audio(card)
  if not audio then return end
  local w = get_wave(audio)
  if not w then return end

  local H = 64
  -- битовая сетка проекта в координатах превью: узел k*beat − pv_offset
  local bpm = core.card_bpm(card)
  local beat = bpm and 60 / bpm or nil
  local off = card.pv_offset or 0
  local function snap_time(t)
    if not (state.loop_snap and beat) then return t end
    local k = math.floor((t + off) / beat + 0.5)
    return math.min(math.max(k * beat - off, 0), w.len)
  end

  local ebpm = eff_bpm(card)
  ImGui.TextDisabled(ctx, T('плеер: ') .. card.name
    .. (ebpm and ('  ' .. ebpm .. 'bpm') or '')
    .. (card.keys_detected and ('  ' ..
        table.concat(card.keys_detected, '/')) or ''))
  ImGui.SameLine(ctx)
  -- питч-крутилка: полутоны, live на играющее превью
  ImGui.SetNextItemWidth(ctx, 74)
  local pv = pitch_map[card.path] or 0
  local pchg, pnew = ImGui.DragDouble(ctx, '###pitch' .. card.path,
    pv, 0.05, -12, 12, 'pt %+.1f')
  if pchg then
    pitch_map[card.path] = pnew ~= 0 and pnew or nil
    if players[audio] then
      reaper.CF_Preview_SetValue(players[audio], 'D_PITCH', pnew)
    end
  end
  if state.btn_tips and ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, T('питч, полутоны · двойной клик — ввод'))
  end
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, 'analyze###an' .. card.path) then
    analyze_start({ card.path })
  end
  if state.btn_tips and ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, T('анализ: тональность и BPM (по wav-превью)'))
  end
  -- scale sync: M — этот клип задаёт тональность, S — подстроить этот
  -- клип питчем под мастера (кратчайший сдвиг корня, ±6 полутонов)
  ImGui.SameLine(ctx)
  if chip('M###km' .. card.path, state.key_master == card.path,
      0xD98ABDFF) then
    state.key_master = state.key_master ~= card.path and card.path or nil
  end
  if state.btn_tips and ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, T('мастер тональности (scale sync)'))
  end
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, 'S###ks' .. card.path) then
    local mc = state.key_master and state.index.projects[state.key_master]
    local mroot = mc and key_root(card_key(mc))
    local sroot = key_root(card_key(card))
    if state.key_master == card.path then
      logf('warn', T('это мастер — подстраивай другие клипы'))
    elseif not mroot then
      logf('warn', T('нет мастера или его тональности (M + analyze)'))
    elseif not sroot then
      logf('warn', T('у клипа нет тональности — жми analyze'))
    else
      local d = ((mroot - sroot + 6) % 12) - 6
      pitch_map[card.path] = d ~= 0 and d or nil
      if players[audio] then
        reaper.CF_Preview_SetValue(players[audio], 'D_PITCH', d)
      end
      logf('act', string.format('scale: %s %s → %s (%+d st)',
        card.name, card_key(card), card_key(mc), d))
    end
  end
  if state.btn_tips and ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, T('слейв: подстроить тональность под мастера'))
  end
  ImGui.SameLine(ctx)
  if chip(T('снэп') .. (beat and '' or ' (нет bpm)') .. '###lsnap',
      state.loop_snap and beat ~= nil, 0x7BB8D9FF) then
    state.loop_snap = not state.loop_snap
    core.set_setting('loop_snap', state.loop_snap and '1' or '0')
  end
  local sel = bigsel[card.path]
  ImGui.SameLine(ctx)
  if sel then
    if ImGui.SmallButton(ctx, '+ ' .. T('луп') .. '###addloop') then
      card.loops = card.loops or {}
      card.loops[#card.loops + 1] =
        { a = sel.a * w.len, b = sel.b * w.len }
      table.sort(card.loops, function(x, y) return x.a < y.a end)
      save_index_soon()
      logf('act', string.format(T('луп %s: %s–%s'), card.name,
        fmt_duration(sel.a * w.len), fmt_duration(sel.b * w.len)))
      bigsel[card.path] = nil
    end
    ImGui.SameLine(ctx)
  end
  if is_playing(audio) then
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '■###bigstop') then preview_stop(audio) end
  end

  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local width = ImGui.GetContentRegionAvail(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + width, y0 + H, 0x141414FF, 3)
  local mid = y0 + H / 2
  local step = width / w.n
  for i = 1, w.n do
    local x = x0 + (i - 1) * step
    local col = w.spec and spec_color(w.spec[i]) or 0x8A8F93FF
    local hi = math.min(math.max(w.max[i], 0), 1) * (H / 2 - 2)
    local lo = math.min(math.max(-w.min[i], 0), 1) * (H / 2 - 2)
    ImGui.DrawList_AddRectFilled(dl, x, mid - hi,
      x + math.max(step - 1, 1), mid + lo + 1, col)
  end
  -- битовая сетка: доли тускло, такты (по размеру проекта) ярче
  if state.loop_snap and beat and w.len > 0 then
    local tsig = card.timesig_num or 4
    local k0 = math.ceil(off / beat)
    local k = k0
    while true do
      local t = k * beat - off
      if t > w.len then break end
      local gx = x0 + t / w.len * width
      local is_bar = (k % tsig) == 0
      ImGui.DrawList_AddLine(dl, gx, y0, gx, y0 + H,
        is_bar and 0xFFFFFF2E or 0xFFFFFF14, 1)
      k = k + 1
      if k - k0 > 2000 then break end
    end
  end

  -- сохранённые лупы — янтарные скобки
  for li, lp in ipairs(card.loops or {}) do
    local lx0 = x0 + math.min(lp.a / w.len, 1) * width
    local lx1 = x0 + math.min(lp.b / w.len, 1) * width
    ImGui.DrawList_AddRectFilled(dl, lx0, y0 + H - 6, lx1, y0 + H, 0xD9B96C88)
    ImGui.DrawList_AddText(dl, lx0 + 2, y0 + H - 18, 0xD9B96CFF,
      tostring(li))
  end
  -- текущее выделение
  if sel then
    local sx0 = x0 + sel.a * width
    local sx1 = x0 + sel.b * width
    ImGui.DrawList_AddRectFilled(dl, sx0, y0, sx1, y0 + H, 0xD9B96C33)
    ImGui.DrawList_AddRect(dl, sx0, y0, sx1, y0 + H, 0xD9B96CFF)
  end
  -- курсор воспроизведения
  if is_playing(audio) then
    local ok, pos = reaper.CF_Preview_GetValue(players[audio], 'D_POSITION')
    if ok and w.len > 0 then
      local px = x0 + math.min(pos / w.len, 1) * width
      ImGui.DrawList_AddLine(dl, px, y0, px, y0 + H, 0xFFFFFFDD, 1)
    end
  end

  ImGui.InvisibleButton(ctx, '###bigwave' .. card.path, width, H)
  local frac = math.min(math.max(
    (ImGui.GetMousePos(ctx) - x0) / width, 0), 1)
  if ImGui.IsItemActivated(ctx) then
    bigdrag = { path = card.path, start = frac, moved = false }
  end
  if bigdrag and bigdrag.path == card.path and ImGui.IsItemActive(ctx) then
    if math.abs(frac - bigdrag.start) > 0.005 then
      bigdrag.moved = true
      local ta = snap_time(math.min(bigdrag.start, frac) * w.len)
      local tb = snap_time(math.max(bigdrag.start, frac) * w.len)
      if tb - ta < 0.01 and beat then tb = math.min(ta + beat, w.len) end
      bigsel[card.path] = { a = ta / w.len, b = tb / w.len }
    end
  end
  if bigdrag and bigdrag.path == card.path
     and ImGui.IsItemDeactivated(ctx) then
    if not bigdrag.moved then
      -- клик без драга: играть с этого места (сброс выделения)
      bigsel[card.path] = nil
      loop_bounds[audio] = nil
      if not is_playing(audio) then
        preview_play(audio, true)
        apply_play_fx(card, audio)
      end
      if players[audio] and w.len > 0 then
        reaper.CF_Preview_SetValue(players[audio], 'D_POSITION',
          frac * w.len)
      end
    end
    bigdrag = nil
  end

  -- лупы списком: ▶ играет луп по кругу, × удаляет
  if card.loops and #card.loops > 0 then
    for li, lp in ipairs(card.loops) do
      if li > 1 then ImGui.SameLine(ctx) end
      if ImGui.SmallButton(ctx, string.format('▶%d %s–%s###lp%d', li,
          fmt_duration(lp.a), fmt_duration(lp.b), li)) then
        preview_play(audio, true)
        apply_play_fx(card, audio)
        if players[audio] then
          reaper.CF_Preview_SetValue(players[audio], 'D_POSITION', lp.a)
          loop_bounds[audio] = { a = lp.a, b = lp.b }
        end
      end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, '×###lpx' .. li) then
        table.remove(card.loops, li)
        if #card.loops == 0 then card.loops = nil end
        save_index_soon()
        break
      end
    end
  end
  ImGui.Separator(ctx)
end

-- Плейлист выбранных: слева от стека плееров, в стиле region manager.
-- Элементы — превью и все лупы каждого выбранного, по порядку выборки;
-- ▶ — последовательно (поверх параллельных лупов), повтор — по кругу.
local function build_playq()
  local q = {}
  local src = #state.playq > 0 and state.playq or state.sel
  for _, p in ipairs(src) do
    local c = state.index.projects[p]
    if c then
      local a = find_preview_audio(c)
      if a then
        q[#q + 1] = { label = '▸ ' .. trunc(c.name, 18), audio = a, card = c }
        for li, lp in ipairs(c.loops or {}) do
          q[#q + 1] = { label = string.format('⟲%d %s', li,
            trunc(c.name, 14)), audio = a, a = lp.a, b = lp.b,
            card = c, li = li }
        end
      end
    end
  end
  return q
end

local function draw_playq_panel(stack_h)
  local q = build_playq()
  if ImGui.BeginChild(ctx, '##playq', 270, stack_h,
      ImGui.ChildFlags_Border) then
    ImGui.TextDisabled(ctx, T('плейлист') ..
      (#state.playq > 0 and (' (' .. #state.playq .. ')') or
        (' · ' .. T('выборка'))))
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '×###pqclear') then
      state.playq = {}
      playlist = nil
    end
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, T('очистить плейлист'))
    end
    if ImGui.SmallButton(ctx, '▶###pqplay') then
      if #q > 0 then
        playlist = { queue = q, i = 1, started = false,
          rep = state.playq_rep }
      end
    end
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, T('играть по очереди'))
    end
    ImGui.SameLine(ctx)
    -- sync play: всё стартует одновременно (с BPM-синком ложится в грув)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x7FD98AFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x111213FF)
    local syncgo = ImGui.SmallButton(ctx, '⇉ sync###pqsync')
    ImGui.PopStyleColor(ctx, 2)
    if syncgo then
      playlist = nil
      preview_stop()
      for _, el in ipairs(q) do
        preview_play(el.audio, true)
        if el.card then apply_play_fx(el.card, el.audio) end
        if players[el.audio] then
          if el.a then
            reaper.CF_Preview_SetValue(players[el.audio], 'D_POSITION', el.a)
            loop_bounds[el.audio] = { a = el.a, b = el.b }
          else
            reaper.CF_Preview_SetValue(players[el.audio], 'D_POSITION', 0)
            loop_bounds[el.audio] = nil
          end
        end
      end
      logf('act', string.format(T('sync play: %d'), #q))
    end
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, T('стартовать все одновременно'))
    end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '■###pqstop') then
      playlist = nil
      preview_stop() -- главный плеер: гасит все превью, где бы ни играли
    end
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, T('стоп всех превью (глобальный)'))
    end
    ImGui.SetNextItemWidth(ctx, 48)
    local bchg, bnew = ImGui.DragInt(ctx, '###mbpm', state.master_bpm,
      0.2, 40, 240, '%d')
    if bchg then
      state.master_bpm = bnew
      core.set_setting('master_bpm', tostring(bnew))
      if state.bpm_sync then
        -- живое обновление rate всех играющих
        for p, cc in pairs(state.index.projects) do
          local a = audio_cache[p]
          if a and players[a] then apply_play_fx(cc, a) end
        end
      end
    end
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, T('мастер-BPM'))
    end
    ImGui.SameLine(ctx)
    if chip('sync###bsync', state.bpm_sync, 0x7FD98AFF) then
      state.bpm_sync = not state.bpm_sync
      for p, cc in pairs(state.index.projects) do
        local a = audio_cache[p]
        if a and players[a] then
          if state.bpm_sync then
            apply_play_fx(cc, a)
          else
            reaper.CF_Preview_SetValue(players[a], 'D_PLAYRATE', 1)
          end
        end
      end
    end
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        T('подгонять темп играющих под мастер-BPM (питч сохраняется)'))
    end
    ImGui.SameLine(ctx)
    if chip(T('повтор') .. '###pqrep', state.playq_rep, 0x7BB8D9FF) then
      state.playq_rep = not state.playq_rep
      if playlist then playlist.rep = state.playq_rep end
    end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, T('в проект') .. '###pqexp') then
      -- десерт: плейлист → новый проект последовательными сабпроектами
      state.basket = {}
      for _, el in ipairs(q) do
        local c = el.card
        if c and not c.daw then
          local off = c.pv_offset or 0
          if el.a then
            state.basket[#state.basket + 1] = { path = c.path,
              region = { pos = el.a + off, fin = el.b + off,
                name = c.name .. ' loop' .. (el.li or 0) } }
          elseif (c.duration or 0) > 0 then
            state.basket[#state.basket + 1] = { path = c.path,
              region = { pos = 0, fin = c.duration, name = c.name } }
          end
        end
      end
      if #state.basket > 0 then
        basket_build()
      else
        logf('warn', T('в плейлисте нечего экспортировать'))
      end
    end
    ImGui.Separator(ctx)
    for qi, el in ipairs(q) do
      local active = playlist and playlist.queue[playlist.i]
        and playlist.queue[playlist.i].audio == el.audio
        and playlist.queue[playlist.i].a == el.a
      if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right)
         and ImGui.IsItemHovered(ctx) and #state.playq > 0 then
        for k, pp in ipairs(state.playq) do
          if el.card and pp == el.card.path then
            table.remove(state.playq, k)
            break
          end
        end
      end
      if ImGui.Selectable(ctx, string.format('%2d %s###pq%d', qi,
          el.label, qi), active) then
        -- клик — играть элемент параллельно (лупы крутятся дальше)
        preview_play(el.audio, true)
        apply_play_fx(el.card, el.audio)
        if players[el.audio] then
          if el.a then
            reaper.CF_Preview_SetValue(players[el.audio], 'D_POSITION', el.a)
            loop_bounds[el.audio] = { a = el.a, b = el.b }
          else
            loop_bounds[el.audio] = nil
          end
        end
      end
    end
    if #q == 0 then
      ImGui.TextDisabled(ctx, T('перетащи сюда карточки'))
    end
    ImGui.EndChild(ctx)
  end
  -- drop-зона: карточка из сетки → в плейлист
  if ImGui.BeginDragDropTarget(ctx) then
    local ok, payload = ImGui.AcceptDragDropPayload(ctx, 'JF_PM_CARD')
    if ok and payload then
      local dup = false
      for _, p in ipairs(state.playq) do
        if p == payload then dup = true break end
      end
      if not dup then
        state.playq[#state.playq + 1] = payload
        logf('act', T('в плейлист: ') ..
          (state.index.projects[payload] or {}).name or payload)
      end
    end
    ImGui.EndDragDropTarget(ctx)
  end
end

-- Боковая панель тегов: справа от сетки. Клик — фильтр (AND по нескольким),
-- повторный — снять. Раньше теги жили в тулбаре и съедали верх.
local TAGS_W = 132
local function draw_tags_panel(h)
  if ImGui.BeginChild(ctx, '##tagspanel', TAGS_W, h,
      ImGui.ChildFlags_Border) then
    ImGui.TextDisabled(ctx, T('теги'))
    if next(state.filter_tags) then
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, '×###tagsclear') then
        state.filter_tags = {}
      end
    end
    if not state.tags_all_cache or state.tags_all_gen ~= data_gen then
      local seen, tags_all = {}, {}
      for _, e in ipairs(TAGS) do
        seen[e[1]] = true; tags_all[#tags_all + 1] = e[1]
      end
      for _, card in pairs(state.index.projects) do
        for _, t in ipairs(all_tags(card, cached_meta(card))) do
          if not seen[t] then seen[t] = true; tags_all[#tags_all + 1] = t end
        end
      end
      table.sort(tags_all)
      state.tags_all_cache, state.tags_all_gen = tags_all, data_gen
    end
    for _, t in ipairs(state.tags_all_cache) do
      local active = state.filter_tags[t]
      if chip('#' .. t .. '###stag' .. t, active, tag_color(t)) then
        state.filter_tags[t] = not active or nil
      end
    end
    ImGui.EndChild(ctx)
  end
end

local function draw_toolbar()
  if ImGui.Button(ctx, state.rescan
      and string.format('Rescan %d/%d ■', state.rescan.i, state.rescan.total)
      or 'Rescan') then
    rescan()
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, T('настройки')) then
    state.show_settings = not state.show_settings
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, T('галерея')) then export_gallery() end
  ImGui.SameLine(ctx)
  if chip('playlist' .. (#state.playq > 0 and
      (' ' .. #state.playq) or '') .. '###pqtoggle',
      state.show_playq, 0x7FD98AFF) then
    state.show_playq = not state.show_playq
  end
  if state.btn_tips and ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, T('панель плейлиста: перетащи карточки, sync play'))
  end
  -- громкость превью (слайдер — согласованное исключение, как выпадашка)
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 90)
  local vchg, nv = ImGui.SliderDouble(ctx, '###pvol', state.preview_vol,
    0.0, 1.0, 'vol %.2f')
  if vchg then
    state.preview_vol = nv
    for _, c in pairs(players) do
      reaper.CF_Preview_SetValue(c, 'D_VOLUME', nv)
    end
  end
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then
    core.set_setting('preview_vol', string.format('%.3f', state.preview_vol))
  end
  -- поиск — на самом верху, всегда под рукой (клавиша /)
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 260)
  if state.focus_tag_input then
    ImGui.SetKeyboardFocusHere(ctx)
    state.focus_tag_input = false
  end
  local schanged, sval = ImGui.InputTextWithHint(ctx, '##tag',
    T('fzf: всё — имя, треки, регионы, отчёты… ( / )'), state.filter_text)
  if schanged then state.filter_text = sval end

  -- WIP-счётчик: >3 в активной работе — многовато; кэш по поколению
  if not state.wip_cache or state.wip_gen ~= data_gen then
    local wip, no_report = 0, 0
    for _, card in pairs(state.index.projects) do
      local s = (card.ext or {}).STATUS or ''
      s = core.STATUS_ALIASES[s] or s
      if s == 'аранжировка' or s == 'микс' or s == 'мастер' then
        wip = wip + 1
      end
      if card.needs_report then no_report = no_report + 1 end
    end
    state.wip_cache, state.wip_gen = { wip = wip, nr = no_report }, data_gen
  end
  local wip, no_report = state.wip_cache.wip, state.wip_cache.nr
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
  if chip('∅ ' .. T('пустые') .. '###fempty', state.filter_empty) then
    state.filter_empty = not state.filter_empty
  end
  ImGui.SameLine(ctx)
  if chip('⧉ ' .. T('дубли') .. '###fdups', state.filter_dups, 0xE06060FF) then
    state.filter_dups = not state.filter_dups
  end
  -- корзина: счётчик и вход
  local ntrash = 0
  for _, c in pairs(state.index.projects) do
    if c.trashed then ntrash = ntrash + 1 end
  end
  if ntrash > 0 or state.filter_trash then
    ImGui.SameLine(ctx)
    if chip('🗑 ' .. T('корзина') .. ' ' .. ntrash .. '###ftrash',
        state.filter_trash, 0xE06060FF) then
      state.filter_trash = not state.filter_trash
      state.filter_dups, state.filter_empty = false, false
    end
    if state.filter_trash then
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, T('вернуть все') .. '###trestore') then
        for _, c in pairs(state.index.projects) do c.trashed = nil end
        save_index_soon()
        logf('undo', T('корзина очищена — всё возвращено'))
      end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, T('удалить просроченные') .. '###tsweep') then
        trash_sweep(true)
      end
    end
  end
  if state.btn_tips and ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, T('проекты с похожими именами (версии, копии)'))
  end
  for _, cat in ipairs({ 'семпл', 'скетч', 'джем', 'аранжировка', 'тест' }) do
    ImGui.SameLine(ctx)
    if chip('~' .. cat .. '###fcat' .. cat, state.filter_cat == cat,
        CAT_COLORS[cat]) then
      state.filter_cat = state.filter_cat ~= cat and cat or nil
    end
  end
  -- чипы DAW: появляются, когда в индексе есть чужие проекты (кэш)
  if not state.daws_cache or state.daws_gen ~= data_gen then
    local daws = {}
    for _, card in pairs(state.index.projects) do
      if card.daw and not daws[card.daw] then
        daws[card.daw] = core.DAW_TYPES[card.daw_ext] or {}
      end
    end
    state.daws_cache, state.daws_gen = daws, data_gen
  end
  local daws = state.daws_cache
  if next(daws) then
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, '|')
    ImGui.SameLine(ctx)
    if chip('Rp###fdaw_rp', state.filter_daw == 'reaper', 0x7BB8D9FF) then
      state.filter_daw = state.filter_daw ~= 'reaper' and 'reaper' or nil
    end
    for daw, dt in pairs(daws) do
      ImGui.SameLine(ctx)
      if chip((dt.label or daw) .. '###fdaw_' .. daw,
          state.filter_daw == daw, dt.color) then
        state.filter_daw = state.filter_daw ~= daw and daw or nil
      end
    end
  end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  for i, s in ipairs(core.STATUSES) do
    ImGui.SameLine(ctx)
    if chip(status_label(s) .. '###fst' .. i, state.filter_status == i + 2,
        core.STATUS_COLORS[s]) then
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
    if chip(label .. '###sort' .. i, active, 0xD9B96CFF) then
      if active then
        state.sort_rev = not state.sort_rev
      else
        state.sort_mode = i
        state.sort_rev = false
      end
    end
  end

  -- размер карточек: S иконки · M обычные · L всё развёрнуто
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '|')
  for ci2, cs2 in ipairs(CARD_SIZES) do
    ImGui.SameLine(ctx)
    if chip(cs2.label .. '###csize' .. ci2, state.card_size == ci2,
        0x7BB8D9FF) then
      state.card_size = ci2
      core.set_setting('card_size', tostring(ci2))
    end
  end



  -- блок выборки: порядок номеров = порядок склейки; при нескольких
  -- выделенных — те же команды, что на карточке, но на всю выборку
  if #state.sel > 0 then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0xD9B96CFF, string.format(T('выбрано: %d'), #state.sel))
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, T('на расслоение') .. '###selharv') then
      for _, p in ipairs(state.sel) do
        local card = state.index.projects[p]
        if card then set_status(card, 'на расслоение') end
      end
      logf('act', string.format(T('На расслоение: %d'), #state.sel))
    end
    if #state.sel >= 2 then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, 'merge') then merge_selected() end
      ImGui.SameLine(ctx)
      -- сабпроектами: исходники не трогаются — ГЛАВНАЯ функция, ярче
      ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xD9B96CFF)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xE8CD8AFF)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xC9A95CFF)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x111213FF)
      local msub = ImGui.Button(ctx, '⧉ merge as subs')
      ImGui.PopStyleColor(ctx, 4)
      if msub then merge_as_subprojects(nil) end
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
    if view_tab(T(label) .. '###view' .. i, state.view == i - 1,
        VIEW_COLORS[i] or 0x7BB8D9FF) then
      state.view = i - 1
      state.focus = 0
      state.cal_scroll_end = 2
    end
  end

  -- мини-плейлист выбранных: сешн-грид, как клипы в Ableton.
  -- Клик по ячейке — играть параллельно; ▶▶ — цепочкой; ■ — стоп.
  if #state.sel > 0 then
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '▶ ' .. T('все') .. '###playall') then
      for _, p in ipairs(state.sel) do
        local c = state.index.projects[p]
        local a = c and find_preview_audio(c)
        if a then preview_play(a, true) end
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '▶▶###playseq') then
      local q = {}
      for _, p in ipairs(state.sel) do
        local c = state.index.projects[p]
        local a = c and find_preview_audio(c)
        if a then q[#q + 1] = { audio = a } end
      end
      if #q > 0 then
        playlist = { queue = q, i = 1, started = false }
      end
    end
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, T('играть выбранные по очереди'))
    end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '■###selstop') then preview_stop() end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, T('найти превью') .. '###findprev') then
      findprev_start()
    end
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        T('обновить превью выделенных; нет файла — Spotlight по всему диску'))
    end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, T('собрать из лупов') .. '###loopbuild') then
      -- лупы выбранных → корзина сабпроектов → новый проект (basket_build):
      -- каждый луп — открываемый subproject-айтем с обрезкой по лупу
      state.basket = {}
      for _, p in ipairs(state.sel) do
        local c = state.index.projects[p]
        if c and not c.daw then
          local off = c.pv_offset or 0
          for li, lp in ipairs(c.loops or {}) do
            state.basket[#state.basket + 1] = {
              path = p,
              region = { pos = lp.a + off, fin = lp.b + off,
                name = c.name .. ' loop' .. li },
            }
          end
        end
      end
      if #state.basket == 0 then
        logf('warn', T('у выбранных нет лупов (плеер → драг по волне → + луп)'))
      else
        basket_build()
      end
    end
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        T('новый проект: каждый луп — сабпроджект-айтем, порядок = выборка'))
    end

  end



end

-- ---------------------------------------------------------------------------
-- Vim-навигация

-- Хинты (как Surfingkeys): f — метки на видимых карточках; буквы — прыжок
-- фокуса; Shift+метка — выделить и остаться в режиме (карточка попадает
-- в стек плееров), Esc — выход.
local HINT_KEYS = 'asdfghjkl'
local function hints_start(cards)
  local first = state.vis_first or 1
  local last = math.min(state.vis_last or #cards, #cards)
  local n = last - first + 1
  if n <= 0 then return end
  local labels = {}
  local K = #HINT_KEYS
  for idx = 0, n - 1 do
    local i = first + idx
    if n <= K then
      labels[i] = HINT_KEYS:sub(idx + 1, idx + 1)
    else
      local a = math.floor(idx / K) + 1
      local b2 = (idx % K) + 1
      labels[i] = HINT_KEYS:sub(a, a) .. HINT_KEYS:sub(b2, b2)
    end
  end
  state.hints = { labels = labels, buf = '' }
end

local function hints_input(cards)
  local h = state.hints
  if not h then return false end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    state.hints = nil
    return true
  end
  local shift = ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift ~= 0
  for k = 1, #HINT_KEYS do
    local ch = HINT_KEYS:sub(k, k)
    -- Key_A..Key_Z в ImGui идут подряд
    local keycode = ImGui.Key_A + (ch:byte() - string.byte('a'))
    if ImGui.IsKeyPressed(ctx, keycode) then
      h.buf = h.buf .. ch
      -- полное совпадение?
      local hit
      for i, lbl in pairs(h.labels) do
        if lbl == h.buf then hit = i break end
      end
      if hit then
        if shift then
          -- выделить и остаться: собираем несколько в стек плееров
          toggle_select(cards[hit].card.path)
          state.focus = hit
          h.buf = ''
        else
          state.focus = hit
          state.scroll_to_focus = true
          state.hints = nil
        end
        return true
      end
      -- нет метки с таким префиксом — сброс набора
      local prefix = false
      for _, lbl in pairs(h.labels) do
        if lbl:sub(1, #h.buf) == h.buf then prefix = true break end
      end
      if not prefix then h.buf = '' end
      return true
    end
  end
  return true -- в хинт-режиме остальные клавиши глотаем
end

local function handle_keys(cards, cols)
  if ImGui.IsAnyItemActive(ctx) then return end -- набор текста в поле
  if not ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) then
    return
  end
  if hints_input(cards) then return end
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
  -- Cmd/Ctrl+Z — отмена последнего обратимого действия
  local mods = ImGui.GetKeyMods(ctx)
  if (mods & ImGui.Mod_Super ~= 0 or mods & ImGui.Mod_Ctrl ~= 0)
     and ImGui.IsKeyPressed(ctx, ImGui.Key_Z) then
    do_undo()
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Slash) then
    state.focus_tag_input = true
  end
  if state.view == 0 and ImGui.IsKeyPressed(ctx, ImGui.Key_F) then
    hints_start(cards)
  end
  -- Ctrl/Cmd+1..5: играть луп N активного превью (фокус или первый выбранный)
  local cmods = ImGui.GetKeyMods(ctx)
  if cmods & ImGui.Mod_Ctrl ~= 0 or cmods & ImGui.Mod_Super ~= 0 then
    local target = entry and entry.card
      or (state.sel[1] and state.index.projects[state.sel[1]])
    if target and target.loops then
      for n = 1, 5 do
        if ImGui.IsKeyPressed(ctx, ImGui.Key_1 + n - 1) then
          local lp = target.loops[n]
          local audio = lp and find_preview_audio(target)
          if lp and audio then
            preview_play(audio, true)
            apply_play_fx(target, audio)
            if players[audio] then
              reaper.CF_Preview_SetValue(players[audio], 'D_POSITION', lp.a)
              loop_bounds[audio] = { a = lp.a, b = lp.b }
              logf('act', string.format('⟲%d %s', n, target.name))
            end
          end
        end
      end
    end
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

-- ---------------------------------------------------------------------------
-- Консоль: мини-bash над каталогом. Команды сцепляются через &&.
-- Работают над выборкой (sel) либо над отфильтрованными карточками.

local function con_out(fmt, ...)
  logf('cmd', fmt, ...)
end

local function con_match(pat, plain)
  -- карточки под фильтрами, отсортированные как на экране
  local cards = collect_cards()
  local out = {}
  for _, e in ipairs(cards) do
    local hay = search_text(e.card, e.meta)
    local ok
    if plain then
      ok = hay:find(ulower(pat), 1, true)
    else
      local okp, res = pcall(string.find, hay, ulower(pat))
      ok = okp and res
    end
    if ok then out[#out + 1] = e end
  end
  return out
end

local function con_selected_cards()
  local out = {}
  for _, p in ipairs(state.sel) do
    local c = state.index.projects[p]
    if c then out[#out + 1] = c end
  end
  return out
end

local CMDS
CMDS = {
  help = function()
    con_out('ls [n] · grep <pat> · fzf <text> · sel <pat>|clear · count')
    con_out('open <pat> · class <класс|-> · tag <имя|-имя> · dl <дд.мм|->')
    con_out('pin · unpin · render · demo · daw <ab|fl|rp|…> · sort <режим>')
    con_out('play [pat] · stop · seq · loop <n> · loops · goto <pat>')
    con_out('view <вид> · size s|m|l · findprev · analyze · rescan · undo')
    con_out('dups · cat <категория|off> · autoclass')
    con_out('trash [sweep|restore] — виртуальная корзина (30 дней)')
  end,
  ls = function(args)
    local n = tonumber(args) or 10
    local cards = collect_cards()
    for i = 1, math.min(n, #cards) do
      local e = cards[i]
      con_out('%2d %s  [%s]%s', i, e.card.name,
        e.meta.status ~= '' and e.meta.status or '—',
        core.card_bpm(e.card) and ('  ' .. core.card_bpm(e.card) .. 'bpm') or '')
    end
    con_out(T('всего: %d'), #cards)
  end,
  grep = function(args)
    if args == '' then con_out('grep <lua-pattern>') return end
    local hits = con_match(args, false)
    for i = 1, math.min(8, #hits) do con_out('  ' .. hits[i].card.name) end
    con_out(T('совпадений: %d'), #hits)
  end,
  fzf = function(args)
    state.filter_text = args
    con_out(T('фильтр: «%s», карточек: %d'), args, #collect_cards())
  end,
  count = function()
    con_out(T('карточек: %d, выбрано: %d'), #collect_cards(), #state.sel)
  end,
  sel = function(args)
    if args == 'clear' or args == '' then
      state.sel = {}
      con_out(T('выборка очищена'))
      return
    end
    local hits = con_match(args, false)
    for _, e in ipairs(hits) do
      if not sel_index(e.card.path) then
        state.sel[#state.sel + 1] = e.card.path
      end
    end
    con_out(T('в выборке: %d'), #state.sel)
  end,
  clear = function()
    state.sel, state.filter_text, state.filter_daw = {}, '', nil
    state.filter_status, state.filter_empty = 0, false
    con_out(T('фильтры и выборка сброшены'))
  end,
  open = function(args)
    local hits = con_match(args, false)
    if #hits == 0 then con_out(T('не найдено')) return end
    open_project(hits[1].card.path)
    con_out(T('открываю: ') .. hits[1].card.name)
  end,
  class = function(args)
    if #state.sel == 0 then con_out(T('выборка пуста (sel <pat>)')) return end
    local cls = args == '-' and '' or args
    if cls ~= '' then
      local valid = false
      for _, s in ipairs(core.STATUSES) do if s == cls then valid = true end end
      if not valid then
        con_out(T('нет класса: ') .. cls .. ' (' ..
          table.concat(core.STATUSES, ' ') .. ')')
        return
      end
    end
    for _, c in ipairs(con_selected_cards()) do set_status(c, cls, true) end
    con_out(T('класс «%s»: %d проектов'), cls ~= '' and cls or '—', #state.sel)
  end,
  tag = function(args)
    if #state.sel == 0 then con_out(T('выборка пуста (sel <pat>)')) return end
    if args == '' then con_out('tag <имя> | tag -имя') return end
    local remove = args:sub(1, 1) == '-'
    local t = remove and args:sub(2) or args
    for _, c in ipairs(con_selected_cards()) do
      local extra = c.tags_extra or {}
      local found
      for j, x in ipairs(extra) do if x == t then found = j end end
      if remove and found then table.remove(extra, found) end
      if not remove and not found then extra[#extra + 1] = t end
      c.tags_extra = #extra > 0 and extra or nil
      search_cache[c.path] = nil
    end
    save_index_soon()
    con_out((remove and T('тег снят: ') or T('тег: ')) .. t)
  end,
  dl = function(args)
    if #state.sel == 0 then con_out(T('выборка пуста (sel <pat>)')) return end
    for _, c in ipairs(con_selected_cards()) do
      set_deadline(c, args == '-' and '' or args)
    end
  end,
  pin = function()
    for _, c in ipairs(con_selected_cards()) do
      if not c.pinned then toggle_pin(c) end
    end
  end,
  unpin = function()
    for _, c in ipairs(con_selected_cards()) do
      if c.pinned then toggle_pin(c) end
    end
  end,
  render = function()
    if #state.sel == 0 then con_out(T('выборка пуста (sel <pat>)')) return end
    local queue = {}
    for _, p in ipairs(state.sel) do
      local c = state.index.projects[p]
      if c and not c.daw then queue[#queue + 1] = p end
    end
    if #queue == 0 then con_out(T('нечего рендерить')) return end
    state.batch = { queue = queue, done = 0, total = #queue }
    con_out(T('превью-батч: %d'), #queue)
  end,
  demo = function()
    for _, c in ipairs(con_selected_cards()) do render_audio(c, 'demo') end
  end,
  daw = function(args)
    local map = { rp = 'reaper', ab = 'ableton', fl = 'flstudio',
      rn = 'renoise', pt = 'protools', lg = 'logic' }
    state.filter_daw = map[args] or (args ~= '' and args or nil)
    con_out(T('фильтр DAW: %s, карточек: %d'),
      state.filter_daw or T('все'), #collect_cards())
  end,
  sort = function(args)
    for i, s in ipairs(SORT_CHIPS) do
      if s == args or (LANG == 'en' and T(s) == args) then
        state.sort_mode = i
        con_out(T('сортировка: ') .. s)
        return
      end
    end
    con_out('sort: ' .. table.concat(SORT_CHIPS, ' '))
  end,
  rescan = function() rescan() end,
  undo = function() do_undo() end,
  play = function(args)
    local hits = args ~= '' and con_match(args, false) or nil
    local c = hits and hits[1] and hits[1].card
      or (state.sel[1] and state.index.projects[state.sel[1]])
    if not c then con_out(T('не найдено')) return end
    local a = find_preview_audio(c)
    if not a then con_out(T('нет превью')) return end
    preview_play(a, false)
    con_out('♪ ' .. c.name)
  end,
  stop = function() preview_stop() end,
  seq = function()
    local q = {}
    for _, p in ipairs(state.sel) do
      local c = state.index.projects[p]
      local a = c and find_preview_audio(c)
      if a then q[#q + 1] = { audio = a } end
    end
    if #q == 0 then con_out(T('выборка пуста (sel <pat>)')) return end
    playlist = { queue = q, i = 1, started = false }
    con_out('▶▶ ' .. #q)
  end,
  loop = function(args)
    local n = tonumber(args) or 1
    local c = state.sel[1] and state.index.projects[state.sel[1]]
    if not c and state.focus > 0 then
      local cards = collect_cards()
      c = cards[state.focus] and cards[state.focus].card
    end
    local lp = c and c.loops and c.loops[n]
    local a = c and find_preview_audio(c)
    if not (lp and a) then con_out(T('нет такого лупа')) return end
    preview_play(a, false)
    if players[a] then
      reaper.CF_Preview_SetValue(players[a], 'D_POSITION', lp.a)
      loop_bounds[a] = { a = lp.a, b = lp.b }
    end
    con_out('⟲' .. n .. ' ' .. c.name)
  end,
  loops = function()
    local c = state.sel[1] and state.index.projects[state.sel[1]]
    if not c then con_out(T('выборка пуста (sel <pat>)')) return end
    for li, lp in ipairs(c.loops or {}) do
      con_out('⟲%d %s–%s', li, fmt_duration(lp.a), fmt_duration(lp.b))
    end
    con_out(T('лупов: %d'), #(c.loops or {}))
  end,
  view = function(args)
    local map = { grid = 0, timeline = 1, calendar = 2, kanban = 3,
      ['сетка'] = 0, ['таймлайн'] = 1, ['календарь'] = 2, ['канбан'] = 3 }
    local v = map[args]
    if v then state.view = v con_out('view: ' .. args)
    else con_out('view: grid|timeline|calendar|kanban') end
  end,
  size = function(args)
    local map = { s = 1, m = 2, l = 3 }
    local v = map[args:lower()]
    if v then
      state.card_size = v
      core.set_setting('card_size', tostring(v))
      con_out('size: ' .. args:upper())
    else
      con_out('size: s|m|l')
    end
  end,
  ['goto'] = function(args)
    local hits = con_match(args, false)
    if #hits == 0 then con_out(T('не найдено')) return end
    local cards = collect_cards()
    for i, e in ipairs(cards) do
      if e.card.path == hits[1].card.path then
        state.focus = i
        state.scroll_to_focus = true
        con_out('→ ' .. e.card.name)
        return
      end
    end
  end,
  dups = function(args)
    local groups = core.duplicate_groups(state.index.projects)
    local list, tc, tv = {}, 0, 0
    for _, g in pairs(groups) do
      local r = core.classify_group(g)
      tc = tc + #r.copies
      tv = tv + #r.versions
      if #r.copies > 0 or #r.versions > 0 then
        list[#list + 1] = { r = r, n = #r.copies * 100 + #r.versions }
      end
    end
    table.sort(list, function(x, y) return x.n > y.n end)
    for i = 1, math.min(10, #list) do
      local r = list[i].r
      con_out('%s — копий %d, версий %d', trunc(r.newest.name, 26),
        #r.copies, #r.versions)
    end
    con_out(T('групп: %d · побайтных копий: %d · версий: %d'),
      #list, tc, tv)
    if args == 'copies' then
      -- список именно копий: их безопасно удалять
      for _, e in ipairs(list) do
        for _, c in ipairs(e.r.copies) do con_out('  ⧉ ' .. c.path) end
      end
    end
  end,
  cat = function(args)
    if args == '' or args == 'off' then
      state.filter_cat = nil
      con_out(T('фильтр категории снят'))
      return
    end
    state.filter_cat = args
    con_out('~%s: %d', args, #collect_cards())
  end,
  autoclass = function()
    -- принять авто-категорию для всех без класса (в выборке или везде)
    local src = {}
    if #state.sel > 0 then
      for _, p in ipairs(state.sel) do src[#src + 1] = state.index.projects[p] end
    else
      for _, e in ipairs(collect_cards()) do src[#src + 1] = e.card end
    end
    local n = 0
    for _, c in ipairs(src) do
      if c and cached_meta(c).status == '' then
        local cat = core.auto_category(c)
        if cat then set_status(c, cat, true) n = n + 1 end
      end
    end
    save_index_soon()
    con_out(T('классов проставлено: %d'), n)
  end,
  trash = function(args)
    if args == 'sweep' then
      trash_sweep(true)
    elseif args == 'restore' then
      local n = 0
      for _, c in pairs(state.index.projects) do
        if c.trashed then c.trashed = nil n = n + 1 end
      end
      save_index_soon()
      con_out(T('возвращено: %d'), n)
    else
      local n = 0
      for _, c in pairs(state.index.projects) do
        if c.trashed then
          n = n + 1
          if n <= 10 then
            con_out('🗑%2d %s', core.trash_days_left(c) or 0, c.name)
          end
        end
      end
      con_out(T('в корзине: %d'), n)
    end
  end,
  findprev = function() findprev_start() end,
  analyze = function()
    analyze_start(state.sel)
  end,
}

local function run_console(line)
  line = line:match('^%s*(.-)%s*$')
  if line == '' then return end
  logf('in', '> ' .. line)
  table.insert(state.con_hist, 1, line)
  if #state.con_hist > 50 then state.con_hist[#state.con_hist] = nil end
  for cmd in (line .. ' && '):gmatch('(.-)%s*&&%s*') do
    if cmd ~= '' then
      local name, args = cmd:match('^(%S+)%s*(.*)$')
      local fn = CMDS[name]
      if not fn then
        con_out(T('нет команды: ') .. tostring(name) .. ' (help)')
        return
      end
      local ok, err = pcall(fn, args or '')
      if not ok then
        con_out('err: ' .. tostring(err))
        return
      end
    end
  end
end

-- Нижняя консоль: лог (новые снизу), прогрессы процессов, строка ввода
-- ---------------------------------------------------------------------------
-- TODO-блок справа от консоли: собирает #todo из регионов и заметок всех
-- проектов + свободный текст пользователя. Всё живёт в одном текстовом
-- файле jf_pm_todo.txt рядом со скриптом: свои строки выше маркера,
-- собранные — ниже (перезаписываются при обновлении).

local TODO_FILE = SCRIPT_DIR .. '/jf_pm_todo.txt'
local TODO_MARK = '--- собрано из проектов ---'

local function todo_load()
  local f = io.open(TODO_FILE, 'rb')
  if not f then return '', '' end
  local all = f:read('*a')
  f:close()
  local mine, auto = all:match('^(.-)\n?' ..
    TODO_MARK:gsub('%-', '%%-') .. '\n?(.*)$')
  if not mine then return all, '' end
  return mine, auto
end

local function todo_save(mine, auto)
  local f = io.open(TODO_FILE, 'wb')
  if not f then return end
  f:write(mine:gsub('%s+$', ''), '\n\n', TODO_MARK, '\n', auto or '')
  f:close()
end

-- собрать #todo: имена регионов/маркеров + строки заметок с тегом
local function todo_collect()
  local out = {}
  for path, card in pairs(state.index.projects) do
    local hits = {}
    local function scan(text, where)
      if not text or text == '' then return end
      for line in (text .. '\n'):gmatch('(.-)\n') do
        if line:lower():find('#todo', 1, true) then
          local clean = line:gsub('#[Tt][Oo][Dd][Oo]', ''):gsub('%s+', ' ')
            :match('^%s*(.-)%s*$')
          hits[#hits + 1] = (where and (where .. ': ') or '') ..
            (clean ~= '' and clean or '(без текста)')
        end
      end
    end
    for _, r in ipairs(card.regions or {}) do
      scan(r.name, fmt_duration(r.pos))
    end
    for _, m in ipairs(card.markers or {}) do scan(m.name, fmt_duration(m.pos)) end
    scan(card.notes)
    for _, n in ipairs(card.track_notes or {}) do scan(n.s) end
    for _, n in ipairs(card.item_notes or {}) do scan(n.s) end
    if #hits > 0 then
      out[#out + 1] = { name = card.name, path = path, hits = hits }
    end
  end
  table.sort(out, function(x, y) return x.name < y.name end)
  local lines = {}
  for _, e in ipairs(out) do
    lines[#lines + 1] = '# ' .. e.name
    for _, h in ipairs(e.hits) do lines[#lines + 1] = '  - ' .. h end
  end
  return table.concat(lines, '\n'), #out
end

local TODO_W = 320
local CONSOLE_H = 158
local function draw_todo_panel()
  if not state.todo_loaded then
    state.todo_mine, state.todo_auto = todo_load()
    state.todo_loaded = true
  end
  if ImGui.BeginChild(ctx, '##todo', TODO_W, CONSOLE_H,
      ImGui.ChildFlags_Border) then
    ImGui.TextDisabled(ctx, 'TODO')
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '↻###todoscan') then
      local auto, n = todo_collect()
      state.todo_auto = auto
      todo_save(state.todo_mine or '', auto)
      logf('ok', string.format(T('#todo: %d проектов'), n))
    end
    if state.btn_tips and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, T('собрать #todo из регионов и заметок'))
    end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, T('сохранить') .. '###todosave') then
      todo_save(state.todo_mine or '', state.todo_auto or '')
      logf('ok', T('TODO сохранён'))
    end
    ImGui.SameLine(ctx)
    if chip(T('собранное') .. '###todoauto', state.todo_show_auto,
        0x7BD9D0FF) then
      state.todo_show_auto = not state.todo_show_auto
    end
    if state.todo_show_auto then
      -- собранное — только чтение, обновляется кнопкой ↻
      if ImGui.BeginChild(ctx, '##todoauto', 0, 0) then
        for line in ((state.todo_auto or '') .. '\n'):gmatch('(.-)\n') do
          if line:sub(1, 1) == '#' then
            ImGui.TextColored(ctx, 0xD9B96CFF, line)
          elseif line ~= '' then
            ImGui.TextDisabled(ctx, line)
          end
        end
        ImGui.EndChild(ctx)
      end
    else
      local chg, v = ImGui.InputTextMultiline(ctx, '##todomine',
        state.todo_mine or '', -1, -1)
      if chg then
        state.todo_mine = v
        state.todo_dirty = reaper.time_precise()
      end
      -- автосохранение через полторы секунды после последней правки
      if state.todo_dirty
         and reaper.time_precise() - state.todo_dirty > 1.5 then
        todo_save(state.todo_mine or '', state.todo_auto or '')
        state.todo_dirty = nil
      end
    end
    ImGui.EndChild(ctx)
  end
end

-- Мини-плейлист «сейчас играет»: слева внизу, половина ширины консоли.
-- Показывает всё, что звучит прямо сейчас, с прогрессом и стопом.
local NOWPLAY_W = 300
local function draw_nowplaying()
  if ImGui.BeginChild(ctx, '##nowplay', NOWPLAY_W, CONSOLE_H,
      ImGui.ChildFlags_Border) then
    local list = {}
    for a, c in pairs(players) do list[#list + 1] = { audio = a, cfp = c } end
    table.sort(list, function(x, y) return x.audio < y.audio end)
    ImGui.TextDisabled(ctx, T('играет') .. ' (' .. #list .. ')')
    if #list > 0 then
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, '■###npstop') then
        playlist = nil
        preview_stop()
      end
    end
    if playlist then
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, 0x7BB8D9FF, string.format('▶▶ %d/%d',
        playlist.i, #playlist.queue))
    end
    for _, el in ipairs(list) do
      local name = el.audio:match('([^/\\]+)%.%w+$') or el.audio
      name = name:gsub('_preview$', '')
      local ok, pos = reaper.CF_Preview_GetValue(el.cfp, 'D_POSITION')
      local lb = loop_bounds[el.audio]
      local okl, len = reaper.CF_Preview_GetValue(el.cfp, 'D_LENGTH')
      local total = (lb and lb.b) or (okl and len) or 0
      local from = (lb and lb.a) or 0
      local frac = (total > from) and
        math.min(math.max(((pos or 0) - from) / (total - from), 0), 1) or 0
      ImGui.ProgressBar(ctx, frac, -22, 0,
        trunc(name, 22) .. (lb and ' ⟲' or ''))
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, '×###np' .. el.audio) then
        preview_stop(el.audio)
      end
    end
    if #list == 0 then
      ImGui.TextDisabled(ctx, T('тишина'))
    end
    ImGui.EndChild(ctx)
  end
end

local function draw_console_bottom()
  draw_nowplaying()
  ImGui.SameLine(ctx)
  if not ImGui.BeginChild(ctx, '##consoleb', -(TODO_W + 8), CONSOLE_H,
      ImGui.ChildFlags_Border) then
    ImGui.SameLine(ctx)
    draw_todo_panel()
    return
  end
  ImGui.TextDisabled(ctx, T('консоль'))
  if #state.undo > 0 then
    ImGui.SameLine(ctx)
    if chip(T('отменить') .. ' (' .. #state.undo .. ')###undo', true,
        0x7BB8D9FF) then
      do_undo()
    end
  end
  -- процессы с прогресс-барами
  if state.rescan then
    ImGui.SameLine(ctx)
    ImGui.ProgressBar(ctx, state.rescan.i / math.max(state.rescan.total, 1),
      170, 0, string.format('rescan %d/%d', state.rescan.i, state.rescan.total))
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '■###rsstop') then state.rescan = nil end
  end
  if state.analysis then
    ImGui.SameLine(ctx)
    ImGui.ProgressBar(ctx,
      state.analysis.done / math.max(state.analysis.total, 1), 170, 0,
      string.format(T('анализ %d/%d'), state.analysis.done,
        state.analysis.total))
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '■###anstop') then state.analysis = nil end
  end
  if state.findprev then
    ImGui.SameLine(ctx)
    ImGui.ProgressBar(ctx,
      state.findprev.done / math.max(state.findprev.total, 1), 170, 0,
      string.format(T('поиск %d/%d'), state.findprev.done,
        state.findprev.total))
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '■###fpstop') then state.findprev = nil end
  end
  if state.batch then
    ImGui.SameLine(ctx)
    local d = state.batch.done + (state.batch.skipped or 0)
    ImGui.ProgressBar(ctx, d / math.max(state.batch.total, 1), 170, 0,
      string.format(T('превью %d/%d'), d, state.batch.total))
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '■###bstop') then state.batch = nil end
  end
  local nplay = 0
  for _ in pairs(players) do nplay = nplay + 1 end
  if nplay > 0 then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, 0xD9B96CFF, '♪ ' .. nplay ..
      (playlist and (' · ' .. T('цепочка') .. ' ' .. playlist.i .. '/'
        .. #playlist.queue) or ''))
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, '■###pstopall') then preview_stop() end
  end

  local input_h = ImGui.GetFrameHeightWithSpacing(ctx)
  if ImGui.BeginChild(ctx, '##clog', 0, -input_h) then
    for i = math.min(#state.log, LOG_MAX), 1, -1 do
      local e = state.log[i]
      ImGui.TextColored(ctx, LOG_COLORS[e.kind] or 0x9A9A9AFF,
        os.date('%H:%M:%S', e.t) .. '  ' .. e.msg)
    end
    if state.log_scroll then
      ImGui.SetScrollHereY(ctx, 1.0)
      state.log_scroll = false
    end
    ImGui.EndChild(ctx)
  end
  ImGui.SetNextItemWidth(ctx, -1)
  if state.con_focus then
    ImGui.SetKeyboardFocusHere(ctx)
    state.con_focus = false
  end
  local done, v = ImGui.InputTextWithHint(ctx, '###conin',
    T('команда… help — список, && — цепочка'), state.con_text,
    ImGui.InputTextFlags_EnterReturnsTrue)
  if v then state.con_text = v end
  if done then
    run_console(state.con_text)
    state.con_text = ''
    state.con_focus = true
  end
  ImGui.EndChild(ctx)
  -- TODO-блок справа от консоли, той же высоты
  ImGui.SameLine(ctx)
  draw_todo_panel()
end

local function loop()
  ImGui.PushFont(ctx, font)
  ImGui.SetNextWindowSize(ctx, 980, 660, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'JF — проекты', true)
  if visible then
    draw_toolbar()
    if state.show_settings then draw_settings() end
    ImGui.Separator(ctx)

    local cards = collect_cards()
    -- большие плееры: выбранные — стеком один над другим (совмещение
    -- лупов из разных треков), иначе — сфокусированная карточка
    if state.view == 0 then
      local want_panel = state.show_playq or #state.playq > 0
        or #state.sel > 0
      if want_panel then
        local nshow = math.max(1, math.min(#state.sel, 4))
        local stack_h = (#state.sel > 0 and nshow * 118 or 132) + 24
        draw_playq_panel(stack_h)
        ImGui.SameLine(ctx)
        ImGui.BeginGroup(ctx)
        local shown = 0
        for _, p in ipairs(state.sel) do
          local c = state.index.projects[p]
          if c then
            draw_big_player({ card = c })
            shown = shown + 1
            if shown >= 4 then break end
          end
        end
        if #state.sel > 4 then
          ImGui.TextDisabled(ctx,
            string.format(T('…ещё %d выбрано'), #state.sel - 4))
        end
        ImGui.EndGroup(ctx)
      elseif state.focus > 0 and cards[state.focus] then
        draw_big_player(cards[state.focus])
      end
    end
    local cols = 1
    -- контент в своём child: тулбар не скроллится, внизу консоль и статусбар
    local footer_h = ImGui.GetTextLineHeightWithSpacing(ctx) + 8
      + CONSOLE_H + 6
    local wflags = (state.view == 2 or state.view == 3)
      and ImGui.WindowFlags_HorizontalScrollbar or ImGui.WindowFlags_None
    if ImGui.BeginChild(ctx, '##content', 0, -footer_h,
        ImGui.ChildFlags_None, wflags) then
      if state.view == 0 then
        -- сетка слева, панель тегов справа
        if ImGui.BeginChild(ctx, '##gridwrap', -(TAGS_W + 8), 0) then
          cols = draw_grid(cards)
          ImGui.EndChild(ctx)
        end
        ImGui.SameLine(ctx)
        draw_tags_panel(0)
      elseif state.view == 1 then
        draw_timeline(cards)
      elseif state.view == 2 then
        draw_calendar(cards)
      else
        draw_kanban(cards)
      end
      handle_keys(cards, cols)
      ImGui.EndChild(ctx)
      batch_step()   -- очередь «превью всем»: один проект за кадр
      rescan_step()  -- фоновый рескан: порция карточек за кадр
      players_step()  -- очистка доигравших превью + шаг плейлиста
      findprev_step() -- поиск превью по ФС: один mdfind за кадр
      analyze_step()  -- анализ тональности/BPM порциями
      if not state.trash_swept then
        state.trash_swept = true
        trash_sweep(false) -- просроченное — в Корзину macOS, раз за сессию
      end
      flush_index()   -- отложенная запись индекса
    end

    draw_console_bottom()

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
    preview_stop()    -- не оставлять играющий плеер после закрытия окна
    flush_index(true) -- дописать индекс перед выходом
  end
end

reaper.defer(loop)
