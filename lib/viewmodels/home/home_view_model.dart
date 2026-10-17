import 'package:app/stores/home/home_repository.dart';
import 'package:flutter/foundation.dart';

/// 首页“目标进度卡”所需的最小愿望数据。
class WishGoalProgress {
  const WishGoalProgress({
    required this.wishId,
    required this.name,
    required this.currentPoints,
    required this.requiredPoints,
  });

  final int wishId;
  final String name;
  final int currentPoints;
  final int requiredPoints;

  double get ratio =>
      requiredPoints == 0 ? 0 : (currentPoints / requiredPoints).clamp(0, 1);
  int get remaining => (requiredPoints - currentPoints).clamp(0, 1 << 31);
}

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({this._repository = const HomeRepository()});

  final HomeRepository _repository;
  List<HomeAnniversary> _anniversaries = [];
  bool _loading = false;
  Object? _error;

  List<HomeAnniversary> get anniversaries => _anniversaries;
  bool get loading => _loading;
  Object? get error => _error;

  Future<void> refreshData() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _anniversaries = await _repository.loadAnniversaries(DateTime.now());
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String get currentDate {
    final today = DateTime.now();
    return '${today.year}年${today.month.toString().padLeft(2, '0')}月'
        '${today.day.toString().padLeft(2, '0')}日';
  }
}
