## 公共 UI 组件（复用小组件）

> 
> 职责：**可复用的 UI 碎片，不属于某个单独页面**，所有页面都能引入使用。
> 和 pages 区分：pages 是完整大页面；components 是小组件。

存放内容：

- 通用按钮：`common_button.dart`
- 通用卡片：`common_card.dart`
- 空状态页面：`empty_widget.dart`
- 加载动画：`loading_widget.dart`
- 输入框、自定义 AppBar、分隔线、标签、弹窗组件
✅ 例子：你的 APP 多处用到的记账卡片、任务条目组件，都放这里。

> 
> ❌ 不要放：完整页面、业务逻辑、网络请求。组件只负责 UI 展示，数据由外部传入。