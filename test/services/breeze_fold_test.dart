import 'dart:io';

import 'package:PiliPlus/pages/breeze/breeze_fold.dart';
import 'package:PiliPlus/services/breeze/breeze_rules.dart';
import 'package:PiliPlus/services/breeze/breeze_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

const _raw = BreezeRaw(
  kind: BreezeKind.dynamic,
  text: '新品上市，戳链接购买',
  author: '测试UP',
  authorId: '123',
  itemId: '1',
);

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-breeze-test-');
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    await BreezeService.init();
    await BreezeService.saveApi(
      apiKey: 'test',
      provider: BreezeProvider.jev,
      apiUrl: '',
      apiModel: '',
      apiProtocol: BreezeProtocol.openai,
    );
    // A cached classification, so no request is sent.
    await Hive.box('breezeCache').put(
      breezeCacheKey(sanitize(_raw), BreezeService.config),
      {
        'result': BreezeResult(
          prob: .9,
          categories: ['ad'],
          kind: 'ad',
        ).toJson(),
        'expires': DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      },
    );
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // Hive writes need real IO, then the fake zone must run their callbacks.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('folds, expands and follows the whitelist', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BreezeFold(
            kind: BreezeKind.dynamic,
            source: _raw,
            raw: () => _raw,
            child: const Text('CONTENT'),
          ),
        ),
      ),
    );
    expect(
      find.text('CONTENT'),
      findsOneWidget,
      reason: 'visible until checked',
    );

    await settle(tester);
    expect(find.text('测试UP · 广告 · 90%'), findsOneWidget);
    expect(find.text('CONTENT'), findsNothing);

    await tester.tap(find.text('展开'));
    await tester.pumpAndSettle();
    expect(find.text('CONTENT'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);

    final history = BreezeService.history;
    expect(history, hasLength(1));
    expect(history.single['action'], '折叠');
    expect(history.single['authorId'], '123');

    await tester.runAsync(
      () => BreezeService.setListed(BreezeKey.whitelist, '123', add: true),
    );
    await settle(tester);
    expect(find.text('CONTENT'), findsOneWidget);
    expect(find.textContaining('广告'), findsNothing);
    expect(BreezeService.history.single['rule'], 'whitelist');
    // Let the last write reach the disk before the fake zone ends.
    await tester.runAsync(() => Hive.box('breezeHistory').flush());
    await tester.pumpAndSettle();
  });
}
