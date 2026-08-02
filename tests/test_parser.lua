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
