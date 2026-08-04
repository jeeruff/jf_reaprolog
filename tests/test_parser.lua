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

print('== notes / todos / deadline ==')
eq(card.notes, 'Ночная вещь, серия dungeon.\n- [ ] дописать интро\n- [x] выбрать темп',
  'project notes parsed')
eq(#card.track_notes, 1, 'track notes count')
eq(card.track_notes[1].t, 1, 'track note on track 1')
eq(card.track_notes[1].s, 'дубль 3 лучший, дубль 1 запасной', 'track note text')
eq(#card.item_notes, 1, 'item notes count')
eq(card.item_notes[1].t, 1, 'item note on track 1')
eq(card.item_notes[1].s, 'поправить дыхание на 1:12', 'item note text')

local nmeta = core.card_meta(card)
eq(#nmeta.todos, 2, 'todos from project notes')
eq(nmeta.todos[1].done, false, 'todo 1 open')
eq(nmeta.todos[1].text, 'дописать интро', 'todo 1 text')
eq(nmeta.todos[2].done, true, 'todo 2 done')
eq(nmeta.todos[2].src, 'notes', 'todo src')

local ts = core.parse_date('15.08.26')
local dt = os.date('*t', ts)
check(dt.day == 15 and dt.month == 8 and dt.year == 2026, 'parse_date full')
check(core.parse_date('32.01') == nil, 'parse_date bad day')
check(core.parse_date('abc') == nil, 'parse_date garbage')

print('== set_ext_in_rpp / set_project_notes ==')
do
  local tmp = os.tmpname()
  local src = io.open('tests/fixtures/test_project.rpp', 'rb'):read('*a')
  io.open(tmp, 'wb'):write(src):close()
  -- существующий ключ заменяется, новый добавляется
  assert(core.set_ext_in_rpp(tmp, 'STATUS', 'готово'))
  assert(core.set_ext_in_rpp(tmp, 'DEADLINE', '1766000000'))
  local c2 = core.parse_rpp(tmp)
  eq(c2.ext.STATUS, 'готово', 'ext key replaced')
  eq(c2.ext.DEADLINE, '1766000000', 'ext key added')
  eq(core.card_meta(c2).deadline, 1766000000, 'meta deadline')
  local _, dup = src:gsub('STATUS', '')
  local txt = io.open(tmp, 'rb'):read('*a')
  local _, dup2 = txt:gsub('\n      STATUS ', '')
  eq(dup2, 1, 'STATUS not duplicated')
  -- top-level токен: замена существующего (RENDER_1X есть в фикстуре),
  -- вставка нового, удаление
  local old1 = core.set_project_token(tmp, 'RENDER_1X', '0')
  check(old1 ~= false and old1 ~= nil, 'RENDER_1X был в фикстуре: ' .. tostring(old1))
  local old2 = core.set_project_token(tmp, 'RENDER_1X', old1)
  eq(old2, '0', 'RENDER_1X: старое значение возвращено')
  local ins = core.set_project_token(tmp, 'JF_TEST_TOKEN', '42')
  eq(ins, false, 'нового токена не было — вставлен')
  local ctok = core.parse_rpp(tmp)
  eq(ctok.track_count, 4, 'проект парсится после токенов')
  core.set_project_token(tmp, 'JF_TEST_TOKEN', nil)
  local txt_tok = io.open(tmp, 'rb'):read('*a')
  check(not txt_tok:find('JF_TEST_TOKEN', 1, true), 'токен удалён')

  -- notes: замена блока, чекбокс переключён
  assert(core.set_project_notes(tmp,
    'Ночная вещь, серия dungeon.\n- [x] дописать интро\n- [x] выбрать темп'))
  local c3 = core.parse_rpp(tmp)
  local m3 = core.card_meta(c3)
  eq(m3.todos[1].done, true, 'todo toggled via set_project_notes')
  eq(c3.track_count, 4, 'project still parses after edits')
  os.remove(tmp)
end

print('== missing_media ==')
do
  -- аудио из фикстуры не существует на диске — всё в списке пропавших
  local miss = core.missing_media('tests/fixtures/test_project.rpp')
  check(#miss >= 2, 'пропавшие найдены: ' .. #miss)
  local has_flute = false
  for _, m in ipairs(miss) do
    if m == 'flute_main_take3.wav' then has_flute = true end
  end
  check(has_flute, 'имя файла в списке')
end

print('== trim_wav_tail ==')
do
  -- синтетический WAV: 16-бит моно 8кГц, 1 c звука + 3 c нулевого хвоста
  local srate, balign = 8000, 2
  local sound = string.pack('<i2', 1000):rep(srate)
  local silence = string.rep('\0', 3 * srate * balign)
  local pcm = sound .. silence
  local fmt = string.pack('<I2I2I4I4I2I2', 1, 1, srate, srate * balign, balign, 16)
  local body = 'WAVE' .. 'fmt ' .. string.pack('<I4', #fmt) .. fmt
    .. 'data' .. string.pack('<I4', #pcm) .. pcm
  local wav_path = os.tmpname()
  local wf = io.open(wav_path, 'wb')
  wf:write('RIFF', string.pack('<I4', #body), body)
  wf:close()

  local ok2, lead_cut, tail_cut = core.trim_wav_silence(wav_path, 0.5, 1.0)
  eq(ok2, true, 'trim сработал')
  eq(lead_cut, 0.0, 'в начале тишины не было')
  eq(tail_cut, 2.0, 'отрезано 2 c (из 3 c хвоста осталась 1)')
  local sz = io.open(wav_path, 'rb'):seek('end')
  eq(sz, 44 + 2 * srate * balign, 'файл = заголовок + 2 c аудио')
  -- заголовок консистентен: data-размер совпадает с фактическим
  local rf = io.open(wav_path, 'rb')
  local all = rf:read('*a') rf:close()
  eq(string.unpack('<I4', all, 41), 2 * srate * balign, 'data-размер обновлён')
  eq(string.unpack('<I4', all, 5), #all - 8, 'RIFF-размер обновлён')
  -- повторный вызов: резать больше нечего
  eq(core.trim_wav_silence(wav_path, 0.5, 1.0), false, 'повторный trim — no-op')
  os.remove(wav_path)

  -- тишина в начале: 2 c нулей + 1 c звука + 3 c нулей → 0.5 + 1 + 1 = 2.5 c
  local pcm2 = string.rep('\0', 2 * srate * balign) .. sound .. silence
  local body2 = 'WAVE' .. 'fmt ' .. string.pack('<I4', #fmt) .. fmt
    .. 'data' .. string.pack('<I4', #pcm2) .. pcm2
  local wav2 = os.tmpname()
  local wf2 = io.open(wav2, 'wb')
  wf2:write('RIFF', string.pack('<I4', #body2), body2)
  wf2:close()
  local ok3, l3, t3 = core.trim_wav_silence(wav2, 0.5, 1.0)
  eq(ok3, true, 'trim начала сработал')
  eq(l3, 1.5, 'в начале срезано 1.5 c (осталось 0.5)')
  eq(t3, 2.0, 'в хвосте срезано 2 c')
  local sz2 = io.open(wav2, 'rb'):seek('end')
  eq(sz2, 44 + math.floor(2.5 * srate) * balign, 'файл = 2.5 c аудио')
  os.remove(wav2)
end

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
eq(meta.status, 'доделать', 'meta status (легаси «в работе» → класс)')
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
