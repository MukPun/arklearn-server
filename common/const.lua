local const = {}

const.loginState = {              -- 登录状态
    LOGIN_STATE_NONE = 0,           -- 未登录
    LOGIN_STATE_LOGINING = 1,       -- 登录中
    LOGIN_STATE_LOGIN_SUCCESS = 2,  -- 登录成功
    LOGIN_STATE_LOGIN_FAIL = 3,     -- 登录失败
}


return const