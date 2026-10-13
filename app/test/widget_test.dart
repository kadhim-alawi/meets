import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meets_app/theme.dart';
import 'package:meets_app/widgets/common.dart';
import 'package:meets_app/widgets/kit/comps.dart';
import 'package:meets_app/widgets/kit/insights.dart';
import 'package:meets_app/widgets/timeline.dart';
import 'package:meets_core/meets_core.dart';

Widget host(Widget child, {double width = 1200}) => MaterialApp(
      theme: buildTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

Candidate cand(String id, String name, {double pop = 0.995, double aff = 0.9, int year = 2023, List<String> flags = const []}) =>
    Candidate(
      entity: Entity(id: id, name: name, kind: EntityKind.book, popularity: pop, affinity: aff, year: year, creator: 'Author $id'),
      fit: aff,
      size: SizeBand.of(pop),
      recency: RecencyBand.recent,
      score: aff,
      flags: flags,
      because: const ['Piranesi'],
    );

CompKit sampleKit() {
  final items = [
    cand('a', 'Babel'),
    cand('b', 'The Atlas Six', pop: 0.98),
    cand('c', 'Fourth Wing', pop: 0.99999, flags: const ['too_big']),
  ];
  return CompKit(
    id: 'k1',
    createdAt: DateTime(2026, 10, 9),
    brief: const Brief(format: WorkFormat.book, title: 'The Lantern Archive', anchors: [AnchorInput(name: 'Piranesi')]),
    mode: 'live',
    primary: DomainScan(kind: EntityKind.book, role: 'primary', items: items, filters: const ['Published 2021 or later']),
    pairing: CompPairing(a: items[0], b: items[1], why: 'Babel brings the scholarship.'),
    audience: const AudienceProfile(
      age: {AgeBand.under25: 0.2, AgeBand.from25to29: 0.4, AgeBand.over55: -0.3},
      male: -0.1,
      female: 0.1,
      descriptors: [TagRef(id: 'urn:tag:keyword:media:dark_academia', name: 'Dark academia')],
    ),
    markets: const [
      MarketCity(name: 'Austin', country: 'US', lat: 30, lon: -97, affinity: 0.99, popularity: 0.6, cells: 3, label: 'hidden_gem'),
    ],
    compCheck: [
      CompVerdict(
        input: "Harry Potter and the Sorcerer's Stone",
        resolved: const Entity(id: 'hp', name: "Harry Potter and the Sorcerer's Stone", kind: EntityKind.book, popularity: 0.99999, year: 1997),
        verdict: 'swap',
        reasons: const ['Top 0.01% in popularity.'],
        swap: items[1],
      ),
    ],
  );
}

void main() {
  testWidgets('comp card shows size, fit and sweet spot', (tester) async {
    await tester.pumpWidget(host(CompCard(candidate: cand('a', 'Babel'))));
    expect(find.text('Babel'), findsWidgets); // title + generated cover
    expect(find.textContaining('Breakout'), findsOneWidget);
    expect(find.text('Sweet spot'), findsOneWidget);
    expect(find.textContaining('Piranesi'), findsOneWidget);
  });

  testWidgets('comps section renders chart and flags blockbusters', (tester) async {
    await tester.pumpWidget(host(CompsSection(kit: sampleKit())));
    await tester.pumpAndSettle();
    expect(find.byType(SweetSpotChart), findsOneWidget);
    expect(find.text('Too big to comp'), findsOneWidget);
    expect(find.text('Published 2021 or later'), findsOneWidget);
  });

  testWidgets('comp check and audience sections', (tester) async {
    final kit = sampleKit();
    await tester.pumpWidget(host(Column(children: [CompCheckSection(kit: kit), AudienceSection(kit: kit)])));
    await tester.pumpAndSettle();
    expect(find.text('Swap'), findsOneWidget);
    expect(find.text('TRY INSTEAD'), findsOneWidget);
    expect(find.text('Hidden gem'), findsOneWidget);
    expect(find.text('Dark academia'), findsOneWidget);
  });

  testWidgets('timeline folds Qloo calls when asked', (tester) async {
    final events = [
      RunEvent(seq: 1, at: DateTime(2026), kind: 'step', title: 'Scanning'),
      RunEvent(seq: 2, at: DateTime(2026), kind: 'qloo', title: 'Call one', data: const {'path': '/v2/insights', 'count': 3}),
      RunEvent(seq: 3, at: DateTime(2026), kind: 'qloo', title: 'Call two', data: const {'path': '/search'}),
      RunEvent(seq: 4, at: DateTime(2026), kind: 'decision', title: 'Dug deeper'),
    ];
    await tester.pumpWidget(host(AgentTimeline(events: events, showCalls: false)));
    await tester.pumpAndSettle();
    expect(find.text('2 Qloo calls'), findsOneWidget);
    expect(find.text('Call one'), findsNothing);
    expect(find.text('Dug deeper'), findsOneWidget);
  });

  testWidgets('logo and pills render', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(body: Column(children: [MeetsLogo(), Pill('Sweet spot')])),
    ));
    expect(find.text('meets'), findsOneWidget);
  });
}
