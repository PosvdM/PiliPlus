import 'package:PiliPlus/pages/breeze/api_page.dart';
import 'package:PiliPlus/pages/breeze/history_page.dart';
import 'package:PiliPlus/pages/breeze/lists_page.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/multi_select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/slider_dialog.dart';
import 'package:PiliPlus/services/breeze/breeze_rules.dart';
import 'package:PiliPlus/services/breeze/breeze_service.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

void _changed(String key) => BreezeService.onChanged([key]);

List<SettingsModel> get breezeSettings => [
  SwitchModel(
    title: '启用哔哩清风',
    subtitle: '用你的 AI API 识别动态和视频置顶评论中的广告、抽奖、活动宣传与招聘，按类别折叠',
    leading: const Icon(Icons.air),
    setKey: BreezeKey.enabled,
    defaultVal: true,
    onChanged: (_) => _changed(BreezeKey.enabled),
  ),
  NormalModel(
    title: 'API 设置',
    leading: const Icon(Icons.key_outlined),
    getSubtitle: () {
      final c = BreezeService.config;
      if (!c.configured) return '未配置，保存 API Key 后才会识别';
      return c.provider == BreezeProvider.jev
          ? '已配置 · Jev 官方'
          : '已配置 · ${c.apiModel}';
    },
    onTap: (context, setState) async {
      await Get.to(() => const BreezeApiPage());
      setState();
    },
  ),
  SwitchModel(
    title: '识别动态',
    leading: const Icon(Icons.dynamic_feed_outlined),
    setKey: BreezeKey.dynamics,
    defaultVal: true,
    onChanged: (_) => _changed(BreezeKey.dynamics),
  ),
  SwitchModel(
    title: '识别视频置顶评论',
    leading: const Icon(Icons.push_pin_outlined),
    setKey: BreezeKey.pinned,
    defaultVal: true,
    onChanged: (_) => _changed(BreezeKey.pinned),
  ),
  NormalModel(
    title: '自动折叠',
    leading: const Icon(Icons.unfold_less),
    getSubtitle: () {
      final kinds = BreezeService.config.foldCategories;
      return kinds.isEmpty
          ? '不折叠任何类别'
          : breezeCategories
                .where(kinds.contains)
                .map((k) => breezeCategoryLabels[k])
                .join('、');
    },
    onTap: (context, setState) async {
      final res = await showDialog<Set<String>>(
        context: context,
        builder: (context) => MultiSelectDialog<String>(
          title: '自动折叠',
          initValues: BreezeService.config.foldCategories,
          values: {
            for (final k in breezeCategories) k: breezeCategoryLabels[k]!,
          },
        ),
      );
      if (res != null) {
        await BreezeService.put(
          BreezeKey.foldCategories,
          breezeCategories.where(res.contains).toList(),
        );
        setState();
      }
    },
  ),
  SwitchModel(
    title: '包含附带抽奖',
    subtitle: '也折叠新闻、活动等内容附带的抽奖',
    leading: const Icon(Icons.redeem_outlined),
    setKey: BreezeKey.foldIncidental,
    onChanged: (_) => _changed(BreezeKey.foldIncidental),
  ),
  _percent(
    title: '广告折叠阈值',
    subtitle: '广告置信度达到阈值时折叠',
    icon: Icons.tune,
    key: BreezeKey.adThreshold,
    value: () => BreezeService.config.adThreshold,
  ),
  _percent(
    title: '谨慎模式阈值',
    subtitle: '谨慎过滤名单中的 UP 主使用此阈值，不会低于广告折叠阈值',
    icon: Icons.shield_outlined,
    key: BreezeKey.cautiousThreshold,
    value: () => BreezeService.config.cautiousThreshold,
  ),
  const SwitchModel(
    title: '自动启用谨慎模式',
    subtitle: 'UP 主最近动态的广告占比达到设定值后，自动加入谨慎过滤名单并持续生效',
    leading: Icon(Icons.auto_mode),
    setKey: BreezeKey.autoCautious,
    defaultVal: true,
    onChanged: _onAutoCautious,
  ),
  _percent(
    title: '自动启用的广告占比',
    icon: Icons.percent,
    key: BreezeKey.ratioThreshold,
    value: () => BreezeService.config.ratioThreshold,
  ),
  NormalModel(
    title: '统计动态条数',
    leading: const Icon(Icons.format_list_numbered),
    getSubtitle: () => '按最近检测的 ${BreezeService.config.ratioWindow} 条不同动态计算',
    onTap: (context, setState) async {
      final res = await showDialog<double>(
        context: context,
        builder: (context) => SliderDialog(
          title: const Text('统计动态条数'),
          min: 2,
          max: 100,
          divisions: 98,
          precise: 0,
          suffix: ' 条',
          value: BreezeService.config.ratioWindow.toDouble(),
        ),
      );
      if (res != null) {
        await BreezeService.put(BreezeKey.ratioWindow, res.round());
        setState();
      }
    },
  ),
  NormalModel(
    title: 'UP 主名单',
    leading: const Icon(Icons.people_outline),
    getSubtitle: () {
      final c = BreezeService.config;
      return '始终显示 ${c.whitelist.length} 位 · 谨慎过滤 ${c.enhancedList.length} 位';
    },
    onTap: (context, setState) async {
      await Get.to(() => const BreezeListsPage());
      setState();
    },
  ),
  NormalModel(
    title: '记录与统计',
    subtitle: '查看检测记录、分类、置信度和 UP 主广告统计',
    leading: const Icon(Icons.query_stats),
    onTap: (context, setState) => Get.to(() => const BreezeHistoryPage()),
  ),
];

void _onAutoCautious(bool _) => _changed(BreezeKey.autoCautious);

NormalModel _percent({
  required String title,
  String? subtitle,
  required IconData icon,
  required String key,
  required ValueGetter<int> value,
}) => NormalModel(
  title: title,
  leading: Icon(icon),
  getSubtitle: () =>
      subtitle == null ? '${value()}%' : '${value()}% · $subtitle',
  onTap: (context, setState) async {
    final res = await showDialog<double>(
      context: context,
      builder: (context) => SliderDialog(
        title: Text(title),
        min: 1,
        max: 100,
        divisions: 99,
        precise: 0,
        suffix: '%',
        value: value().toDouble(),
      ),
    );
    if (res != null) {
      await BreezeService.put(key, res.round());
      setState();
    }
  },
);
