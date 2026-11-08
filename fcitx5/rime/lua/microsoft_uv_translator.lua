-- u / v / uu 模式的用法提示，以及「同前缀子模式」汇总提示。
--
-- 文案与状态判断都在 microsoft_uv_hints.lua，这里只负责把它变成候选项。
-- 两类提示，类型都是 uv_hint：
--   1. 提示态（u、v、uu、还没拼完的 uu<字母>）：一条总览提示，候选栏只留它。
--   2. 子模式汇总（编码已是精确符号码，但还有更长的编码以它为前缀，例如 uus）：
--     一条汇总提示排在候选首位，后面跟这个精确编码的真实候选。
--     这条提示带选择标记，但不参与选词：空格/回车会提交原始编码而不是它。
local hints = require("microsoft_uv_hints")

local function translator(input, seg, env)
  local config = env.engine.schema.config
  -- u 模式的 affix 段会把前缀 u 切成 phony 段，此时 seg 只覆盖后半截，
  -- 所以整理后的编码要用 context.input，而不是函数入参。
  local code = env.engine.context.input or input
  local text = hints.hint_text(code, config, env)
  if not text then
    return
  end
  -- 跨度覆盖整个编码，否则输入框里只剩后面那截。
  local cand = Candidate(hints.HINT_TYPE, seg.start, #code, text, "")
  cand.preedit = code
  -- 子模式汇总要排在真实候选之前；普通提示态只有它一条，不需要抢位置。
  if hints.is_symbol_code(config, code, env) then
    cand.quality = 99999
  end
  yield(cand)
end

return translator
