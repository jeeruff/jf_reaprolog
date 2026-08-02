-- egxrkin_pm_report.lua
-- Egxrkin PM: отчёт по манифесту при закрытии проекта.
-- Вешается на Cmd+W ВМЕСТО штатного File: Close project.
--
-- Почему не custom action из двух шагов (скрипт + Close project):
-- defer-скрипт возвращает управление сразу, и Close выполнился бы до
-- появления окна. Поэтому закрытие таба делает сам скрипт (40860) после
-- записи отчёта.
--
-- Кнопки: «Сохранить и закрыть» / «Сохранить» (без закрытия) /
-- «Закрыть без отчёта» (трение: явный клик, проект пометится «без отчёта») /
-- Esc или крестик — отмена, ничего не происходит.

local SCRIPT_PATH = ({reaper.get_action_context()})[2]
local SCRIPT_DIR = SCRIPT_PATH:match('^(.*)[/\\]')
local core = dofile(SCRIPT_DIR .. '/egxrkin_pm_core.lua')

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB('Нужен ReaImGui 0.9+ (ReaPack).', 'Egxrkin PM', 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.9'

local proj, proj_fn = reaper.EnumProjects(-1)

local NS = core.NAMESPACE

local function get_ext(key)
  local _, val = reaper.GetProjExtState(proj, NS, key)
  return val or ''
end

-- предыдущий отчёт подтягивается: todo едет в поле «что надо сделать»,
-- история не теряется (REPORT_LOG только дописывается)
local prev_todo = get_ext('REPORT_TODO')
local prev_status = get_ext('STATUS')

local st = {
  status_idx = 0,
  tags = get_ext('TAGS'),
  desc = get_ext('DESC') ~= '' and core.decode_ml(get_ext('DESC')) or '',
  done = '',
  todo = prev_todo ~= '' and core.decode_ml(prev_todo) or '',
}
for i, s in ipairs(core.STATUSES) do
  if s == prev_status then st.status_idx = i end
end

local STATUS_LABELS = '(нет)\0' .. table.concat(core.STATUSES, '\0') .. '\0'

local ctx = ImGui.CreateContext('Egxrkin PM Report')
local font = ImGui.CreateFont('sans-serif', 14)
ImGui.Attach(ctx, font)

local function refresh_index_card(mark_needs_report)
  local _, fn = reaper.EnumProjects(-1) -- путь мог появиться после Save As
  if not fn or fn == '' then return end
  local idx = core.load_index()
  local card = core.build_card(fn, idx.projects[fn])
  if card then
    card.needs_report = mark_needs_report
    idx.projects[fn] = card
    core.save_index(idx)
  end
  -- маячок для watcher: это закрытие обработано, не помечать повторно
  reaper.SetExtState(core.EXT_SECTION, 'REPORT_JUST_SAVED',
    fn .. '|' .. os.time(), false)
end

local function save_report()
  local status = st.status_idx > 0 and core.STATUSES[st.status_idx] or ''
  reaper.SetProjExtState(proj, NS, 'STATUS', status)
  reaper.SetProjExtState(proj, NS, 'TAGS', st.tags)
  reaper.SetProjExtState(proj, NS, 'DESC', core.encode_ml(st.desc))
  reaper.SetProjExtState(proj, NS, 'REPORT_DONE', core.encode_ml(st.done))
  reaper.SetProjExtState(proj, NS, 'REPORT_TODO', core.encode_ml(st.todo))
  reaper.SetProjExtState(proj, NS, 'REPORT_TS', tostring(os.time()))

  local log = get_ext('REPORT_LOG')
  log = log ~= '' and core.decode_ml(log) .. '\n\n' or ''
  log = log .. os.date('== %d.%m.%Y %H:%M ==')
  if st.done ~= '' then log = log .. '\nсделано: ' .. st.done end
  if st.todo ~= '' then log = log .. '\nдальше: ' .. st.todo end
  reaper.SetProjExtState(proj, NS, 'REPORT_LOG', core.encode_ml(log))

  reaper.Main_SaveProject(proj, false)
  refresh_index_card(false)
end

local function close_tab()
  reaper.Main_OnCommand(40860, 0) -- Close current project tab
end

local done_action = nil -- 'save_close' | 'save' | 'skip' | 'cancel'

local function loop()
  ImGui.PushFont(ctx, font)
  ImGui.SetNextWindowSize(ctx, 560, 0, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Отчёт — ' ..
    (proj_fn ~= '' and proj_fn:match('([^/\\]+)%.[rR][pP][pP]$') or 'без имени'),
    true, ImGui.WindowFlags_NoCollapse)
  if visible then
    ImGui.Text(ctx, 'Что сделано:')
    local rv
    rv, st.done = ImGui.InputTextMultiline(ctx, '##done', st.done, -1, 90)

    ImGui.Text(ctx, 'Что надо сделать:')
    rv, st.todo = ImGui.InputTextMultiline(ctx, '##todo', st.todo, -1, 90)

    ImGui.SetNextItemWidth(ctx, 160)
    rv, st.status_idx = ImGui.Combo(ctx, 'статус', st.status_idx, STATUS_LABELS)
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, -1)
    rv, st.tags = ImGui.InputTextWithHint(ctx, '##tags',
      'теги через запятую (флейта, dungeon, EP-кандидат…)', st.tags)

    ImGui.SetNextItemWidth(ctx, -1)
    rv, st.desc = ImGui.InputTextWithHint(ctx, '##desc',
      'короткое описание проекта', st.desc)

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Сохранить и закрыть') then done_action = 'save_close' end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Сохранить') then done_action = 'save' end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Закрыть без отчёта') then done_action = 'skip' end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then done_action = 'cancel' end
    ImGui.End(ctx)
  end
  ImGui.PopFont(ctx)

  if not open then done_action = done_action or 'cancel' end

  if not done_action then
    reaper.defer(loop)
    return
  end
  if done_action == 'save_close' then
    save_report()
    close_tab()
  elseif done_action == 'save' then
    save_report()
  elseif done_action == 'skip' then
    -- проект не сохраняем: если есть несохранённые изменения,
    -- штатный диалог покажет само закрытие таба
    refresh_index_card(true) -- явный пропуск: проект всплывёт как «без отчёта»
    close_tab()
  end
end

reaper.defer(loop)
