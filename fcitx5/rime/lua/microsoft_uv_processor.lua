-- v 模式用字母做候选序号。数字和运算符仍然写入编码。
local LETTERS = "abcdefghijklmnopqrstuvwxyz"
local DIGITS = "123456789"

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

local function processor(key, env)
  local ctx = env.engine.context
  local input = ctx.input or ""
  local repr = key:repr()

  local v_mode = input:sub(1, 1) == "v"
  if not v_mode and input == "" and repr == "v" then
    v_mode = true
  end
  if (repr == "BackSpace" or repr == "Escape") and (input == "v" or input == "") then
    v_mode = false
  end
  apply_labels(env, v_mode)

  if input == "" or input:sub(1, 1) ~= "v" then
    return 2
  end

  local n = page_size_of(env)
  local letter_index = nil
  if #repr == 1 then
    letter_index = LETTERS:find(repr, 1, true)
  end
  if letter_index and letter_index <= n and ctx:has_menu() then
    select_on_page(ctx, env, letter_index - 1)
    return 1
  end

  local extra = {
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
  local ch = extra[repr]
  if not ch and repr:match("^[0-9]$") then
    ch = repr
  end
  if ch and ctx.push_input then
    ctx:push_input(ch)
    return 1
  end
  return 2
end

return processor
