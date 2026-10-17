## 全局状态 + 本地数据库

> 
> 全局持久化数据，APP 全局共享，跨页面使用。
> 存放：

1. 本地数据库管理类：`app_database.dart`（你的 Isar/Sqflite 数据库单例）
2. 全局状态：用户登录信息、全局配置主题设置
3. 本地缓存管理（Hive / SharedPreferences 封装