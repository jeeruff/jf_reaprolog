-- tests/test_parser.lua
-- Запуск: lua5.4 tests/test_parser.lua  (из корня репозитория)
-- Проверяет парсер .rpp, JSON и кодирование multiline без Reaper.

local core = dofile('jf_pm_core.lua')

local failed = 0
local function check(cond, msg)
  if cond then
    print('  ok    ' .. msg)
  else
    failed = failed + 1
    print('  FAIL  ' .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. ' (got ' .. tostring(a) .. ', want ' .. tostring(b) .. ')')
end

print('== tokenize_rpp_line ==')
local t = core.tokenize_rpp_line('MARKER 1 32.25 "flute loop" 1 23197940 1 B {GUID} 0')
eq(t[1], 'MARKER', 'token 1')
eq(t[4], 'flute loop', 'quoted token with space')
eq(t[5], '1', 'token after quoted')

t = core.tokenize_rpp_line("NAME 'machinedrum \"kit 12\"'")
eq(t[2], 'machinedrum "kit 12"', 'single-quote delimiter')

t = core.tokenize_rpp_line('MARKER 4 64.5 `breakdown "hart"` 1')
eq(t[4], 'breakdown "hart"', 'backtick delimiter')

t = core.tokenize_rpp_line('MARKER 5 90 drop 0')
eq(t[4], 'drop', 'unquoted name')

print('== parse_rpp ==')
local card, err = core.parse_rpp('tests/fixtures/test_project.rpp')
check(card ~= nil, 'parsed without error: ' .. tostring(err))

eq(card.tempo, 92, 'tempo')
eq(card.timesig_num, 7, 'timesig numerator')
eq(card.timesig_den, 8, 'timesig denominator')

eq(card.track_count, 4, 'track count')
eq(card.track_names[1], 'flute main', 'track 1 name')
eq(card.track_names[2], 'moog one bass', 'track 2 name')
eq(card.track_names[3], 'machinedrum "kit 12"', 'track 3 name (quotes inside)')
eq(card.track_names[4], '', 'track 4 unnamed')

eq(#card.regions, 3, 'region count')
eq(card.regions[1].name, 'intro drone', 'region 1 name')
eq(card.regions[1].pos, 0, 'region 1 start')
eq(card.regions[1].fin, 32.25, 'region 1 end (paired MARKER line)')
eq(card.regions[2].name, 'flute loop', 'region 2 name')
eq(card.regions[3].name, 'breakdown "hart"', 'region 3 name (backtick)')
eq(card.regions[3].fin, 96, 'region 3 end')

eq(#card.markers, 2, 'marker count')
eq(card.markers[1].name, 'fix breath noise', 'marker 1 name')
eq(card.markers[2].name, 'drop', 'marker 2 unquoted name')

eq(card.render_file, 'renders/nachtmusik_v3.wav', 'render file')
eq(card.render_pattern, '$project_v3', 'render pattern')

-- items: 0+32.25 и 32.25+72.5=104.75; регионы до 96 → длительность 104.75
eq(card.duration, 104.75, 'duration from items/regions')

print('== rename_project ==')
do
  -- стаб reaper.* поверх ls (как в рескан-харнессе)
  local function list(dir, want_dirs)
    local out = {}
    local p = io.popen("ls -A '" .. dir:gsub("'", "'\\''") .. "' 2>/dev/null")
    if p then
      for name in p:lines() do
        local pd = io.popen("test -d '" .. (dir .. '/' .. name):gsub("'", "'\\''")
          .. "' && echo d")
        local isdir = pd:read('*l') == 'd'
        pd:close()
        if isdir == want_dirs then out[#out + 1] = name end
      end
      p:close()
    end
    return out
  end
  _G.reaper = {
    EnumerateFiles = function(d, i) return list(d, false)[i + 1] end,
    EnumerateSubdirectories = function(d, i) return list(d, true)[i + 1] end,
  }

  local root = os.tmpname()
  os.remove(root)
  os.execute("mkdir -p '" .. root .. "/MySong/Backups'")
  local function touch(p) io.open(p, 'wb'):close() end
  touch(root .. '/MySong/MySong.rpp')
  touch(root .. '/MySong/MySong.rpp-bak')
  touch(root .. '/MySong/MySong.rpp.reapeaks')
  touch(root .. '/MySong/MySong.png')
  touch(root .. '/MySong/other.wav')
  touch(root .. '/MySong/Backups/MySong-2026-01-01.rpp-bak')

  local np, olddir = core.rename_project(root .. '/MySong/MySong.rpp', 'NewName')
  eq(np, root .. '/NewName/NewName.rpp', 'new path with renamed dir')
  eq(olddir, root .. '/MySong', 'old dir reported')
  local function exists(p)
    local f = io.open(p, 'rb')
    if f then f:close() return true end
    return false
  end
  check(exists(root .. '/NewName/NewName.rpp'), 'rpp renamed')
  check(exists(root .. '/NewName/NewName.rpp-bak'), 'bak renamed')
  check(exists(root .. '/NewName/NewName.rpp.reapeaks'), 'reapeaks renamed')
  check(exists(root .. '/NewName/NewName.png'), 'preview renamed')
  check(exists(root .. '/NewName/other.wav'), 'unrelated file untouched')
  check(exists(root .. '/NewName/Backups/NewName-2026-01-01.rpp-bak'),
    'backup in Backups/ renamed')
  check(not exists(root .. '/MySong/MySong.rpp'), 'old path gone')

  local bad = core.rename_project(root .. '/NewName/NewName.rpp', 'a/b')
  check(bad == nil, 'slash in name rejected')
  os.execute("rm -rf '" .. root .. "'")
  _G.reaper = nil
end

print('== merge_projects ==')
-- пути в индексе абсолютные — merge тоже тестируем с абсолютным
local cwd = io.popen('pwd'):read('*l')
local fixture = cwd .. '/tests/fixtures/test_project.rpp'
local merged_path = os.tmpname()
local ok, merr = core.merge_projects({ fixture, fixture }, merged_path)
check(ok, 'merge ok: ' .. tostring(merr))
local mc = core.parse_rpp(merged_path)
check(mc ~= nil, 'merged parses')
eq(mc.track_count, 8, 'merged track count doubled')
eq(#mc.items, 4, 'merged item count doubled')
eq(mc.items[3].t, 5, 'follower item on shifted track')
eq(mc.items[3].p, 104.8, 'follower item position offset (104.75 → 0.1)')
eq(mc.duration, 209.5, 'merged duration is sum')
-- 3 базовых + 3 сдвинутых + 2 региона-проекта
eq(#mc.regions, 8, 'merged regions: base + follower + per-project spans')
local mf = io.open(merged_path, 'rb')
local mtxt = mf:read('*a') mf:close()
check(mtxt:find('FILE "tests/fixtures/audio/', 1, true) == nil,
  'no relative FILE paths left')
check(mtxt:find('/tests/fixtures/audio/flute_main_take3.wav', 1, true) ~= nil,
  'FILE paths absolutized')
os.remove(merged_path)

-- карта айтемов для тамбнейла-навигатора (позиции округлены до 0.1)
eq(#card.items, 2, 'item map count')
eq(card.items[1].t, 1, 'item 1 on track 1')
eq(card.items[1].p, 0, 'item 1 position')
eq(card.items[1].l, 32.3, 'item 1 length rounded')
eq(card.items[2].t, 2, 'item 2 on track 2')
eq(card.items[2].p, 32.3, 'item 2 position rounded')

eq(card.ext.STATUS, 'в работе', 'extstate STATUS')
eq(card.ext.TAGS, 'флейта,dungeon,EP-кандидат', 'extstate TAGS')
eq(card.ext.SOMEKEY, nil, 'foreign namespace ignored')

print('== card_meta ==')
local meta = core.card_meta(card)
eq(meta.status, 'в работе', 'meta status')
eq(meta.tags[3], 'EP-кандидат', 'meta tags split')
eq(meta.report_todo, 'свести брейк\nдобавить machinedrum', 'meta todo decoded \\n')
eq(meta.report_ts, 1722340000, 'meta report_ts')

print('== multiline encode/decode ==')
local src = 'строка 1\nстрока 2 \\ backslash\nстрока 3'
eq(core.decode_ml(core.encode_ml(src)), src, 'roundtrip')
check(not core.encode_ml(src):find('\n'), 'encoded has no raw newlines')

print('== json ==')
local obj = {
  version = 1,
  projects = {
    ['/a b/проект.rpp'] = {
      name = 'проект', tempo = 92.5, needs_report = true,
      track_names = { 'flute', 'moog' },
      regions = { { name = 'intro "x"', pos = 0, fin = 32.25 } },
      empty = {},
    },
  },
}
local back = core.json_decode(core.json_encode(obj))
check(back ~= nil, 'decode ok')
local p = back.projects['/a b/проект.rpp']
eq(p.name, 'проект', 'utf-8 key/value survive')
eq(p.tempo, 92.5, 'float survives')
eq(p.needs_report, true, 'bool survives')
eq(p.track_names[2], 'moog', 'array survives')
eq(p.regions[1].name, 'intro "x"', 'escaped quote survives')

print('')
if failed > 0 then
  print(failed .. ' FAILED')
  os.exit(1)
else
  print('all tests passed')
end
