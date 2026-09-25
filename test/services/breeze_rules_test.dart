import 'package:PiliPlus/services/breeze/breeze_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const _raw = BreezeRaw(
  kind: BreezeKind.dynamic,
  text: '混合',
  author: '测试UP',
  authorId: '123',
  itemId: 'item',
);

Map _row(int i, double prob, {String uid = '123'}) => {
  'id': 'seed$i',
  'authorId': uid,
  'type': 'dynamic',
  'classificationVersion': breezeClassificationVersion,
  'prob': prob,
  'rule': 'category',
  'firstSeen': i + 1,
};

List<Map> _seed(int n, int ads) => [
  for (var i = 0; i < n; i++) _row(i, i < ads ? .8 : .1),
];

BreezeResult _api({
  double ad = .1,
  double recruitment = 0,
  double event = 0,
  Object? primary,
  Object? incidental,
  bool lottery = false,
}) => parseResponse(
  {
    'answers': {
      'is_ad': {'noul': ad},
      'is_recruitment': {'noul': recruitment},
      'is_event': {'noul': event},
      'giveaway_primary': {'noul': primary},
      'giveaway_incidental': {'noul': incidental},
    },
  },
  BreezeRequest('', const {}, false, lottery),
);

void main() {
  test('giveaway keywords need an explicit lottery mechanism', () {
    for (final t in [
      '互动抽奖好运来',
      '转发+评论+关注 本月抽1人送手表',
      '本月抽奖，奖品手表，评论参与',
      '从评论中随机抽取三名朋友送出奖品',
    ]) {
      expect(isGiveaway(t), isTrue, reason: t);
    }
    for (final t in [
      '穿上 Storm Crew 拍一张合影，就有机会被选入运载火箭上太空',
      '有奖征集！搞卫生还能搞得有什么说法？',
      '不抽奖，这次聊聊抽奖骗局',
      '游戏抽卡体验',
      '岗位招聘，期待你的加入',
    ]) {
      expect(isGiveaway(t), isFalse, reason: t);
    }
  });

  test('cache and history keys match the extension', () {
    final state = sanitize(
      const BreezeRaw(
        kind: BreezeKind.dynamic,
        text: '互动抽奖 转发关注抽1人送耳机',
        originalText: '感谢支持',
        forwardedText: '互动抽奖',
        links: ['https://t.bilibili.com/1'],
      ),
    );
    expect(
      breezeCacheKey(state, const BreezeConfig()),
      '34026caae8ab0e91e4a819fd6e383e7a80b99c67045cb1a3aa1a5e14dcc1f878',
    );
    expect(
      historyId(
        const BreezeRaw(
          kind: BreezeKind.dynamic,
          text: 'x',
          authorId: '123',
          itemId: '456',
        ),
      ),
      'b322a8fb8a0059ed4efc58662816aa0f781e179a819ebbc424bf0cf9d2987718',
    );
  });

  test('giveaway primary, incidental and uncertain answers', () {
    expect(
      _api(lottery: true, primary: .95, incidental: .02).giveawayType,
      'primary',
    );
    expect(
      _api(lottery: true, primary: .05, incidental: .95).giveawayType,
      'incidental',
    );
    for (final (p, i) in [(.5, .5), (.9, .9), (null, null)]) {
      final r = _api(lottery: true, primary: p, incidental: i);
      expect(r.giveawayType, 'uncertain');
      expect(r.categories, isNot(contains('giveaway')));
    }
    // The model cannot invent a giveaway without the keywords.
    expect(_api(primary: .95, incidental: 0).giveawayType, isNull);
  });

  test('incidental giveaways fold only when enabled', () {
    BreezeResult run(BreezeConfig c) => applyPolicy(
      _api(lottery: true, primary: .05, incidental: .95),
      _raw,
      c,
      const [],
    );
    const giveaway = BreezeConfig(foldCategories: ['giveaway']);
    expect(run(giveaway).fold, isFalse);
    expect(
      run(
        const BreezeConfig(foldCategories: ['giveaway'], foldIncidental: true),
      ).fold,
      isTrue,
    );
    expect(
      run(const BreezeConfig(foldCategories: [], foldIncidental: true)).fold,
      isFalse,
    );
  });

  test('independent categories and thresholds', () {
    final mixed = applyPolicy(
      _api(ad: .8, recruitment: .9),
      _raw,
      const BreezeConfig(),
      const [],
    );
    expect(mixed.categories, ['ad', 'recruitment']);
    expect(mixed.fold, isTrue);

    final recruitment = applyPolicy(
      _api(ad: .8, recruitment: .9),
      _raw,
      const BreezeConfig(foldCategories: ['recruitment']),
      const [],
    );
    expect(recruitment.kind, 'recruitment');

    // A cautious author below 90% stays visible; 90% folds.
    const cautious = BreezeConfig(
      foldCategories: ['ad'],
      enhancedList: [BreezeAuthor(uid: '123')],
    );
    expect(applyPolicy(_api(ad: .8), _raw, cautious, const []).fold, isFalse);
    expect(applyPolicy(_api(ad: .9), _raw, cautious, const []).fold, isTrue);

    final event = applyPolicy(
      _api(event: .9),
      _raw,
      const BreezeConfig(foldCategories: ['event']),
      const [],
    );
    expect((event.kind, event.fold), ('event', true));
    expect(
      applyPolicy(
        _api(event: .9),
        _raw,
        const BreezeConfig(foldCategories: ['ad']),
        const [],
      ).fold,
      isFalse,
    );
  });

  test('author ratio uses the latest full window', () {
    const c = BreezeConfig();
    expect(authorRatio(_seed(9, 9), '123', c), isNull);
    expect(authorRatio(_seed(10, 3), '123', c), isNull);
    expect(authorRatio(_seed(10, 4), '123', c)?.ads, 4);
    expect(authorRatio(_seed(14, 4), '123', c), isNull);
    expect(
      authorRatio(
        _seed(10, 10),
        '123',
        const BreezeConfig(autoCautious: false),
      ),
      isNull,
    );
    expect(
      authorRatio(
        _seed(10, 10),
        '123',
        const BreezeConfig(autoCautionExcluded: ['123']),
      ),
      isNull,
    );
  });

  test('saved auto caution stays when the ratio drops', () {
    const c = BreezeConfig(
      enhancedList: [
        BreezeAuthor(
          uid: '123',
          source: 'auto',
          sample: BreezeSample(total: 10, ads: 4),
        ),
      ],
    );
    final r = applyPolicy(_api(ad: .8), _raw, c, _seed(10, 0));
    expect(r.enhanced, isTrue);
    expect(r.cautionStatus, 'active');
    expect(r.fold, isFalse);
  });

  test('local decisions skip the API', () {
    Map<String, dynamic> s(String text) =>
        sanitize(BreezeRaw(kind: BreezeKind.dynamic, text: text));
    expect(
      localDecision(
        _raw,
        s('x'),
        const BreezeConfig(whitelist: [BreezeAuthor(uid: '123')]),
      )?.rule,
      'whitelist',
    );
    expect(
      localDecision(
        _raw,
        s('互动抽奖'),
        const BreezeConfig(foldCategories: ['giveaway']),
      )?.giveawayType,
      'uncertain',
    );
    expect(
      localDecision(
        _raw,
        s('普通'),
        const BreezeConfig(foldCategories: ['giveaway'], apiKey: 'k'),
      )?.rule,
      'local',
    );
    expect(
      localDecision(_raw, s('普通'), const BreezeConfig(apiKey: 'k')),
      isNull,
    );
  });

  test('OpenAI compatible responses and payloads', () {
    const c = BreezeConfig(
      provider: BreezeProvider.custom,
      apiUrl: 'https://example.test/v1/chat/completions',
      apiModel: 'test',
      apiKey: 'k',
    );
    final request = buildRequest(
      sanitize(const BreezeRaw(kind: BreezeKind.dynamic, text: '互动抽奖 转发参与')),
      c,
    );
    expect(request.openai, isTrue);
    final messages = request.payload['messages'] as List;
    expect(
      (messages.first as Map)['content'],
      contains('giveaway_incidental_prob'),
    );
    final r = parseResponse({
      'choices': [
        {
          'message': {
            'content': '```json\n{"ad_prob":0.1,"recruitment_prob":0,"giveaway_primary_prob":0.1,"giveaway_incidental_prob":0.95}\n```',
          },
        },
      ],
    }, request);
    expect(r.giveawayType, 'incidental');
    expect(
      () => parseResponse({
        'choices': [
          {
            'message': {'content': 'nope'},
          },
        ],
      }, request),
      throwsA(isA<BreezeException>()),
    );
    expect(
      () => validateCustomEndpoint('http://example.test/v1'),
      throwsA(isA<BreezeException>()),
    );
    expect(
      () => validateCustomEndpoint('https://example.test/v1?key=1'),
      throwsA(isA<BreezeException>()),
    );
  });

  test('editable prompt replaces the rules, output format stays', () {
    expect(
      sha256Hex(breezeDefaultPrompt),
      '0e4c9ccab6ab2a8edf99f42e50cddf8d98a81eb2d9de1ac80bb37a1aa392f661',
      reason: 'same built-in prompt as the extension',
    );
    expect(normalizeBreezePrompt('  $breezeDefaultPrompt  '), '');
    expect(normalizeBreezePrompt('   '), '');
    expect(normalizeBreezePrompt('A' * 5000), 'A' * breezePromptLimit);

    const prompt = '游戏官方号宣传新活动也算广告';
    final state = sanitize(
      const BreezeRaw(
        kind: BreezeKind.dynamic,
        text: '互动抽奖 转发关注抽1人送耳机',
        originalText: '感谢支持',
        forwardedText: '互动抽奖',
        links: ['https://t.bilibili.com/1'],
      ),
    );
    expect(
      breezeCacheKey(state, const BreezeConfig(rulesPrompt: prompt)),
      '3732019683af9301e501dd12a35cfd0e38100616e75b531d0701d90e3dc87d3a',
      reason: 'same key as the extension',
    );

    final builtin = buildRequest(state, const BreezeConfig(apiKey: 'k'));
    final builtinQuestions = builtin.payload['questions'] as Map;
    expect(
      (builtinQuestions['is_ad'] as Map)['instructions'],
      '$breezeDefaultPrompt 返回广告概率。',
    );

    final jev = buildRequest(
      state,
      const BreezeConfig(apiKey: 'k', rulesPrompt: prompt),
    );
    final questions = jev.payload['questions'] as Map;
    expect((questions['is_ad'] as Map)['instructions'], '$prompt 返回广告概率。');
    expect(
      (questions['is_event'] as Map)['instructions'],
      '$prompt 返回活动宣传概率。',
    );
    expect(
      (questions['giveaway_primary'] as Map)['instructions'],
      allOf(startsWith('仅判断输入内容中的抽奖主次'), isNot(contains(prompt))),
      reason: 'giveaway rules stay built in',
    );
    expect(jev.payload['model'], 'jev-latest');

    final openai = buildRequest(
      sanitize(const BreezeRaw(kind: BreezeKind.dynamic, text: '周边开售')),
      const BreezeConfig(
        apiKey: 'k',
        provider: BreezeProvider.custom,
        apiUrl: 'https://example.test/v1/chat/completions',
        apiModel: 'm',
        rulesPrompt: prompt,
      ),
    );
    final system =
        ((openai.payload['messages'] as List).first as Map)['content']
            as String;
    expect(system, startsWith('$prompt只输出JSON'));
  });

  test('fold label', () {
    final r = applyPolicy(_api(ad: .853), _raw, const BreezeConfig(), const []);
    expect(foldLabel(_raw, r), '测试UP · 广告 · 85%');
  });
}
