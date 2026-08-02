-- jf_pm_harvest.lua
-- JF PM: расслоение открытого проекта.
--   Мультитреки — все треки стемами в <stems_path>/<имя проекта>/  ($track)
--   Регионы     — мастер-микс по регионам в <regions_path>/<имя проекта>/  ($region)
-- Пути задаются в настройках браузера (кнопка «пути»).
--
-- Рендер: подменяем RENDER_* через GetSetProjectInfo, рендерим действием
-- 41824 (render using the most recent settings, без диалога), возвращаем
-- настройки рендера и выделение треков как было.
-- Значения RENDER_SETTINGS: 0 = master mix, 3 = stems (selected tracks);
-- RENDER_BOUNDSFLAG: 1 = entire project, 3 = all project regions.
-- Сверено с cfillion_Apply render preset.lua; проверить на железе.

local SCRIPT_PATH = ({reaper.get_action_context()})[2]
local SCRIPT_DIR = SCRIPT_PATH:match('^(.*)[/\\]')
local core = dofile(SCRIPT_DIR .. '/jf_pm_core.lua')

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB('Нужен ReaImGui 0.9+ (ReaPack).', 'JF PM', 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.9'

local proj, proj_fn = reaper.EnumProjects(-1)
if not proj_fn or proj_fn == '' then
  reaper.MB('Проект не сохранён — сначала сохрани.', 'JF PM: расслоение', 0)
  return
end
local proj_name = proj_fn:match('([^/\\]+)%.[rR][pP][pP]$') or 'project'

local stems_path = core.get_setting('stems_path')
local regions_path = core.get_setting('regions_path')
local _, _, num_regions = reaper.CountProjectMarkers(proj)

local ctx = ImGui.CreateContext('JF PM Harvest')
local font = ImGui.CreateFont('sans-serif', 14)
ImGui.Attach(ctx, font)

local st = {
  archive_after = true,
  msg = '',
  done_any = false,
}

local function render_with(settings, bounds, file_dir, pattern)
  -- сохранить текущее
  local s0 = reaper.GetSetProjectInfo(proj, 'RENDER_SETTINGS', 0, false)
  local b0 = reaper.GetSetProjectInfo(proj, 'RENDER_BOUNDSFLAG', 0, false)
  local _, f0 = reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', '', false)
  local _, p0 = reaper.GetSetProjectInfo_String(proj, 'RENDER_PATTERN', '', false)

  reaper.GetSetProjectInfo(proj, 'RENDER_SETTINGS', settings, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_BOUNDSFLAG', bounds, true)
  reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', file_dir, true)
  reaper.GetSetProjectInfo_String(proj, 'RENDER_PATTERN', pattern, true)

  reaper.Main_OnCommand(41824, 0) -- File: Render project, using the most recent render settings

  reaper.GetSetProjectInfo(proj, 'RENDER_SETTINGS', s0, true)
  reaper.GetSetProjectInfo(proj, 'RENDER_BOUNDSFLAG', b0, true)
  reaper.GetSetProjectInfo_String(proj, 'RENDER_FILE', f0, true)
  reaper.GetSetProjectInfo_String(proj, 'RENDER_PATTERN', p0, true)
end

local function harvest_stems()
  local dir = stems_path:gsub('/+$', '') .. '/' .. proj_name
  -- stems (selected tracks) = 3: выделить все треки, потом вернуть как было
  local sel = {}
  for i = 0, reaper.CountTracks(proj) - 1 do
    local tr = reaper.GetTrack(proj, i)
    sel[i] = reaper.IsTrackSelected(tr)
    reaper.SetTrackSelected(tr, true)
  end
  render_with(3, 1, dir, '$track')
  for i = 0, reaper.CountTracks(proj) - 1 do
    reaper.SetTrackSelected(reaper.GetTrack(proj, i), sel[i])
  end
  st.msg = 'Мультитреки → ' .. dir
  st.done_any = true
end

local function harvest_regions()
  local dir = regions_path:gsub('/+$', '') .. '/' .. proj_name
  render_with(0, 3, dir, '$region')
  st.msg = 'Регионы → ' .. dir
  st.done_any = true
end

local function set_archive()
  reaper.SetProjExtState(proj, core.NAMESPACE, 'STATUS', 'архив')
  reaper.Main_SaveProject(proj, false)
  local idx = core.load_index()
  local card = core.build_card(proj_fn, idx.projects[proj_fn])
  if card then
    idx.projects[proj_fn] = card
    core.save_index(idx)
  end
end

local closing = false

local function loop()
  ImGui.PushFont(ctx, font)
  ImGui.SetNextWindowSize(ctx, 520, 0, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Расслоение — ' .. proj_name, true,
    ImGui.WindowFlags_NoCollapse)
  if visible then
    if stems_path == '' and regions_path == '' then
      ImGui.TextColored(ctx, 0xE06060FF,
        'Пути расслоения не заданы — браузер, кнопка «пути».')
    end

    if stems_path ~= '' then
      if ImGui.Button(ctx, 'Мультитреки', 160, 0) then harvest_stems() end
      ImGui.SameLine(ctx)
      ImGui.TextDisabled(ctx, stems_path .. '/' .. proj_name .. '/  ($track)')
    end

    if regions_path ~= '' then
      if num_regions > 0 then
        if ImGui.Button(ctx, 'Регионы', 160, 0) then harvest_regions() end
        ImGui.SameLine(ctx)
        ImGui.TextDisabled(ctx, regions_path .. '/' .. proj_name .. '/  ($region)')
      else
        ImGui.TextDisabled(ctx, 'Регионов в проекте нет — нечего резать.')
      end
    end

    ImGui.Separator(ctx)
    local rv
    rv, st.archive_after = ImGui.Checkbox(ctx,
      'после расслоения поставить статус «архив»', st.archive_after)

    if st.msg ~= '' then
      ImGui.TextColored(ctx, 0x7FD98AFF, st.msg)
    end

    if st.done_any then
      if ImGui.Button(ctx, 'Готово') then
        if st.archive_after then set_archive() end
        closing = true
      end
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then closing = true end
    ImGui.End(ctx)
  end
  ImGui.PopFont(ctx)
  if open and not closing then reaper.defer(loop) end
end

reaper.defer(loop)
