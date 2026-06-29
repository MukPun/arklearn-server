local util = {}

-- 深拷，传参避免引用污染
function util.Deepcopy(object)
    -- 已经复制过的table，key为复制源table，value为复制后的table
    -- 为了防止table中的某个属性为自身时出现死循环
    -- 避免本该是同一个table的属性，在复制时变成2个不同的table(内容同，但是地址关系和原来的不一样了)
    local lookupTable = {}
    local function _copy(object)
        if type(object) ~= "table" then     -- 非table类型都直接返回
            return object
        elseif lookupTable[object] then
            return lookupTable[object]
        end

        local resTable = {}
        lookupTable[object] = resTable
        for key, value in pairs(table) do
            resTable[key] = type(value)=="table" and _copy(value) or value
        end
        -- 这里直接拿mt来用是因为一般对table操作不会很粗暴的修改mt的相关内容
        return setmetatable(resTable, getmetatable(table))
    end
    return _copy(object)
end

-- 打印 table
-- 返回字符串版本：dumpstr(table)
function util.Dumpstr(t)
    local result = {}

    local function _dump(t, space)
        space = space or ""
        for k, v in pairs(t) do
            local key = tostring(k)
            if type(v) == "table" then
                table.insert(result, space .. key .. " = {")
                _dump(v, space .. "  ")
                table.insert(result, space .. "}")
            else
                table.insert(result, space .. key .. " = " .. tostring(v))
            end
        end
    end

    _dump(t)
    return table.concat(result, "\n")
end

util.tab = {}

-- 表跟新 会修改 表a的数据
function util.tab.update(dst_tab, src_tab)
    for key, value in pairs(src_tab) do
        dst_tab[key] = value
    end
end

return util
