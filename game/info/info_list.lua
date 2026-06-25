-- 导表数据加载清单
--   key   = sharedata 注册名(也是 game.info 查询用的 table_name)
--   value = { file = "<相对服务根目录的 json 路径>", root = "<可选,JSON 顶层 key>" }
--
--   root 字段:部分 json 文件顶层会包一层(比如 {"items": {...}}),
--   设置 root 后只把子表注册到 sharedata,业务层就能直接按主键查
--
-- 用法:
--   local list = require "game.info_list"
--   for name, cfg in pairs(list) do ... end

return {
    items = {
        file = "game/info/item_table.json",
        root = "items",
    },
    -- levels = {
    --     file = "game/info/level_table.json",
    --     -- root = "levels",   -- 如果 json 是数组 [[...]] 可省略
    -- },
    -- shop = {
    --     file = "game/info/shop_table.json",
    --     root = "shopList",
    -- },
}