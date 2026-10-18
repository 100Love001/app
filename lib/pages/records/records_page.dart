import 'dart:async';
import 'dart:convert';

import 'package:app/constants/app_constants.dart';
import 'package:app/pages/anniversaries/anniversaries_page.dart';
import 'package:app/pages/records/diary_editor_page.dart';
import 'package:app/pages/records/diary_folder_management_page.dart';
import 'package:app/stores/collections/collection_repository.dart';
import 'package:app/stores/database/points_service.dart';
import 'package:app/stores/settings/app_settings_controller.dart';
import 'package:app/utils/dialog.dart';
import 'package:app/utils/folder_path.dart';
import 'package:app/utils/num_cast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// C2：cognition=认知本（原日记本），diary=新独立日记本。
enum _RecordTab { wishes, hopes, problems, cognition, diary, anniversaries }

class RecordsPage extends StatefulWidget {
  const RecordsPage({
    super.key,
    this.openDiaries = false,
    this.taskListsOnly = false,
    this.openHopes = false,
  });

  final bool openDiaries;
  final bool taskListsOnly;
  final bool openHopes;

  @override
  RecordsPageState createState() => RecordsPageState();
}

class RecordsPageState extends State<RecordsPage> {
  _RecordTab _tab = _RecordTab.wishes;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _wishes = [];
  List<Map<String, dynamic>> _hopes = [];
  List<Map<String, dynamic>> _problems = [];
  List<Map<String, dynamic>> _cognitionDiaries = [];
  List<Map<String, dynamic>> _diaryBookDiaries = [];
  List<Map<String, dynamic>> _folders = [];
  // 用户打开记录页想直接看到正在推进的事：愿望/希望默认落在“进行中”。
  String _wishFolder = '进行中';
  String _hopeFolder = '进行中';
  // 愿望/希望标签分组手风琴当前展开的分组名；null 表示全部收起。
  String? _wishExpandedGroup;
  String? _hopeExpandedGroup;
  int? _cognitionFolder;
  int? _diaryBookFolder;
  int _carouselIndex = 0;
  Timer? _carouselTimer;
  final PageController _carouselController = PageController();
  List<Map<String, dynamic>>? _inProgressWishesCache;
  List<Map<String, dynamic>>? _inProgressHopesCache;
  // 纪念日分区进入后是否自动打开添加对话框（一次性，由视图消费后复位）。
  bool _anniversariesAutoAdd = false;

  static String _bookName(String bookType) =>
      bookType == 'diary' ? '日记本' : '认知本';

  List<Map<String, dynamic>> _foldersOfBook(String bookType) =>
      _folders.where((folder) => folder['book_type'] == bookType).toList();

  List<Map<String, dynamic>> _diariesOfBook(String bookType) =>
      bookType == 'diary' ? _diaryBookDiaries : _cognitionDiaries;

  int? _selectedFolderOf(String bookType) =>
      bookType == 'diary' ? _diaryBookFolder : _cognitionFolder;

  void _setSelectedFolder(String bookType, int? folderId) {
    if (bookType == 'diary') {
      _diaryBookFolder = folderId;
    } else {
      _cognitionFolder = folderId;
    }
  }

  /// 按父子层级展开指定本子的文件夹。
  List<Map<String, dynamic>> _orderedFoldersOf(String bookType) {
    final folders = _foldersOfBook(bookType);
    final ordered = <Map<String, dynamic>>[];
    final visited = <int>{};
    void appendChildren(int? parentId) {
      for (final folder in folders) {
        if (folder['parent_id'] != parentId) continue;
        final id = folder['folder_id'] as int;
        if (!visited.add(id)) continue;
        ordered.add(folder);
        appendChildren(id);
      }
    }

    appendChildren(null);
    for (final folder in folders) {
      final id = folder['folder_id'] as int;
      if (visited.add(id)) {
        ordered.add(folder);
        appendChildren(id);
      }
    }
    return ordered;
  }

  bool _isWishInProgress(Map<String, dynamic> item) {
    final status = item['status'];
    return (toInt(item['current_points']) > 0 ||
            status == WishStatus.inProgress) &&
        status != WishStatus.readyToRedeem &&
        !WishStatus.isTerminal(status as String?);
  }

  bool _matchesFolder(Map<String, dynamic> item, bool wish, String folder) {
    final status = item['status'] as String? ?? '';
    if (wish) {
      if (folder == '未开始') {
        return toInt(item['current_points']) == 0 &&
            status != WishStatus.inProgress &&
            status != WishStatus.readyToRedeem &&
            !WishStatus.isTerminal(status);
      }
      if (folder == '进行中') return _isWishInProgress(item);
      if (folder == '待兑换') return status == WishStatus.readyToRedeem;
      if (folder == '已兑换') return WishStatus.isTerminal(status);
      return false;
    }
    return status == folder || (folder == '未进行' && status == '待完成');
  }

  @override
  void initState() {
    super.initState();
    if (widget.taskListsOnly) {
      _tab = widget.openHopes ? _RecordTab.hopes : _RecordTab.wishes;
    } else if (widget.openDiaries) {
      _tab = _RecordTab.cognition;
    } else {
      _tab = _RecordTab.problems;
    }
    _loadData();
  }

  /// 仅在当前清单的可轮播内容超过 1 页时运行定时器，
  /// 避免空耗与测试中 pumpAndSettle 永不静默。
  void _configureCarouselTimer() {
    final shouldRun =
        (_tab == _RecordTab.wishes && _inProgressWishes.length > 1) ||
        (_tab == _RecordTab.hopes && _inProgressHopes.length > 1);
    if (shouldRun && _carouselTimer != null) return;
    if (!shouldRun) {
      _carouselTimer?.cancel();
      _carouselTimer = null;
      return;
    }
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_tab != _RecordTab.wishes && _tab != _RecordTab.hopes) return;
      final count = _tab == _RecordTab.wishes
          ? _inProgressWishes.length
          : _inProgressHopes.length;
      if (count > 1 && _carouselController.hasClients) {
        final next = (_carouselIndex + 1) % count;
        _carouselController.animateToPage(
          next,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _carouselController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _inProgressWishes =>
      _inProgressWishesCache ??= _wishes.where(_isWishInProgress).toList();
  List<Map<String, dynamic>> get _inProgressHopes => _inProgressHopesCache ??=
      _hopes.where((item) => item['status'] == '进行中').toList();

  void showHopes() {
    setState(() {
      _tab = _RecordTab.hopes;
      _carouselIndex = 0;
    });
    if (_carouselController.hasClients) {
      _carouselController.jumpToPage(0);
    }
    _configureCarouselTimer();
  }

  /// 供首页纪念日入口/通知直达纪念日分区；
  /// [autoAdd] 为 true 时进入后自动打开添加对话框。
  void showAnniversaries({bool autoAdd = false}) {
    setState(() {
      _tab = _RecordTab.anniversaries;
      _carouselIndex = 0;
      _anniversariesAutoAdd = autoAdd;
    });
  }

  void refresh() => unawaited(_loadData());

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = CollectionRepository.instance;
      final result = await Future.wait([
        repo.loadWishes(),
        repo.loadHopes(),
        repo.loadProblems(),
        repo.loadDiaries(bookType: 'cognition'),
        repo.loadDiaries(bookType: 'diary'),
        repo.loadFolders(),
      ]);
      if (!mounted) return;
      setState(() {
        _inProgressWishesCache = null;
        _inProgressHopesCache = null;
        _wishes = result[0];
        _hopes = result[1];
        _problems = result[2];
        _cognitionDiaries = result[3];
        _diaryBookDiaries = result[4];
        _folders = result[5];
        for (final bookType in const ['cognition', 'diary']) {
          final selected = _selectedFolderOf(bookType);
          if (selected != null &&
              !_foldersOfBook(bookType)
                  .any((folder) => folder['folder_id'] == selected)) {
            _setSelectedFolder(bookType, null);
          }
        }
        _carouselIndex = 0;
        if (_carouselController.hasClients) {
          _carouselController.jumpToPage(0);
        }
        _loading = false;
      });
      _configureCarouselTimer();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '记录加载失败：$error';
      });
    }
  }

  Future<void> _addDesire(String type, int id) async {
    final today = _date(DateTime.now());
    try {
      await CollectionRepository.instance.addDesire(
        itemType: type,
        itemId: id,
        dateKey: today,
      );
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('增加渴望度失败：$error')));
      }
    }
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _advanceHope(Map<String, dynamic> hope) async {
    final pointsController = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('增加进度'),
        content: TextField(
          controller: pointsController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '增加的进度点数',
            suffixText: '%',
            helperText: '当前进度 ${hope['progress'] ?? 0}%',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(pointsController.text.trim());
              if (value != null && value > 0) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    pointsController.dispose();
    if (amount == null) return;
    try {
      final progress = await PointsService.advanceHope(
        hope['hope_id'] as int,
        DateTime.now(),
        amount: amount,
      );
      if (progress == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('该希望尚未开始或已经兑换')));
        }
        return;
      }
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              progress >= 100
                  ? '希望进度已满，请点击”兑换”领取奖励'
                  : '希望进度增加 $amount%，当前 $progress%',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更新希望进度失败：$error')));
      }
    }
  }

  /// D1：完成分步任务，自动刷新希望进度并发放步骤奖励。
  Future<void> _completeStep(Map<String, dynamic> step) async {
    try {
      final result = await PointsService.completeHopeStep(
        step['step_id'] as int,
        DateTime.now(),
      );
      await _loadData();
      if (mounted) {
        final message = result.stepReward != null
            ? '步骤“${step['name']}”已完成（+${result.stepReward} 积分），希望进度 ${result.progress}%'
            : '步骤“${step['name']}”已完成，希望进度 ${result.progress}%';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('完成步骤失败：$error')));
      }
    }
  }

  Future<void> _startHope(Map<String, dynamic> hope) async {
    try {
      if (!await PointsService.startHope(hope['hope_id'] as int)) {
        throw StateError('此希望已开始或已兑换');
      }
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('开始希望失败：$error')));
      }
    }
  }

  Future<void> _redeemHope(Map<String, dynamic> hope) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('兑换希望奖励'),
        content: Text(
          '“${hope['name']}”进度已满，兑换后将获得 ${hope['reward_points']} 积分。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认兑换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final reward = await PointsService.redeemHope(
        hope['hope_id'] as int,
        DateTime.now(),
      );
      if (reward == null) throw StateError('希望状态已改变，请刷新后重试');
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已兑换希望，获得 $reward 积分')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('兑换希望失败：$error')));
      }
    }
  }

  Future<void> _contributeWishPoints(Map<String, dynamic> wish) async {
    final pointsController = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('投入积分'),
        content: TextField(
          controller: pointsController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '投入积分',
            suffixText: '分',
            helperText: '10 积分 = 1 元',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(pointsController.text.trim());
              if (value != null && value > 0) {
                Navigator.pop(dialogContext, value);
              }
            },
            child: const Text('确认投入'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    pointsController.dispose();
    if (amount == null) return;
    try {
      await PointsService.contributeToWish(
        wishId: wish['wish_id'] as int,
        pointsToSpend: amount,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已投入 $amount 积分，愿望进度增加 ¥${(amount / 10).toStringAsFixed(2)}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('投入愿望积分失败：$error')));
      }
    }
  }

  Future<void> _startWish(Map<String, dynamic> wish) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('开始攒积分'),
        content: Text('确认开始“${wish['name']}”吗？开始后将移入进行中。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (!await PointsService.startWish(wish['wish_id'] as int)) {
        throw StateError('愿望已开始或状态已改变');
      }
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('开始攒积分失败：$error')));
      }
    }
  }

  Future<void> _redeemWish(Map<String, dynamic> wish) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('兑换愿望'),
        content: Text('“${wish['name']}”积分已攒满，确认兑换并完成此愿望吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('暂不兑换'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认兑换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final redeemed = await PointsService.redeemWish(
        wish['wish_id'] as int,
        DateTime.now(),
      );
      if (!redeemed) throw StateError('愿望积分尚未攒满或状态已改变');
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('愿望已兑换')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('兑换愿望失败：$error')));
      }
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item, bool wish) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('删除${wish ? '愿望' : '希望'}'),
        content: Text(
          wish && item['status'] != '已兑换'
              ? '删除“${item['name']}”后会退还已投入积分，确定继续吗？'
              : '确定删除“${item['name']}”吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (wish) {
        await PointsService.deleteWishAndRefund(item['wish_id'] as int);
      } else {
        await PointsService.deleteHope(item['hope_id'] as int);
      }
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Future<void> _addItem({
    required bool wish,
    Map<String, dynamic>? item,
  }) async {
    final tagTable = wish ? 'wish_tags' : 'hope_tags';
    List<Map<String, dynamic>> availableTags;
    try {
      availableTags = await CollectionRepository.instance.loadTags(tagTable);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取${wish ? '愿望' : '希望'}标签失败：$error')),
        );
      }
      return;
    }
    if (!mounted) return;
    final nameController = TextEditingController(
      text: item?['name'] as String? ?? '',
    );
    final contentController = TextEditingController(
      text: item?['content'] as String? ?? item?['notes'] as String? ?? '',
    );
    final requirementController = TextEditingController(
      text: item?['requirement'] as String? ?? '',
    );
    final valueController = TextEditingController(
      text: item == null
          ? ''
          : wish
          ? (toDouble(item['required_points']) / 10).toStringAsFixed(2)
          : '${item['reward_points']}',
    );
    int? selectedTagId = availableTags.isEmpty
        ? null
        : (item?['tag_id'] as int?) ?? (availableTags.first['id'] as int);
    int? dialogValue;
    String dialogName = '';
    String dialogContent = '';
    String dialogRequirement = '';
    // D1：希望分步模式。
    var hopeMode = (item?['hope_mode'] as String?) ?? 'simple';
    final stepControllers = <TextEditingController>[];
    final stepRewardControllers = <TextEditingController>[];
    if (!wish && hopeMode == 'steps') {
      try {
        final existingSteps = await CollectionRepository.instance.loadHopeSteps(
          item!['hope_id'] as int,
        );
        for (final step in existingSteps) {
          stepControllers.add(
            TextEditingController(text: step['name'] as String? ?? ''),
          );
          stepRewardControllers.add(
            TextEditingController(text: '${step['reward_points'] ?? 0}'),
          );
        }
      } catch (_) {
        // 读取失败时按无步骤处理。
      }
    }
    void disposeStepControllers() {
      for (final c in stepControllers) {
        c.dispose();
      }
      for (final c in stepRewardControllers) {
        c.dispose();
      }
    }

    if (!mounted) {
      disposeStepControllers();
      return;
    }
    try {
      dialogValue = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text('${item == null ? '新增' : '编辑'}${wish ? '愿望' : '希望'}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '名称 *'),
                  ),
                  TextField(
                    controller: contentController,
                    // 随内容自动向下增高（最小 2 行，不设上限）。
                    minLines: 2,
                    maxLines: null,
                    decoration: const InputDecoration(labelText: '内容'),
                  ),
                  TextField(
                    controller: requirementController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '要求',
                      helperText: '选填：完成该事项需满足的条件/验收标准',
                    ),
                  ),
                  if (availableTags.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue: selectedTagId,
                      decoration: const InputDecoration(labelText: '选择标签'),
                      items: [
                        for (final tag in availableTags)
                          DropdownMenuItem(
                            value: tag['id'] as int,
                            child: Text(tag['name'] as String),
                          ),
                      ],
                      onChanged: (id) =>
                          setDialogState(() => selectedTagId = id),
                    )
                  else
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('还没有标签，请先添加标签'),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final tagName = await _promptTagName(
                          wish ? '新增愿望标签' : '新增希望标签',
                        );
                        if (tagName == null || tagName.trim().isEmpty) return;
                        try {
                          final repo = CollectionRepository.instance;
                          await repo.addTag(tagTable, tagName.trim());
                          availableTags = await repo.loadTags(tagTable);
                          final match = availableTags.where(
                            (tag) => tag['name'] == tagName.trim(),
                          );
                          if (match.isNotEmpty) {
                            setDialogState(
                              () => selectedTagId = match.first['id'] as int,
                            );
                          }
                        } catch (error) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('添加标签失败：$error')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('添加标签'),
                    ),
                  ),
                  TextField(
                    controller: valueController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: wish,
                    ),
                    decoration: InputDecoration(
                      labelText: wish ? '愿望金额' : '完成奖励积分',
                      prefixText: wish ? '¥ ' : null,
                      suffixText: wish ? null : '分',
                      helperText: wish
                          ? '按 10 积分 = 1 元换算目标积分'
                          : hopeMode == 'steps'
                          ? '分步模式：全部步骤完成后一次性发放'
                          : null,
                    ),
                  ),
                  // D1：希望支持“单条进度”与“分步任务”两种模式。
                  if (!wish) ...[
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('模式'),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('单条进度'),
                          selected: hopeMode == 'simple',
                          onSelected: (_) =>
                              setDialogState(() => hopeMode = 'simple'),
                        ),
                        ChoiceChip(
                          label: const Text('分步任务'),
                          selected: hopeMode == 'steps',
                          onSelected: (_) =>
                              setDialogState(() => hopeMode = 'steps'),
                        ),
                      ],
                    ),
                    if (hopeMode == 'steps') ...[
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('步骤（完成全部步骤后希望达成）'),
                      ),
                      for (var i = 0; i < stepControllers.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: stepControllers[i],
                                  decoration: InputDecoration(
                                    labelText: '步骤 ${i + 1}',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: stepRewardControllers[i],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '奖励',
                                    suffixText: '分',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '删除步骤',
                                onPressed: () => setDialogState(() {
                                  stepControllers[i].dispose();
                                  stepRewardControllers[i].dispose();
                                  stepControllers.removeAt(i);
                                  stepRewardControllers.removeAt(i);
                                }),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setDialogState(() {
                            stepControllers.add(TextEditingController());
                            stepRewardControllers.add(
                              TextEditingController(text: '0'),
                            );
                          }),
                          icon: const Icon(Icons.add),
                          label: const Text('添加步骤'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final rawValue = double.tryParse(valueController.text.trim());
                  var value = rawValue == null || !rawValue.isFinite
                      ? null
                      : wish
                      ? (rawValue * 10).round()
                      : rawValue.toInt();
                  // 分步模式：奖励在各步骤上设置，主奖励字段可为 0。
                  final isStepsHope = !wish && hopeMode == 'steps';
                  if (isStepsHope) value ??= 0;
                  final namedSteps = stepControllers
                      .where((c) => c.text.trim().isNotEmpty)
                      .length;
                  final message = switch ((
                    nameController.text.trim().isEmpty,
                    selectedTagId == null,
                    value == null || value <= 0,
                    isStepsHope && namedSteps == 0,
                  )) {
                    (true, _, _, _) => '请填写名称',
                    (false, true, _, _) => '请选择标签',
                    (false, false, true, _) =>
                      wish ? '请输入大于 0 的愿望金额' : '请输入大于 0 的奖励积分',
                    (false, false, false, true) => '请至少添加一个步骤',
                    _ => null,
                  };
                  if (message != null) {
                    ScaffoldMessenger.of(dialogContext)
                      ..clearSnackBars()
                      ..showSnackBar(SnackBar(content: Text(message)));
                    return;
                  }
                  Navigator.pop(dialogContext, value);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      );
      dialogName = nameController.text.trim();
      dialogContent = contentController.text.trim();
      dialogRequirement = requirementController.text.trim();
      await waitForDialogDismissal();
    } finally {
      nameController.dispose();
      contentController.dispose();
      requirementController.dispose();
      valueController.dispose();
      disposeStepControllers();
    }
    if (dialogValue == null) return;
    try {
      final repo = CollectionRepository.instance;
      final values = {
        'name': dialogName,
        'content': dialogContent,
        'requirement': dialogRequirement,
        'tag_id': selectedTagId,
        if (wish) 'required_points': dialogValue,
        if (!wish) ...{'reward_points': dialogValue, 'hope_mode': hopeMode},
      };
      // D1：分步模式下，收集命名的步骤（名称+奖励）。
      final stepInputs = <({String name, int reward})>[];
      if (!wish && hopeMode == 'steps') {
        for (var i = 0; i < stepControllers.length; i++) {
          final name = stepControllers[i].text.trim();
          if (name.isEmpty) continue;
          final reward =
              int.tryParse(stepRewardControllers[i].text.trim()) ?? 0;
          stepInputs.add((name: name, reward: reward));
        }
      }
      int? hopeId;
      if (item == null) {
        if (wish) {
          await repo.saveWish(values);
        } else {
          hopeId = await repo.saveHope(values);
        }
      } else if (wish) {
        final currentPoints = toInt(item['current_points']);
        final oldStatus = item['status'] as String?;
        // 终态（已兑换/已完成）愿望只改名称/内容等字段，状态不允许被覆盖。
        final terminal = WishStatus.isTerminal(oldStatus);
        await repo.saveWish({
          ...values,
          if (!terminal)
            'status': currentPoints >= dialogValue
                ? WishStatus.readyToRedeem
                : currentPoints > 0 || oldStatus == WishStatus.inProgress
                ? WishStatus.inProgress
                : WishStatus.notStarted,
        }, id: item['wish_id'] as int);
      } else {
        hopeId = item['hope_id'] as int;
        await repo.saveHope(values, id: hopeId);
      }
      // D1：持久化分步任务。
      if (!wish && hopeId != null) {
        final oldSteps = await repo.loadHopeSteps(hopeId);
        final newNames = stepInputs.map((s) => s.name).toSet();
        // 已完成且新列表中仍存在同名步骤的，保留原记录（含完成状态），
        // 防止通过编辑保存把已领奖步骤重置后反复领奖。
        final keptCompletedNames = <String>{};
        for (final old in oldSteps) {
          final oldName = old['name'] as String;
          if (hopeMode == 'steps' &&
              old['status'] == '已完成' &&
              newNames.contains(oldName)) {
            keptCompletedNames.add(oldName);
          } else {
            await repo.deleteHopeStep(old['step_id'] as int);
          }
        }
        for (var i = 0; i < stepInputs.length; i++) {
          if (keptCompletedNames.contains(stepInputs[i].name)) continue;
          await repo.saveHopeStep({
            'hope_id': hopeId,
            'name': stepInputs[i].name,
            'reward_points': stepInputs[i].reward,
            'sort': i,
          });
        }
        // 仅分步模式按完成步骤比例重算总进度；
        // 单条模式的进度由手动推进管理，切回单条模式时保留现有进度。
        if (hopeMode == 'steps') {
          await PointsService.refreshHopeProgress(hopeId);
        }
      }
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${item == null ? '新增' : '编辑'}${wish ? '愿望' : '希望'}失败：$error',
            ),
          ),
        );
      }
    }
  }

  Future<String?> _promptTagName(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '标签名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    controller.dispose();
    return value;
  }

  Future<void> _showDetails(Map<String, dynamic> item, bool wish) async {
    final id = (wish ? item['wish_id'] : item['hope_id']) as int;
    final type = wish ? 'wish' : 'hope';
    final currentPoints = toInt(item['current_points']);
    final requiredPoints = toInt(item['required_points']);
    final wishProgress = requiredPoints == 0
        ? 0.0
        : (currentPoints * 100 / requiredPoints).clamp(0.0, 100.0);
    final hopeProgress = toDouble(item['progress']);
    final isStepsHope = !wish && item['hope_mode'] == 'steps';
    List<Map<String, dynamic>> steps = [];
    if (isStepsHope) {
      try {
        steps = await CollectionRepository.instance.loadHopeSteps(id);
      } catch (_) {
        steps = [];
      }
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item['name'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              item['content'] as String? ?? item['notes'] as String? ?? '暂无内容',
            ),
            if ((item['requirement'] as String? ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('要求：${(item['requirement'] as String).trim()}'),
              ),
            ],
            const SizedBox(height: 8),
            Text('标签：${item['tag_name'] ?? '未分类'}'),
            if (wish) ...[
              Text(
                '愿望进度：$currentPoints / $requiredPoints 积分（${wishProgress.toStringAsFixed(0)}%）',
              ),
              Text(
                '目标金额：¥${(requiredPoints / 10).toStringAsFixed(2)} · 已兑换：¥${(currentPoints / 10).toStringAsFixed(2)}',
              ),
            ] else ...[
              Text(
                isStepsHope
                    ? '希望进度（按完成步骤）：${hopeProgress.toStringAsFixed(0)}%'
                    : '希望进度：${hopeProgress.toStringAsFixed(0)}%',
              ),
              Text('完成奖励：${item['reward_points']} 积分'),
              LinearProgressIndicator(
                value: (hopeProgress / 100).clamp(0.0, 1.0),
              ),
              if (isStepsHope) ...[
                const SizedBox(height: 12),
                const Text(
                  '分步任务',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (steps.isEmpty)
                  const Text('暂无步骤，请编辑希望添加', style: TextStyle(fontSize: 12))
                else
                  for (final step in steps)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(
                            step['status'] == '已完成'
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: step['status'] == '已完成'
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              step['name'] as String,
                              style: TextStyle(
                                decoration: step['status'] == '已完成'
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          if (toInt(step['reward_points']) > 0)
                            Text('+${step['reward_points']}分'),
                          if (step['status'] != '已完成' &&
                              item['status'] == '进行中')
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _completeStep(step);
                              },
                              child: const Text('完成'),
                            ),
                        ],
                      ),
                    ),
              ],
            ],
            if (item['status'] != '已兑换') Text('渴望度：${item['desire'] ?? 0}'),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (item['status'] != '已兑换')
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _addItem(wish: wish, item: item);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                if (wish && !WishStatus.isTerminal(item['status'] as String?))
                  Builder(
                    builder: (context) {
                      final isGoal =
                          AppSettingsController.instance.wishGoalId == id;
                      return OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          final settings = AppSettingsController.instance;
                          await settings.setWishGoalId(isGoal ? null : id);
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(isGoal ? '已取消目标' : '已设为首页目标'),
                            ),
                          );
                        },
                        icon: Icon(isGoal ? Icons.flag : Icons.flag_outlined),
                        label: Text(isGoal ? '取消目标' : '设为目标'),
                      );
                    },
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteItem(item, wish);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                ),
                if (item['status'] != '已兑换')
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _addDesire(type, id);
                    },
                    icon: const Icon(Icons.favorite_border),
                    label: const Text('增加渴望度'),
                  ),
                FilledButton(
                  onPressed:
                      item['status'] == '已兑换' ||
                          (!wish &&
                              isStepsHope &&
                              item['status'] == '进行中' &&
                              toInt(item['progress']) < 100)
                      ? null
                      : () {
                          Navigator.pop(context);
                          if (wish) {
                            if (item['status'] == '待兑换') {
                              _redeemWish(item);
                            } else if (item['status'] ==
                                WishStatus.notStarted) {
                              _startWish(item);
                            } else {
                              _contributeWishPoints(item);
                            }
                          } else if (item['status'] == '未进行') {
                            _startHope(item);
                          } else if (toInt(item['progress']) >= 100) {
                            _redeemHope(item);
                          } else {
                            _advanceHope(item);
                          }
                        },
                  child: Text(
                    wish
                        ? item['status'] == '待兑换'
                              ? '兑换'
                              : item['status'] == WishStatus.notStarted
                              ? '开始攒积分'
                              : '攒积分'
                        : item['status'] == '未进行'
                        ? '开始任务'
                        : toInt(item['progress']) >= 100
                        ? '兑换'
                        : isStepsHope
                        ? '完成上方步骤推进进度'
                        : '增加进度 (+1%)',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.taskListsOnly
          ? null
          : AppBar(
              title: const Text('记录'),
              actions: [
                if (!widget.taskListsOnly &&
                    (_tab == _RecordTab.cognition || _tab == _RecordTab.diary))
                  IconButton(
                    tooltip: '在此处新建文件夹',
                    onPressed: _loading
                        ? null
                        : () => _createDiaryFolder(
                            _tab == _RecordTab.diary ? 'diary' : 'cognition',
                          ),
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                if (!widget.taskListsOnly &&
                    (_tab == _RecordTab.cognition || _tab == _RecordTab.diary))
                  IconButton(
                    tooltip: '管理文件夹',
                    onPressed: () => _manageDiaryFolders(
                      _tab == _RecordTab.diary ? 'diary' : 'cognition',
                    ),
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                if (_tab == _RecordTab.wishes || _tab == _RecordTab.hopes)
                  IconButton(
                    tooltip: _tab == _RecordTab.wishes ? '新增愿望' : '新增希望',
                    onPressed: _loading
                        ? null
                        : () => _addItem(wish: _tab == _RecordTab.wishes),
                    icon: const Icon(Icons.add),
                  ),
                if (_tab != _RecordTab.anniversaries)
                  IconButton(
                    onPressed: _loading ? null : _loadData,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
      floatingActionButton: widget.taskListsOnly
          ? FloatingActionButton.extended(
              heroTag: 'records_fab',
              onPressed: _loading
                  ? null
                  : () => _addItem(wish: _tab == _RecordTab.wishes),
              tooltip: _tab == _RecordTab.wishes ? '新增愿望' : '新增希望',
              icon: const Icon(Icons.add),
              label: Text(_tab == _RecordTab.wishes ? '新增愿望' : '新增希望'),
            )
          : _tab == _RecordTab.cognition || _tab == _RecordTab.diary
          ? FloatingActionButton.extended(
              heroTag: 'records_fab',
              onPressed: _loading
                  ? null
                  : () => _editDiary(
                      bookType: _tab == _RecordTab.diary
                          ? 'diary'
                          : 'cognition',
                    ),
              icon: const Icon(Icons.edit_note),
              label: Text(_tab == _RecordTab.diary ? '写日记' : '记录认知'),
            )
          : _tab == _RecordTab.problems
          ? FloatingActionButton.extended(
              heroTag: 'records_fab',
              onPressed: _loading ? null : () => _addProblem(),
              tooltip: '新增问题',
              icon: const Icon(Icons.add),
              label: const Text('新增问题'),
            )
          : null,
      body: Column(
        children: [
          _buildTopTabs(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _loadData,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabs() => SizedBox(
    height: 54,
    child: widget.taskListsOnly
        ? const SizedBox.shrink()
        : ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            scrollDirection: Axis.horizontal,
            children: [
              for (final entry in [
                (_RecordTab.problems, '问题清单'),
                (_RecordTab.cognition, '认知本'),
                (_RecordTab.diary, '日记本'),
                (_RecordTab.anniversaries, '纪念日'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(entry.$2),
                    selected: _tab == entry.$1,
                    onSelected: (_) {
                      setState(() {
                        _tab = entry.$1;
                        _carouselIndex = 0;
                      });
                      if (_carouselController.hasClients) {
                        _carouselController.jumpToPage(0);
                      }
                      _configureCarouselTimer();
                    },
                  ),
                ),
            ],
          ),
  );

  Widget _buildBody() {
    if (_tab == _RecordTab.anniversaries) {
      return AnniversariesView(
        // autoAdd 变化时换 key 重建，保证重复直达也能再次触发添加对话框。
        key: ValueKey('anniversaries-view-$_anniversariesAutoAdd'),
        autoAdd: _anniversariesAutoAdd,
        onAutoAddConsumed: () {
          if (mounted) setState(() => _anniversariesAutoAdd = false);
        },
      );
    }
    if (_tab == _RecordTab.cognition) return _buildDiaries('cognition');
    if (_tab == _RecordTab.diary) return _buildDiaries('diary');
    if (_tab == _RecordTab.problems) return _buildProblems();
    final wish = _tab == _RecordTab.wishes;
    final items = wish ? _wishes : _hopes;
    final carousel = wish ? _inProgressWishes : _inProgressHopes;
    final folders = wish ? ['未开始', '进行中', '待兑换', '已兑换'] : ['未进行', '进行中', '已兑换'];
    final selectedFolder = wish ? _wishFolder : _hopeFolder;
    final visible = items
        .where((item) => _matchesFolder(item, wish, selectedFolder))
        .toList();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in visible) {
      final tag = (item['tag_name'] as String?)?.trim();
      grouped
          .putIfAbsent(tag == null || tag.isEmpty ? '未分类' : tag, () => [])
          .add(item);
    }
    // 手风琴展开态：优先保留用户选择，分组变化后回落到第一个分组。
    final groupKeys = grouped.keys.toList();
    final storedKey = wish ? _wishExpandedGroup : _hopeExpandedGroup;
    final expandedKey = groupKeys.contains(storedKey)
        ? storedKey
        : (groupKeys.isEmpty ? null : groupKeys.first);
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _buildCarousel(carousel, wish),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final folder in folders)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        '$folder (${items.where((item) => _matchesFolder(item, wish, folder)).length})',
                      ),
                      selected: folder == selectedFolder,
                      onSelected: (_) => setState(() {
                        if (wish) {
                          _wishFolder = folder;
                        } else {
                          _hopeFolder = folder;
                        }
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            _Empty(message: '$selectedFolder暂无内容')
          else ...[
            // 标签分组手风琴：点开一个分组时其他同级分组自动收起。
            for (final entry in grouped.entries)
              ExpansionTile(
                key: ValueKey(
                  '${wish ? 'wish' : 'hope'}-group-${entry.key}-${expandedKey == entry.key}',
                ),
                initiallyExpanded: expandedKey == entry.key,
                onExpansionChanged: (value) => setState(() {
                  if (wish) {
                    _wishExpandedGroup = value ? entry.key : null;
                  } else {
                    _hopeExpandedGroup = value ? entry.key : null;
                  }
                }),
                leading: const Icon(Icons.folder_outlined),
                title: Text(entry.key),
                subtitle: Text('${entry.value.length} 项'),
                children: [
                  for (final item in entry.value)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: _buildItem(item, wish),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  // ==================== C3：问题清单 ====================

  String _problemTimeLabel(String? iso) {
    final time = DateTime.tryParse('$iso')?.toLocal();
    if (time == null) return '';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  Widget _buildProblems() {
    final pending = _problems.where((item) => item['status'] != '已解决').toList();
    final resolved = _problems
        .where((item) => item['status'] == '已解决')
        .toList();
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_problems.isEmpty)
            const _Empty(message: '暂无问题，点击下方按钮记录一个待思考的问题')
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '待解决（${pending.length}）',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final problem in pending) _buildProblemCard(problem),
            if (resolved.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '已解决（${resolved.length}）',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final problem in resolved) _buildProblemCard(problem),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildProblemCard(Map<String, dynamic> problem) {
    final resolved = problem['status'] == '已解决';
    final colorScheme = Theme.of(context).colorScheme;
    final accent = resolved
        ? colorScheme.primary.withValues(alpha: 0.7)
        : const Color(0xFFB0764F);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _showProblemDetails(problem),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.14),
          child: Icon(
            resolved ? Icons.check_circle_outline : Icons.help_outline,
            color: accent,
          ),
        ),
        title: Text(
          problem['title'] as String? ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            decoration: resolved ? TextDecoration.lineThrough : null,
            color: resolved
                ? colorScheme.onSurfaceVariant
                : colorScheme.onSurface,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((problem['description'] as String? ?? '').trim().isNotEmpty)
              Text(
                (problem['description'] as String).trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 2),
            Text(
              resolved
                  ? '解决于 ${_problemTimeLabel(problem['resolved_at'] as String?)}'
                  : '记录于 ${_problemTimeLabel(problem['create_time'] as String?)}',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        trailing: IconButton(
          tooltip: resolved ? '重新打开' : '标记解决',
          onPressed: () =>
              resolved ? _reopenProblem(problem) : _resolveProblem(problem),
          icon: Icon(
            resolved ? Icons.undo : Icons.check_circle_outline,
            color: resolved ? colorScheme.tertiary : accent,
          ),
        ),
      ),
    );
  }

  Future<void> _addProblem({Map<String, dynamic>? problem}) async {
    final titleController = TextEditingController(
      text: problem?['title'] as String? ?? '',
    );
    final descController = TextEditingController(
      text: problem?['description'] as String? ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(problem == null ? '记录问题' : '编辑问题'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: problem == null,
                textInputAction: TextInputAction.next,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '问题标题 *',
                  hintText: '当下没有答案、暂不处理的问题',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descController,
                minLines: 3,
                maxLines: null,
                decoration: const InputDecoration(
                  labelText: '详细描述',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext)
                  ..clearSnackBars()
                  ..showSnackBar(const SnackBar(content: Text('请输入问题标题')));
                return;
              }
              try {
                await CollectionRepository.instance.saveProblem({
                  'title': titleController.text.trim(),
                  'description': descController.text.trim(),
                }, id: problem?['problem_id'] as int?);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(SnackBar(content: Text('保存问题失败：$error')));
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    titleController.dispose();
    descController.dispose();
    if (saved == true) await _loadData();
  }

  Future<void> _resolveProblem(Map<String, dynamic> problem) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('标记为已解决？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              problem['title'] as String? ?? '',
              style: Theme.of(dialogContext).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '解决思路备注（选填）',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('标记解决'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      noteController.dispose();
      return;
    }
    final note = noteController.text.trim();
    noteController.dispose();
    try {
      await CollectionRepository.instance.setProblemResolved(
        problem['problem_id'] as int,
        resolved: true,
        solutionNote: note,
      );
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }

  Future<void> _reopenProblem(Map<String, dynamic> problem) async {
    try {
      await CollectionRepository.instance.setProblemResolved(
        problem['problem_id'] as int,
        resolved: false,
        solutionNote: problem['solution_note'] as String? ?? '',
      );
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }

  Future<void> _deleteProblem(Map<String, dynamic> problem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除问题？'),
        content: Text('将删除「${problem['title']}」，删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await CollectionRepository.instance.deleteProblem(
        problem['problem_id'] as int,
      );
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Future<void> _showProblemDetails(Map<String, dynamic> problem) async {
    final resolved = problem['status'] == '已解决';
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                problem['title'] as String? ?? '',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '记录于 ${_problemTimeLabel(problem['create_time'] as String?)}',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              if (resolved)
                Text(
                  '解决于 ${_problemTimeLabel(problem['resolved_at'] as String?)}',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              Text(
                (problem['description'] as String? ?? '').trim().isEmpty
                    ? '暂无详细描述'
                    : (problem['description'] as String).trim(),
              ),
              if ((problem['solution_note'] as String? ?? '')
                  .trim()
                  .isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).colorScheme.secondaryContainer
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '解决思路：${(problem['solution_note'] as String).trim()}',
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, 'resolve'),
                  icon: Icon(resolved ? Icons.undo : Icons.check),
                  label: Text(resolved ? '重新打开' : '标记为已解决'),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, 'edit'),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, 'delete'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'resolve') {
      if (resolved) {
        await _reopenProblem(problem);
      } else {
        await _resolveProblem(problem);
      }
    } else if (action == 'edit') {
      await _addProblem(problem: problem);
    } else if (action == 'delete') {
      await _deleteProblem(problem);
    }
  }

  Widget _buildCarousel(List<Map<String, dynamic>> items, bool wish) {
    if (items.isEmpty) return const _Empty(message: '暂无需要展示的内容');
    return SizedBox(
      height: 210,
      child: PageView.builder(
        controller: _carouselController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          if (mounted) setState(() => _carouselIndex = index);
        },
        itemCount: items.length,
        itemBuilder: (context, index) {
          final safeIndex = index.clamp(0, items.length - 1);
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _buildCarouselCard(items, safeIndex, wish),
          );
        },
      ),
    );
  }

  Widget _buildCarouselCard(
    List<Map<String, dynamic>> items,
    int index,
    bool wish,
  ) {
    final item = items[index];
    final hopeProgress = toInt(item['progress']).clamp(0, 100);
    final progress = wish
        ? ((toDouble(item['current_points']) /
                  toDouble(item['required_points']))
              .clamp(0.0, 1.0))
        : hopeProgress / 100;
    final progressLabel = wish
        ? '${item['current_points'] ?? 0} / ${item['required_points'] ?? 0} 积分'
        : '$hopeProgress% 已完成';
    final accent = wish ? const Color(0xFFDA7966) : const Color(0xFF438F78);
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withValues(alpha: 0.15), surface, surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _showDetails(item, wish),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        wish
                            ? Icons.card_giftcard_rounded
                            : Icons.emoji_events_rounded,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            wish ? '正在积攒的愿望' : '正在前进的希望',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            '${item['tag_name'] ?? '未分类'} · ${index + 1} / ${items.length}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, color: accent),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  item['name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  item['content'] as String? ?? '点击查看详情',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 13),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.13),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  progressLabel,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: accent, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item, bool wish) {
    final redeemed = item['status'] == '已兑换' || item['status'] == '已完成';
    final wishFull =
        wish &&
        (item['status'] == '待兑换' ||
            toInt(item['current_points']) >= toInt(item['required_points']));
    final hopeProgress = toInt(item['progress']);
    final hopeReady = !wish && hopeProgress >= 100;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => _showDetails(item, wish),
              leading: CircleAvatar(child: Text('${item['desire'] ?? 0}')),
              title: Text(item['name'] as String),
              subtitle: Text(
                '${item['tag_name'] ?? '未分类'} · ${item['content'] ?? item['notes'] ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Wrap(
                spacing: 0,
                children: [
                  if (!redeemed)
                    IconButton(
                      tooltip: '编辑',
                      onPressed: () => _addItem(wish: wish, item: item),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  IconButton(
                    tooltip: '删除',
                    onPressed: () => _deleteItem(item, wish),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
            if (wish) ...[
              Text(
                '积分 ${item['current_points']} / ${item['required_points']} · '
                '目标金额 ¥${(toDouble(item['required_points']) / 10).toStringAsFixed(2)}',
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value:
                    (toDouble(item['current_points']) /
                            toDouble(item['required_points']))
                        .clamp(0.0, 1.0),
              ),
            ] else ...[
              Row(
                children: [
                  Text('进度 $hopeProgress%'),
                  const Spacer(),
                  Text('完成奖励 +${item['reward_points']} 分'),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (hopeProgress / 100).clamp(0.0, 1.0),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!redeemed)
                  OutlinedButton.icon(
                    onPressed: () => _addDesire(
                      wish ? 'wish' : 'hope',
                      (wish ? item['wish_id'] : item['hope_id']) as int,
                    ),
                    icon: const Icon(Icons.favorite_border),
                    label: Text('渴望度 ${item['desire'] ?? 0}'),
                  ),
                if (wish && !redeemed)
                  FilledButton.icon(
                    onPressed: () {
                      if (wishFull) {
                        _redeemWish(item);
                      } else if (item['status'] == WishStatus.notStarted) {
                        _startWish(item);
                      } else {
                        _contributeWishPoints(item);
                      }
                    },
                    icon: Icon(
                      wishFull
                          ? Icons.redeem
                          : item['status'] == WishStatus.notStarted
                          ? Icons.play_arrow
                          : Icons.savings_outlined,
                    ),
                    label: Text(
                      wishFull
                          ? '兑换'
                          : item['status'] == WishStatus.notStarted
                          ? '开始攒积分'
                          : '攒积分',
                    ),
                  ),
                if (!wish && !redeemed && item['status'] == '未进行')
                  FilledButton.icon(
                    onPressed: () => _startHope(item),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始任务'),
                  ),
                if (!wish && !redeemed && item['status'] == '进行中')
                  FilledButton.icon(
                    onPressed: hopeReady
                        ? () => _redeemHope(item)
                        : item['hope_mode'] == 'steps'
                        ? () => _showDetails(item, wish)
                        : () => _advanceHope(item),
                    icon: Icon(
                      hopeReady
                          ? Icons.redeem
                          : item['hope_mode'] == 'steps'
                          ? Icons.checklist
                          : Icons.add_task,
                    ),
                    label: Text(
                      hopeReady
                          ? '兑换'
                          : item['hope_mode'] == 'steps'
                          ? '完成步骤'
                          : '增加进度',
                    ),
                  ),
                if (redeemed)
                  Chip(
                    avatar: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('已兑换'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiaries(String bookType) {
    final folders = _foldersOfBook(bookType);
    final diaries = _diariesOfBook(bookType);
    final selectedFolder = _selectedFolderOf(bookType);
    final children = folders
        .where((folder) => folder['parent_id'] == selectedFolder)
        .toList();
    final visible = diaries
        .where((diary) => diary['folder_id'] == selectedFolder)
        .toList();
    final currentFolder = selectedFolder == null
        ? null
        : folders.firstWhere((folder) => folder['folder_id'] == selectedFolder);
    final parentId = currentFolder?['parent_id'] as int?;
    final bookName = _bookName(bookType);
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: selectedFolder == null
                ? const Icon(Icons.menu_book_outlined)
                : IconButton(
                    tooltip: '返回上一级',
                    onPressed: () =>
                        setState(() => _setSelectedFolder(bookType, parentId)),
                    icon: const Icon(Icons.arrow_back),
                  ),
            title: Text(
              currentFolder == null
                  ? bookName
                  : currentFolder['folder_name'] as String,
            ),
            subtitle: Text(
              currentFolder == null
                  ? '文件夹 ${children.length} 个'
                  : _folderPath(selectedFolder!),
            ),
          ),
          for (final folder in children)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder['folder_name'] as String),
                subtitle: Text(
                  '${diaries.where((diary) => diary['folder_id'] == folder['folder_id']).length} 篇',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(
                  () =>
                      _setSelectedFolder(bookType, folder['folder_id'] as int),
                ),
              ),
            ),
          if (visible.isEmpty && children.isEmpty)
            const _Empty(message: '此文件夹还没有内容'),
          ...visible.map(
            (diary) => Card(
              child: ListTile(
                onTap: () => _showDiary(bookType, diary),
                onLongPress: () => _moveDiary(bookType, diary),
                leading: const Icon(Icons.menu_book),
                title: Text(diary['title'] as String),
                subtitle: Text(
                  '${diary['folder_name'] ?? '未分类'} · ${_diaryPreview(diary)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manageDiaryFolders(String bookType) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => DiaryFolderManagementPage(bookType: bookType),
      ),
    );
    if (mounted) await _loadData();
  }

  Future<void> _createDiaryFolder(String bookType) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('新建${_bookName(bookType)}文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    await waitForDialogDismissal();
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final folders = _foldersOfBook(bookType);
      final parentId = _selectedFolderOf(bookType);
      final duplicate = folders.any(
        (folder) =>
            folder['folder_name'] == name && folder['parent_id'] == parentId,
      );
      if (duplicate) {
        throw StateError('此文件夹中已有同名文件夹');
      }
      await CollectionRepository.instance.createFolder(
        name: name,
        bookType: bookType,
        parentId: parentId,
        sort: folders.length,
      );
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('新建文件夹失败：$error')));
      }
    }
  }

  Future<void> _editDiary({
    required String bookType,
    Map<String, dynamic>? diary,
  }) async {
    if (_foldersOfBook(bookType).isEmpty) {
      await _manageDiaryFolders(bookType);
      if (!mounted) return;
      if (_foldersOfBook(bookType).isEmpty) return;
    }
    final result = await Navigator.push<DiaryEditResult>(
      context,
      MaterialPageRoute<DiaryEditResult>(
        builder: (context) => DiaryEditorPage(
          bookType: bookType,
          folders: _foldersOfBook(bookType),
          diary: diary,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result.deleted) {
      try {
        await CollectionRepository.instance.deleteDiary(
          diary!['diary_id'] as int,
        );
        await _loadData();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('删除失败：$error')));
        }
      }
      return;
    }
    try {
      final now = DateTime.now().toIso8601String();
      final diaryValues = {
        'folder_id': result.folderId,
        'title': result.title,
        'content': result.content,
        'content_format': result.contentFormat,
        'book_type': bookType,
        'update_time': now,
        if (diary == null) 'create_time': now,
      };
      await CollectionRepository.instance.saveDiary(
        diaryValues,
        id: diary?['diary_id'] as int?,
      );
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }

  Future<void> _moveDiary(String bookType, Map<String, dynamic> diary) async {
    final orderedFolders = _orderedFoldersOf(bookType);
    if (orderedFolders.length < 2) return;
    final selectedFolder = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('移动到${_bookName(bookType)}文件夹')),
            for (final folder in orderedFolders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(_folderPath(folder['folder_id'] as int)),
                trailing: diary['folder_id'] == folder['folder_id']
                    ? const Icon(Icons.check)
                    : null,
                onTap: diary['folder_id'] == folder['folder_id']
                    ? null
                    : () => Navigator.pop(
                        sheetContext,
                        folder['folder_id'] as int,
                      ),
              ),
          ],
        ),
      ),
    );
    if (selectedFolder == null || !mounted) return;
    try {
      await CollectionRepository.instance.saveDiary({
        'folder_id': selectedFolder,
        'book_type': bookType,
        'update_time': DateTime.now().toIso8601String(),
      }, id: diary['diary_id'] as int);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已移动')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('移动失败：$error')));
      }
    }
  }

  String _folderPath(int folderId) =>
      FolderPathUtil.buildPath(folderId, _folders);

  /// C1：从日记内容中提取纯文本预览（兼容 delta JSON 与历史纯文本）。
  String _diaryPreview(Map<String, dynamic> diary) {
    final content = diary['content'] as String?;
    if (content == null || content.isEmpty) return '';
    final format = (diary['content_format'] as String?) ?? 'plaintext';
    if (format != 'delta') return content;
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) {
        return Document.fromJson(decoded).toPlainText().trim();
      }
    } catch (_) {
      // 内容损坏时回退为原文。
    }
    return content;
  }

  /// C1：点击日记直接进入全屏查看页（编辑器的只读模式），
  /// 在查看页内可切换编辑或删除。
  Future<void> _showDiary(String bookType, Map<String, dynamic> diary) async {
    final result = await Navigator.push<DiaryEditResult>(
      context,
      MaterialPageRoute<DiaryEditResult>(
        builder: (context) => DiaryEditorPage(
          bookType: bookType,
          folders: _foldersOfBook(bookType),
          diary: diary,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result.deleted) {
      try {
        await CollectionRepository.instance.deleteDiary(
          diary['diary_id'] as int,
        );
        await _loadData();
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('删除失败：$error')));
        }
      }
      return;
    }
    if (result.title == null) return;
    try {
      final now = DateTime.now().toIso8601String();
      await CollectionRepository.instance.saveDiary({
        'folder_id': result.folderId,
        'title': result.title,
        'content': result.content,
        'content_format': result.contentFormat,
        'book_type': bookType,
        'update_time': now,
      }, id: diary['diary_id'] as int);
      await _loadData();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(message)),
    ),
  );
}
