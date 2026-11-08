-- 微软拼音式的 u / v 输入（配合 microsoft_uv_translator / microsoft_uv_filter）。
--
-- 两个阶段：
--   提示阶段——编码是 u、v、uu、或还没拼完的 uu<字母>。此时候选栏只有一行说明文字，
--     没有任何可选候选，也没有选择标记（数字/字母都不显示）。
--     字母继续进编码；空格、回车把当前编码原样上屏，绝不把提示文字写进输入框。
--   模式阶段——编码进入具体模式（uhsh 笔画、uudw 单位、v123 数字…）。
--     v 模式的数字属于编码，选词改用字母标签 a b c…；其余走正常数字选词。
--
-- 标签是在按键「生效前」写进配置的，所以要按这一步之后的编码来决定用哪种标签，
-- 否则会慢一拍（输入 v 时还在显示数字标签，v 模式却要靠字母选词）。
local hints = require("microsoft_uv_hints")

local LETTERS = "abcdefghijklmnopqrstuvwxyz"
local DIGITS = "123456789"
local NO_LABELS = " "
-- 与 rime_ice.custom.yaml 里 calculator 的字符集保持一致；单独一个 v 不算公式。
local V_SELECT = "^v[0-9.()+*/=-]+$"
-- 公式里能继续写进编码的符号。
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

-- librime-lua 暴露了全局 log，写日志用它的等级输出即可，不必自己开文件。
local function log_line(msg)
  if log and log.warning then
    log.warning("[microsoft_uv] " .. msg)
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

local function current_segment(ctx)
  local comp = ctx.composition
  if not comp or comp:empty() then
    return nil
  end
  return comp:back()
end

-- 提示阶段：候选栏只有一行说明文字，没有任何可选候选。
local function in_hint_state(env, code)
  return code ~= "" and hints.is_hint_state(env.engine.schema.config, code, env)
end

-- 这一步按键之后的编码，用来决定标签类型。
local function predicted_input(input, repr)
  if repr:match("^[%a]$") then
    -- v 模式里字母是在选词，不延长编码。
    if input:match(V_SELECT) and #input > 1 then
      return input
    end
    return input .. repr
  end
  if repr:match("^[0-9]$") or EXTRA[repr] then
    return input .. (EXTRA[repr] or repr)
  end
  if repr == "BackSpace" then
    return input:sub(1, -2)
  end
  if repr == "Escape" then
    return ""
  end
  return input
end

local function label_mode(env, code)
  if in_hint_state(env, code) then
    return "none"
  end
  if code:match(V_SELECT) and #code > 1 then
    return "letter"
  end
  return "digit"
end

-- 改的是 schema 自己的配置副本，下一次按键就生效，不用重新部署。
-- 路径里的 @N 是 0 基下标；列表短了 librime 会自动补齐。
local function set_labels(env, letters)
  local config = env.engine.schema.config
  local n = page_size_of(env)
  for i = 1, n do
    local ch = letters:sub(i, i)
    if ch == "" then
      ch = NO_LABELS
    end
    local path = "menu/alternative_select_labels/@" .. tostring(i - 1)
    local ok, err = config:set_string(path, ch)
    if not ok then
      log_line("set_string failed " .. path .. " " .. tostring(err))
    end
  end
end

local function apply_label_mode(env, mode)
  if env.label_mode == mode then
    return
  end
  local letters = DIGITS
  if mode == "letter" then
    letters = LETTERS
  elseif mode == "none" then
    letters = NO_LABELS
  end
  local ok, err = pcall(set_labels, env, letters)
  if not ok then
    log_line("apply failed " .. tostring(err))
    return
  end
  env.label_mode = mode
end

local function in_v_select_mode(input)
  return input:match(V_SELECT) ~= nil
end

local function digit_index(ch)
  local n = tonumber(ch)
  if not n then
    return nil
  end
  return (n + 9) % 10
end

local function page_start_of(seg, n)
  if not seg then
    return 0
  end
  return math.floor((seg.selected_index or 0) / n) * n
end

local function is_hint_cand(cand)
  return cand ~= nil and cand.type == hints.HINT_TYPE
end

-- 当前页上真实候选（跳过提示项）的绝对下标。
local function real_indices(ctx, env)
  local seg = current_segment(ctx)
  if not seg then
    return {}
  end
  local n = page_size_of(env)
  local page_start = page_start_of(seg, n)
  local list = {}
  for index = page_start, page_start + n - 1 do
    local ok, cand = pcall(function()
      return seg:get_candidate_at(index)
    end)
    if not ok or not cand then
      break
    end
    if not is_hint_cand(cand) then
      list[#list + 1] = index
    end
  end
  return list
end

-- 第一页页首那条候选是不是提示项（子模式汇总）。后续页没有提示项。
local function page_has_hint(ctx, env)
  local seg = current_segment(ctx)
  if not seg then
    return false
  end
  local ok, cand = pcall(function()
    return seg:get_candidate_at(page_start_of(seg, page_size_of(env)))
  end)
  return ok and is_hint_cand(cand)
end

-- 把当前编码原样上屏。
local function commit_raw_code(env, ctx)
  local text = ctx.input or ""
  if text == "" then
    return false
  end
  return pcall(function()
    env.engine:commit_text(text)
    ctx:clear()
  end)
end

-- index 是「真实候选在页内的序号」，与候选栏上的数字标签一一对应。
-- 第一页若有子模式汇总提示占着第 1 位，标签 1 指向它、标签 2 才是第一个真实候选；
-- 所以这里按提示项的有无平移一位，直接按标签取候选，才能和屏幕上的序号一致。
-- 返回 "hint" 表示这一格是提示项：由调用方改成提交原始编码。
local function select_by_label(ctx, env, index)
  local has_hint = page_has_hint(ctx, env)
  local absolute = real_indices(ctx, env)[has_hint and index or (index + 1)]
  if absolute then
    return ctx:select(absolute)
  end
  if has_hint and index == 0 then
    return "hint"
  end
  return false
end

-- 数字会被 recognizer 的 uu 模式当成编码吞掉。
-- 能拼出更长的符号编码时放行进编码（uu1 → uu10），否则当候选选择键。
local function handle_uu_digit(env, ctx, input, repr)
  if not input:find("^uu") or in_hint_state(env, input) then
    return false
  end
  local digit = repr:match("^([0-9])$")
  if not digit then
    return false
  end
  if hints.uu_prefixes(env.engine.schema.config, env)[input .. digit] then
    return false
  end
  if select_by_label(ctx, env, digit_index(digit)) == "hint" then
    commit_raw_code(env, ctx)
  end
  return true
end

local function selected_index_of(ctx)
  local seg = current_segment(ctx)
  if not seg then
    return nil
  end
  return seg.selected_index or 0
end

local function candidate_at(ctx, index)
  local seg = current_segment(ctx)
  if not seg or not index then
    return nil
  end
  local ok, cand = pcall(function()
    return seg:get_candidate_at(index)
  end)
  if ok then
    return cand
  end
  return nil
end

local function handle_letter_select(ctx, env, repr)
  if #repr ~= 1 then
    return false
  end
  local letter_index = LETTERS:find(repr, 1, true)
  if not letter_index then
    return false
  end
  local n = page_size_of(env)
  if letter_index > n or not ctx:has_menu() then
    return false
  end
  return select_by_label(ctx, env, letter_index - 1)
end

-- 选中的候选是提示（总览或子模式汇总）时，提交当前编码而不是提示文字。
-- 子模式汇总是排在真实候选首位的那一条，此时按空格/回车也应得到原始编码。
local function selected_is_hint(ctx)
  return is_hint_cand(candidate_at(ctx, selected_index_of(ctx)))
end

-- 提示阶段按空格或回车：把当前编码原样上屏。
local function commit_raw_input(env, ctx, repr)
  if repr ~= "space" and repr ~= "Return" and repr ~= "KP_Enter" then
    return false
  end
  return commit_raw_code(env, ctx)
end

local function processor(key, env)
  local ctx = env.engine.context
  local input = ctx.input or ""
  local repr = key:repr()

  -- 只处理裸键。带修饰键的是编辑/导航操作，既不延长编码也不改标签。
  if key:release() or key:ctrl() or key:alt() or key:super() then
    return 2
  end

  -- 标签必须在按键生效前写好，否则会慢一拍（输入 v 时还显示数字标签），
  -- 所以要按「这一步之后的编码」来决定用哪一种。
  apply_label_mode(env, label_mode(env, predicted_input(input, repr)))

  -- 退格回到提示态时，段仍停在 phony 前缀状态，翻译器不会重新触发，
  -- 候选栏会空着、输入框还挂着「〔偏旁〕」。清空后重放整个输入，强制重新分段。
  if repr == "BackSpace" and (ctx.input or "") ~= "" then
    local rest = input:sub(1, -2)
    if in_hint_state(env, rest) then
      ctx:clear()
      for i = 1, #rest do
        ctx:push_input(rest:sub(i, i))
      end
      return 1
    end
  end

  -- ESC：一次清空整个输入。u 模式里前缀 u 是 phony 段，
  -- librime 的 express_editor 只清最后一个段，所以自己接管。
  if repr == "Escape" and (ctx.input or "") ~= "" then
    ctx:clear()
    return 1
  end

  -- 提示阶段：字母继续进编码以收窄提示；数字只可能是想选那条提示，一律吞掉；
  -- 空格/回车提交原始编码。
  if in_hint_state(env, input) then
    -- 只有单独一个 u 时，数字没有别的含义，只是有人想选那条提示，吞掉。
    -- uu 里的数字属于符号编码（uu1 → uu10），v 里的数字进入计算模式，都放行。
    if input == "u" and repr:match("^[0-9]$") then
      return 1
    end
    -- 空格/回车把当前编码原样上屏（u、v、uu 都适用），不把提示文字写进输入框。
    if commit_raw_input(env, ctx, repr) then
      return 1
    end
    return 2
  end

  -- 子模式汇总提示排在真实候选首位时，选中它按空格/回车要提交原始编码。
  if ctx:has_menu() and selected_is_hint(ctx) and commit_raw_input(env, ctx, repr) then
    return 1
  end

  if handle_uu_digit(env, ctx, input, repr) then
    return 1
  end

  if in_v_select_mode(input) then
    -- 公式字符（- . + * / ( ) =）和数字必须先写进编码，
    -- 否则会被当成翻页键（- = , .）或选词键（数字）吃掉。
    local ch = EXTRA[repr] or (repr:match("^[0-9]$") and repr)
    if ch then
      -- 必须用冒号调用：点号会少传 self，lua 侧直接报错、按键被静默丢弃。
      ctx:push_input(ch)
      return 1
    end

    -- v 模式不翻页：逗号吞掉，避免被 key_binder 当成上一页；
    -- 【】交给 key_binder 统一处理，和普通模式走同一条路径。
    if repr == "comma" then
      return 1
    end

    if handle_letter_select(ctx, env, repr) then
      return 1
    end

    return 2
  end

  return 2
end

return processor
