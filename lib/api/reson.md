> 职责：统一管理后端 http 请求，**只做网络请求，不处理页面 UI**
> 存放内容：

1. 网络请求封装：`http_client.dart` / `dio_client.dart`（dio 实例、拦截器、统一错误处理）
2. 接口定义文件：按业务模块拆分
   - `task_api.dart`：任务相关接口（新增任务、查询任务）
   - `finance_api.dart`：财务记账接口
   - `user_api.dart`：用户信息接口
3. 请求参数、响应体**实体类（Request/Response Model）**


## 接口定义文件（task_api.dart/finance_api.dart）

✅ 职责：**纯粹网络请求层，只封装 HTTP 调用**
只做这些事：

1. 组装请求地址、请求头、请求参数
2. 调用 dio 发起 GET/POST 请求
3. 拿到后端返回原始 JSON，转成基础实体模型返回
4. 捕获网络层面异常（断网、404、500）
❌ **不做：业务判断、数据加工、页面 loading 状态、表单校验**
