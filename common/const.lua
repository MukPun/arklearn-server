local const = {}

const.loginState = {              -- 登录状态
    LOGIN_STATE_NONE = 0,           -- 未登录
    LOGIN_STATE_LOGINING = 1,       -- 登录中
    LOGIN_STATE_LOGIN_SUCCESS = 2,  -- 登录成功
    LOGIN_STATE_LOGIN_FAIL = 3,     -- 登录失败
}

-- 服务名
const.public_server_name = {
    DB_SERVER = ".DbServer"     -- 数据库服务
}

const.BAG_TYPE = {
    BAG_TYPE_NONE = "NONE",         -- 无类型 无类型的物品背包 不展示在仓库界面 但是也需要下发给客户的
    BAG_TYPE_NORMAL = "NORMAL",     -- 基础
    BAG_TYPE_CONSUME = "CONSUME",   -- 消耗品
    BAG_TYPE_MATERIAL = "MATERIAL", -- 养成材料
}


return const