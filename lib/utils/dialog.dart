import 'package:flutter/scheduler.dart';

Future<void> waitForDialogDismissal() async {
  for (var i = 0; i < 8; i++) {
    await SchedulerBinding.instance.endOfFrame;
  }
}
