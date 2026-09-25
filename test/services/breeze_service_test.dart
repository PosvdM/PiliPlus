import 'dart:io';

import 'package:PiliPlus/services/breeze/breeze_rules.dart';
import 'package:PiliPlus/services/breeze/breeze_service.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Like the app's global overrides in debug builds or with 忽略证书错误.
class _AcceptAnyCertificate extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = (cert, host, port) => true;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('piliplus-breeze-service-');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    HttpOverrides.global = null;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'init does not need the settings box, which opens in parallel',
    () async {
      // GStorage.setting is not assigned yet, as during GStorage.init().
      await BreezeService.init();

      final setting = await Hive.openBox('setting');
      await setting.put('breezeCustomPrompt', ' 游戏官方号宣传新活动也算广告 ');
      GStorage.setting = setting;
      GStorage.video = await Hive.openBox('video');

      expect(
        BreezeService.config.rulesPrompt,
        '$breezeDefaultPrompt\n用户补充规则（与上文冲突时以此为准）：游戏官方号宣传新活动也算广告',
        reason: 'the old extra prompt is migrated on the first read',
      );
      expect(setting.containsKey('breezeCustomPrompt'), isFalse);
    },
  );

  test('reset and import take effect without restarting', () async {
    await BreezeService.saveApi(
      apiKey: 'secret',
      provider: BreezeProvider.jev,
      apiUrl: '',
      apiModel: '',
      apiProtocol: BreezeProtocol.openai,
    );
    await BreezeService.put(BreezeKey.adThreshold, 80);
    expect(BreezeService.config.configured, isTrue);

    final events = <BreezeEvent>[];
    final sub = BreezeService.events.listen(events.add);

    await GStorage.importAllJsonSettings({
      'setting': {BreezeKey.adThreshold: 55},
      'video': <String, dynamic>{},
    });
    await pumpEventQueue();
    expect(BreezeService.config.adThreshold, 55);
    expect(events.whereType<BreezeSettingsChanged>(), isNotEmpty);

    // 重置所有数据 clears the key; nothing keeps using it from memory.
    events.clear();
    await BreezeService.clear();
    await pumpEventQueue();
    expect(BreezeService.config.configured, isFalse);
    expect(BreezeService.history, isEmpty);
    expect(events.whereType<BreezeSettingsChanged>(), isNotEmpty);
    await sub.cancel();
  });

  test('API requests verify certificates despite global overrides', () async {
    const fixtures = 'test/services/fixtures';
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain('$fixtures/localhost.crt')
        ..usePrivateKey('$fixtures/localhost.key'),
    );
    server.listen((request) {
      request.response
        ..statusCode = 200
        ..write('{}')
        ..close();
    });
    HttpOverrides.global = _AcceptAnyCertificate();
    final uri = Uri.parse('https://localhost:${server.port}/');
    try {
      // The global override really accepts the self-signed certificate...
      final plain = HttpClient();
      final ok = await (await plain.getUrl(uri)).close();
      expect(ok.statusCode, 200);
      plain.close(force: true);

      // ...but the client that carries the API key rejects it.
      final strict = BreezeService.createHttpClient();
      await expectLater(
        strict.getUrl(uri).then((request) => request.close()),
        throwsA(isA<HandshakeException>()),
      );
      strict.close(force: true);
    } finally {
      HttpOverrides.global = null;
      await server.close(force: true);
    }
  });
}
