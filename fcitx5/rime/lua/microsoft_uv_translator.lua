-- 只输入 u / v / uu 时，在候选栏给出和微软拼音相近的用法说明。
local hints = {
  u = {
    { "笔画", "h横 s竖 p撇 n捺 z折 d点。例：uhsh" },
    { "拆分", "部件拼音连写。例：uhuohuohuo、uyuxia" },
    { "笔画拆分混合", "部件拼音与笔画连写。例：uchekouhs" },
    { "符号", "uudw单位 uubd标点 uusx数学 uujh几何 uuxh星号；uuhelp 查看全部" },
  },
  uu = {
    { "uudw", "单位" },
    { "uubd", "标点" },
    { "uusx", "数学" },
    { "uujh", "几何" },
    { "uuxh", "星号" },
    { "uuszq", "圆数字、序号" },
    { "uuhelp", "全部符号分类" },
  },
  v = {
    { "数字", "v123 → 一二三、壹贰叁、金额" },
    { "公式", "v12+23 → 35，以及 12+23=35；用 a、b、c… 选择" },
  },
}

local function translator(input, seg, env)
  local rows = hints[input]
  if not rows then
    return
  end
  for _, row in ipairs(rows) do
    local cand = Candidate("uv_hint", seg.start, seg._end, row[1], row[2])
    cand.quality = 10000
    yield(cand)
  end
end

return translator
