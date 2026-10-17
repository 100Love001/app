import 'package:flutter/scheduler.dart';

/// 等待对话框退场动画结束后再继续。
/// showDialog 的 Future 在路由 pop 时即完成，而默认 150ms 退场动画
/// 仍在进行；按固定帧数等待在 120Hz 设备上会提前返回，导致随后的
/// controller.dispose() 命中仍在退场中的输入框（used after disposed）。
/// 改为按动画时长等待，适配所有刷新率。
Future<void> waitForDialogDismissal() async {
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await SchedulerBinding.instance.endOfFrame;
}
