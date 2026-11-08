-- u / v / uu 提示文案与状态判断的公共实现。
--
-- translator 用它生成候选，processor 用它判断按键该进编码还是该选词，
-- filter 用它决定候选栏是否只留提示。三处共用一份逻辑，
-- 免得文案和状态判断各写一份、慢慢走样。
--
-- 解析 symbols_v.yaml 有一定开销，结果缓存在传入的 cache 表上
-- （传 env 即可：每个 gear 的 env 在方案重新部署时会重建，不会读到旧数据）。
local M = {}

M.HINT_TYPE = "uv_hint"

local MAX_CATEGORIES = 12
local MAX_SUBMODES = 10

-- 还没进入具体模式时的总览提示。
local OVERVIEW = {
  u = "U 模式支持笔画（h横 s竖 p撇 n捺 z折 d点）、拆分（水+水+水=淼）、"
    .. "笔画拆分混合（偏旁部首笔画）、符号（uu开头）输入",
  v = "V 模式支持数字（123→一二三、壹贰叁、金额），公式（1+2→3）输入",
}

local function load_symbols(config, cache)
  local codes = {}
  local ok, symbols = pcall(function()
    return config:get_map("punctuator/symbols")
  end)
  if ok and symbols then
    local ok_keys, list = pcall(function()
      return symbols:keys()
    end)
    if ok_keys and type(list) == "table" then
      for _, key in ipairs(list) do
        if type(key) == "string" then
          codes[key] = true
        end
      end
    end
  end
  return codes
end

-- 分类清单来自 symbols_v.yaml 的 uuhelp 索引，形如 "uudw(单位)"。
local function load_categories(config)
  local rows = {}
  local ok, list = pcall(function()
    return config:get_list("punctuator/symbols/uuhelp")
  end)
  if not ok or not list then
    return rows
  end
  local size = 0
  local ok_size, n = pcall(function()
    return list.size
  end)
  if ok_size and type(n) == "number" then
    size = n
  end
  for i = 0, size - 1 do
    local ok_item, item = pcall(function()
      return list:get_value_at(i)
    end)
    if ok_item and item then
      local ok_str, text = pcall(function()
        return item.value
      end)
      if not ok_str or type(text) ~= "string" then
        ok_str, text = pcall(function()
          return item:get_string()
        end)
      end
      if ok_str and type(text) == "string" then
        local code, desc = text:match("^(.-)%((.-)%)$")
        if code and desc then
          rows[#rows + 1] = { code, desc }
        end
      end
    end
  end
  return rows
end

-- 符号表解析结果：{ codes = {编码=true}, cats = {{编码, 说明}}, desc = {编码=说明} }。
local function table_of(config, cache)
  if cache and cache.uv_symbol_table then
    return cache.uv_symbol_table
  end
  local codes = load_symbols(config, cache)
  local cats = load_categories(config)
  local desc = {}
  for _, row in ipairs(cats) do
    desc[row[1]] = row[2]
  end
  local data = { codes = codes, cats = cats, desc = desc }
  if cache then
    cache.uv_symbol_table = data
  end
  return data
end

-- 编码是不是 symbols_v.yaml 里的一个精确符号码。
function M.is_symbol_code(config, code, cache)
  return table_of(config, cache).codes[code] == true
end

-- uu 符号编码的所有前缀。处理器用它判断「再按一个数字还能不能拼出符号」。
function M.uu_prefixes(config, cache)
  local data = table_of(config, cache)
  if not data.prefixes then
    local prefixes = {}
    for code in pairs(data.codes) do
      if code:sub(1, 2) == "uu" then
        for i = 1, #code do
          prefixes[code:sub(1, i)] = true
        end
      end
    end
    data.prefixes = prefixes
  end
  return data.prefixes
end

-- 提示态：编码是 u、v、uu，或者还没拼完的 uu<字母>。
-- 已经是精确符号码就不算提示态 —— 那时该显示真实符号，而不是分类说明。
function M.is_hint_state(config, code, cache)
  if code == "u" or code == "v" or code == "uu" then
    return true
  end
  if not code:find("^uu[a-z]*$") then
    return false
  end
  return not M.is_symbol_code(config, code, cache)
end

-- 统一格式：模式码+模式名。
local function fmt(code, name)
  if name and name ~= "" then
    return code .. name
  end
  return code
end

-- 最多列 limit 项，超出时补一句「等 N 项」。
local function join(list, limit)
  if #list <= limit then
    return table.concat(list, " ")
  end
  local shown = {}
  for i = 1, limit do
    shown[i] = list[i]
  end
  return table.concat(shown, " ") .. " 等 " .. tostring(#list) .. " 项"
end

-- 还没拼完的 uu 片段：列出可能的分支。
local function category_text(code, cats, desc)
  local hit = {}
  for _, row in ipairs(cats) do
    if row[1]:sub(1, #code) == code then
      hit[#hit + 1] = fmt(row[1], desc[row[1]] or row[2])
    end
  end
  if #hit == 0 then
    return nil
  end
  return join(hit, MAX_CATEGORIES)
end

-- 精确符号码还有更长编码时，汇总这些子模式。
-- 只列在 uuhelp 索引里有说明的子模式：其余是符号表内部的键
-- （uushift、uuspace 之类），对用户没有意义。
local function sub_mode_text(code, codes, desc)
  local named = {}
  for child in pairs(codes) do
    if #child > #code and child:sub(1, #code) == code and desc[child] then
      named[#named + 1] = child
    end
  end
  if #named == 0 then
    return nil
  end
  table.sort(named)
  for i, child in ipairs(named) do
    named[i] = fmt(child, desc[child])
  end
  return join(named, MAX_SUBMODES)
end

-- 返回要显示的提示文案；不在提示范围里就返回 nil。
-- u / v 是纯字符串判断，先返回，免得为了取符号表白读一遍配置。
function M.hint_text(code, config, cache)
  local overview = OVERVIEW[code]
  if overview then
    return overview
  end
  if code:sub(1, 2) ~= "uu" then
    return nil
  end
  local data = table_of(config, cache)
  -- 已经拼出精确符号码：说明进入这个模式了，不再列分类；
  -- 但若还有更长的子模式，仍提示一下有哪些分支。
  if data.codes[code] then
    return sub_mode_text(code, data.codes, data.desc)
  end
  return category_text(code, data.cats, data.desc)
end

return M
