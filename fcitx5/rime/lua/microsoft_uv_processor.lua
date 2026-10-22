-- v 以及 v 后只有数字、小数点和运算符时，用字母选当前页上真实存在的候选。
-- 数字和 + * / ( ) 写入编码。小键盘的 - . 也写入编码。
-- 有候选时，- = ，。 翻页，【】 移动候选，与普通模式一致，不写进编码。
-- 其它按键（不是数字、运算符，也不是当前候选对应的字母）退出字母选词，
-- 恢复数字选词；这个键交给后面的普通输入处理。
-- uu 符号里，数字只有在能延长一条真实编码时才继续输入（uu1 → uu10）；
-- 其余数字是当前页的候选选择键。
local LETTERS = "abcdefghijklmnopqrstuvwxyz"
local DIGITS = "123456789"
-- 与 rime_ice.custom.yaml 里 calculator 的字符集保持一致（v 单独出现时不算公式）。
local V_SELECT = "^v[0-9.()+*/=-]*$"

local function log_line(msg)
  local f = io.open("/tmp/uv-label.log", "a")
  if f then
    f:write(msg, "\n")
    f:close()
  end
end

local function page_size_of(env)
  local n = 7
  local ok, value = pcall(function()
    return env.engine.schema.page_size
  end)
  if ok and type(value) == "number" and value > 0 and value <= 9 then
    n = value
  end
  return n
end

local function set_labels(env, letters)
  local config = env.engine.schema.config
  local n = page_size_of(env)
  for i = 1, n do
    local ch = letters:sub(i, i)
    local path = "menu/alternative_select_labels/@" .. tostring(i - 1)
    local ok, err = config:set_string(path, ch)
    if not ok then
      log_line("set_string failed " .. path .. " " .. tostring(err))
    end
  end
  local size = config:get_list_size("menu/alternative_select_labels")
  log_line("labels=" .. letters:sub(1, n) .. " size=" .. tostring(size) .. " page=" .. tostring(n))
end

local function apply_labels(env, enabled)
  if env.letter_labels == enabled then
    return
  end
  local ok, err = pcall(set_labels, env, enabled and LETTERS or DIGITS)
  if not ok then
    log_line("apply failed " .. tostring(err))
    return
  end
  env.letter_labels = enabled
end

local function fallback_symbol_codes()
  local codes = {}
  for i = 0, 9 do
    codes["uu" .. tostring(i)] = true
  end
  codes["uu10"] = true
  return codes
end

local function load_symbol_codes(config)
  local codes = {}
  local ok, symbols = pcall(function()
    return config:get_map("punctuator/symbols")
  end)
  if ok and symbols then
    local ok_keys, keys = pcall(function()
      return symbols:keys()
    end)
    if ok_keys and type(keys) == "table" then
      for _, key in ipairs(keys) do
        if type(key) == "string" and key:sub(1, 2) == "uu" then
          codes[key] = true
        end
      end
    end
  end
  if not next(codes) then
    codes = fallback_symbol_codes()
  end
  return codes
end

local function symbol_prefixes(env)
  if env.symbol_prefixes then
    return env.symbol_prefixes
  end
  local prefixes = {}
  local codes = load_symbol_codes(env.engine.schema.config)
  for code in pairs(codes) do
    for i = 1, #code do
      prefixes[code:sub(1, i)] = true
    end
  end
  env.symbol_prefixes = prefixes
  local count = 0
  for _ in pairs(codes) do
    count = count + 1
  end
  log_line("uu symbol codes=" .. tostring(count))
  return prefixes
end

local function select_on_page(ctx, env, index)
  local page_size = page_size_of(env)
  local page_start = 0
  local comp = ctx.composition
  if comp and not comp:empty() then
    local seg = comp:back()
    local selected = seg and seg.selected_index or 0
    page_start = math.floor(selected / page_size) * page_size
  end
  return ctx:select(page_start + index)
end

local function in_v_select_mode(input)
  return input:match(V_SELECT) ~= nil
end

local NAV = {
  BackSpace = true,
  Escape = true,
  Delete = true,
  Left = true,
  Right = true,
  Up = true,
  Down = true,
  Page_Up = true,
  Page_Down = true,
  Prior = true,
  Next = true,
  Home = true,
  End = true,
  Tab = true,
  space = true,
  Return = true,
  Shift_L = true,
  Shift_R = true,
  Control_L = true,
  Control_R = true,
  Alt_L = true,
  Alt_R = true,
  Super_L = true,
  Super_R = true,
  Caps_Lock = true,
}

-- 与 librime selector 一致：1→0 … 9→8，0→9。
local function digit_index(ch)
  local n = tonumber(ch)
  if not n then
    return nil
  end
  return (n + 9) % 10
end

-- 数字会被 recognizer 的 uu 模式吞掉。能拼出更长符号编码时继续输入，否则选词。
local function handle_uu_digit(key, env, ctx, input, repr)
  if key:release() or key:ctrl() or key:alt() or key:super() then
    return false
  end
  if not input:find("^uu") then
    return false
  end
  local digit = repr:match("^([0-9])$")
  if not digit then
    return false
  end
  local next_input = input .. digit
  if symbol_prefixes(env)[next_input] then
    return false
  end
  local index = digit_index(digit)
  local n = page_size_of(env)
  if index and index < n and ctx:has_menu() then
    select_on_page(ctx, env, index)
  end
  return true
end

-- 当前页上这个字母确实对应一个候选时，返回菜单里的绝对下标。
local function candidate_index_for_letter(ctx, env, repr)
  if #repr ~= 1 then
    return nil
  end
  local letter_index = LETTERS:find(repr, 1, true)
  if not letter_index then
    return nil
  end
  local n = page_size_of(env)
  if letter_index > n or not ctx:has_menu() then
    return nil
  end
  local page_start = 0
  local comp = ctx.composition
  local seg = nil
  if comp and not comp:empty() then
    seg = comp:back()
    local selected = seg and seg.selected_index or 0
    page_start = math.floor(selected / n) * n
  end
  local absolute = page_start + letter_index - 1
  if not seg then
    return absolute
  end
  local ok, cand = pcall(function()
    return seg:get_candidate_at(absolute)
  end)
  if not ok or cand then
    return absolute
  end
  local counted, count = pcall(function()
    local menu = seg.menu
    if not menu then
      return 0
    end
    return menu:candidate_count()
  end)
  if not counted or count == 0 then
    return absolute
  end
  return nil
end

local function labels_enabled(input, repr, key)
  if key:release() then
    return in_v_select_mode(input)
  end
  local shown = input
  if repr == "Escape" then
    shown = ""
  elseif repr == "BackSpace" then
    shown = input:sub(1, -2)
  end
  if shown == "" and input == "" and repr == "v" then
    return true
  end
  return in_v_select_mode(shown)
end

local EXTRA = {
  plus = "+",
  KP_Add = "+",
  minus = "-",
  KP_Subtract = "-",
  equal = "=",
  asterisk = "*",
  KP_Multiply = "*",
  slash = "/",
  KP_Divide = "/",
  period = ".",
  KP_Decimal = ".",
  parenleft = "(",
  parenright = ")",
}

-- 与 default.yaml 的 key_binder 一致。有候选时这些键不进入 v 编码。
local MENU_PREV_PAGE = { minus = true, comma = true }
local MENU_NEXT_PAGE = { equal = true, period = true }

local function selected_index_of(ctx)
  local comp = ctx.composition
  if not comp or comp:empty() then
    return nil
  end
  return comp:back().selected_index or 0
end

local function has_candidate_at(ctx, index)
  local comp = ctx.composition
  if not comp or comp:empty() then
    return false
  end
  local ok, cand = pcall(function()
    return comp:back():get_candidate_at(index)
  end)
  if not ok then
    return true
  end
  return cand ~= nil
end

local function move_highlight(ctx, index)
  if index < 0 then
    return
  end
  pcall(function()
    ctx:highlight(index)
  end)
end

-- 有候选时接管翻页和【】，避免被公式字符或后面的识别器吃掉。
local function handle_menu_nav(ctx, env, repr)
  if not ctx:has_menu() then
    return false
  end
  if MENU_PREV_PAGE[repr] then
    local n = page_size_of(env)
    local selected = selected_index_of(ctx)
    if selected then
      move_highlight(ctx, selected < n and 0 or selected - n)
    end
    return true
  end
  if MENU_NEXT_PAGE[repr] then
    local n = page_size_of(env)
    local selected = selected_index_of(ctx)
    if selected then
      local page_start = math.floor((selected + n) / n) * n
      if has_candidate_at(ctx, page_start) then
        move_highlight(ctx, selected + n)
      end
    end
    return true
  end
  if repr == "bracketleft" then
    local selected = selected_index_of(ctx)
    if selected and selected > 0 then
      move_highlight(ctx, selected - 1)
    end
    return true
  end
  if repr == "bracketright" then
    local selected = selected_index_of(ctx)
    if selected and has_candidate_at(ctx, selected + 1) then
      move_highlight(ctx, selected + 1)
    end
    return true
  end
  return false
end

local function processor(key, env)
  local ctx = env.engine.context
  local input = ctx.input or ""
  local repr = key:repr()

  apply_labels(env, labels_enabled(input, repr, key))

  if handle_uu_digit(key, env, ctx, input, repr) then
    return 1
  end

  if key:release() or key:ctrl() or key:alt() or key:super() then
    return 2
  end

  if in_v_select_mode(input) then
    if handle_menu_nav(ctx, env, repr) then
      return 1
    end

    local absolute = candidate_index_for_letter(ctx, env, repr)
    if absolute then
      ctx:select(absolute)
      return 1
    end

    local ch = EXTRA[repr]
    if not ch and repr:match("^[0-9]$") then
      ch = repr
    end
    if ch and ctx.push_input then
      ctx:push_input(ch)
      return 1
    end

    if not NAV[repr] then
      apply_labels(env, false)
    end
    return 2
  end

  -- 已经不是纯 v 公式。数字恢复为当前页选词，不再写进编码，字母也不再选词。
  if input:sub(1, 1) == "v" and repr:match("^[0-9]$") and ctx:has_menu() then
    local index = digit_index(repr)
    local n = page_size_of(env)
    if index and index < n then
      select_on_page(ctx, env, index)
      return 1
    end
  end

  return 2
end

return processor
