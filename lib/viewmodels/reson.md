## 业务模型 & 页面状态

> 
> MVVM 核心：**分离页面 UI 和业务逻辑**
> 页面（View，pages）只负责渲染 UI；业务逻辑放在 viewmodel。
> 存放：

- 每个页面单独一个 viewmodel，页面名字 + viewmodel 后缀
  - `home_viewmodel.dart` 首页业务逻辑
  - `finance_viewmodel.dart` 记账页面逻辑
- 页面数据、表单变量、加载状态、业务计算
- 调用 api 请求、数据转换，把结果暴露给页面

原则：**页面不写复杂业务逻辑，页面只监听 viewmodel 的数据变化，刷新 UI**

## 页面业务层（MVVM 的 VM）

✅ 职责：**业务逻辑 + 页面状态管理，调用 api**
viewmodel 是中间层，承上启下：

- 向上：给页面（pages）提供数据、loading 状态、错误提示
- 向下：调用`api`里面的接口函数，拿到接口返回的数据，做**业务处理**

viewmodel 做这些：

1. 标记页面`isLoading`、`errorMsg`（控制页面加载动画、错误提示）
2. 调用`TaskApi.getTaskList()`拿到接口返回数据
3. **业务计算、数据过滤、排序**（例如：筛选未完成任务、按截止时间排序）
4. 暴露可供页面监听的数据（任务列表）
5. 表单校验、业务规则判断（比如任务名称不能为空）
❌ **不做：直接写 Dio 请求代码，不要在这里写 url、请求头**