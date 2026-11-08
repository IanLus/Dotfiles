-- 候选过滤：提示态只留提示；v 纯数字去掉多余的「原样」候选。
--
-- 1. 提示态（u、v、uu、还没拼完的 uu<字母>）：候选栏只留 microsoft_uv_translator
--    生成的那一条提示，其它真实候选全部滤掉。
-- 2. v 纯数字（v123、v1.5 这类没有运算符的）：计算器会额外产出「123」和
--    「123=123」两个没有信息量的候选，这里去掉；一旦出现运算符（v12+23），
--    计算结果和算式都保留。
local hints = require("microsoft_uv_hints")

-- 只有数字和小数点，没有运算符。
local V_PLAIN_NUMBER = "^v[0-9.]+$"

-- 浮点运算会带出 1.2000000000000002 这种噪声尾数。
-- 只处理「纯小数」形式的文本，其它内容一律不动；返回整理后的字符串或 nil。
local function tidy_decimal(text)
  if type(text) ~= "string" then
    return nil
  end
  local head, frac = text:match("^(%-?%d*)%.(%d+)$")
  if not head then
    return nil
  end
  -- 最多保留 12 位有效小数，再去掉末尾多余的 0。
  if #frac > 12 then
    frac = frac:sub(1, 12)
  end
  frac = frac:gsub("0+$", "")
  local out = (head == "-" and "-0" or head) .. (frac ~= "" and ("." .. frac) or "")
  -- 浮点里的 -0.0 打印成 -0，对用户没有区别，按 0 显示。
  if out == "-0" then
    out = "0"
  end
  if out == text then
    return nil
  end
  return out
end

-- 算式结果里的噪声也要清掉：a+b=1.2000000000000002 → a+b=1.2
local function tidy_expression(text)
  if type(text) ~= "string" then
    return nil
  end
  local lhs, rhs = text:match("^(.-=)(.+)$")
  if not lhs then
    return nil
  end
  local fixed = tidy_decimal(rhs)
  if not fixed then
    return nil
  end
  return lhs .. fixed
end

-- v 纯数字里，用数字直接翻译出来的那两个候选没有意义：
--   输入 v123 时计算器给出「123」和「123=123」，前者是原样回显，后者是恒等式。
-- 注意候选里不含前导 v，所以拿去掉 v 的编码来比。
local function is_redundant_plain_number(code, cand)
  local body = code:sub(2)
  local text = cand.text
  if type(text) ~= "string" then
    return false
  end
  if text == body then
    return true
  end
  return text == body .. "=" .. body
end

-- u 模式的 affix 段（chaizi_lookup / stroke_lookup）把前缀 u 做成 phony 段，
-- phony 段在 preedit 里会被完全跳过，所以「u」+「hsh」只剩「hsh」。
-- 真实候选的 preedit 会替换整个段的显示文本，这里补回完整编码。
local function restore_prefix(cand, code)
  if code:sub(1, 1) ~= "u" or code:sub(1, 2) == "uu" then
    return
  end
  if type(cand.text) ~= "string" then
    return
  end
  pcall(function()
    cand.preedit = code
  end)
end

local function filter(input, env)
  local config = env.engine.schema.config
  local code = env.engine.context.input or ""

  if hints.is_hint_state(config, code, env) then
    local yielded = false
    for cand in input:iter() do
      if cand.type == hints.HINT_TYPE then
        yielded = true
        yield(cand)
      end
    end
    -- 退格回到提示态时提示翻译器可能没被触发（段还在 phony 状态），
    -- 这里补一条同样的提示，保证和刚输入 u 时一致。
    if not yielded then
      local text = hints.hint_text(code, config, env)
      if text then
        local filler = Candidate(hints.HINT_TYPE, 0, #code, text, "")
        filler.preedit = code
        yield(filler)
      end
    end
    return
  end

  local plain = code:match(V_PLAIN_NUMBER) ~= nil
  for cand in input:iter() do
    if plain and is_redundant_plain_number(code, cand) then
      -- 丢弃
    else
      restore_prefix(cand, code)
      local fixed = tidy_decimal(cand.text) or tidy_expression(cand.text)
      if fixed then
        pcall(function()
          cand.text = fixed
        end)
      end
      yield(cand)
    end
  end
  -- 没有真实候选时不要再补占位候选：那会让「uniform」这类词只剩一个空候选。
end

return filter
