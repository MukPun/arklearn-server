return {
    host = "127.0.0.1",
    port = 27017,
    username = "admin",
    password = "ark1998219",
    authdb = "admin",
    database = "arkServer",
    name = "db_proxy",
    collections = {"accounts", "players"},  -- 新增：允许访问的集合列表
}