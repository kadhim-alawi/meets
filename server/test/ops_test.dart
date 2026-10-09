import 'dart:async';
import 'dart:io';

import 'package:meets_core/meets_core.dart';
import 'package:meets_server/meets_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

QlooClient previewClient() => QlooClient(apiKey: 'preview', mode: 'preview', transport: previewTransport, minInterval: Duration.zero);

void main() {
  test('appended traces keep unique sequence numbers', () {
    RunEvent e(int seq) => RunEvent(seq: seq, at: DateTime(2026), kind: 'step', title: 's$seq');
    final merged = RunManager.appendTrace([e(1), e(2), e(3)], [e(1), e(2)]);
    expect(merged.map((x) => x.seq), [1, 2, 3, 4, 5]);
  });

  test('concurrency slots are handed over, never exceeded', () async {
    final tmp = await Directory.systemTemp.createTemp('meets_ops');
    addTearDown(() => tmp.delete(recursive: true));
    final images = ImageProxy();
    final runs = RunManager(client: previewClient(), llm: null, kits: KitStore(dataDir: tmp.path, images: images), images: images, maxConcurrent: 2);
    var active = 0, peak = 0;
    Future<void> job() => runs.withSlot(() async {
          active++;
          peak = active > peak ? active : peak;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          active--;
        });
    await Future.wait([for (var i = 0; i < 9; i++) job()]);
    expect(peak, 2);
  });

  group('client IP', () {
    Request req(Map<String, String> headers) => Request('GET', Uri.parse('http://x/api'), headers: headers);
    tearDown(() => trustedProxyHops = 1);

    test('uses the entry the trusted proxy appended, not a spoofed one', () {
      expect(clientIp(req({'x-forwarded-for': '1.1.1.1, 9.9.9.9'})), '9.9.9.9');
      trustedProxyHops = 2;
      expect(clientIp(req({'x-forwarded-for': 'spoof, 9.9.9.9, 10.0.0.1'})), '9.9.9.9');
    });

    test('prefers Fly-Client-IP', () {
      expect(clientIp(req({'fly-client-ip': '7.7.7.7', 'x-forwarded-for': 'spoof'})), '7.7.7.7');
    });
  });

  test('per-kit lock rejects a second concurrent update', () async {
    final tmp = await Directory.systemTemp.createTemp('meets_ops');
    addTearDown(() => tmp.delete(recursive: true));
    final images = ImageProxy();
    final kits = KitStore(dataDir: tmp.path, images: images);
    final client = previewClient();
    final kit = await CompsAgent(client: client).build(
      const Brief(format: WorkFormat.book, anchors: [AnchorInput(name: 'Piranesi', kind: EntityKind.book)]),
      ListEmitter(),
      kitId: 'lock1',
    );
    await kits.save(kit, const []);
    final runs = RunManager(client: client, llm: null, kits: kits, images: images);
    final first = runs.startRefine('lock1', 'only the last 3 years', 'a');
    expect(() => runs.startRefine('lock1', 'more indie', 'b'), throwsA(isA<LimitExceeded>()));
    for (var i = 0; i < 100 && !(runs.run(first.id)!.status.finished); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(runs.run(first.id)!.status, RunStatus.done);
    expect(kits.get('lock1')!.version, 2);
    expect(kits.get('lock1')!.brief.recencyYears, 3);
    // Lock released: a second refine is accepted now.
    expect(runs.startRefine('lock1', 'more indie', 'b').kitId, 'lock1');
  });

  test('heuristic refine: bounded years, word-boundary markets', () async {
    final kit = await CompsAgent(client: previewClient()).build(
      const Brief(format: WorkFormat.book, anchors: [AnchorInput(name: 'Piranesi', kind: EntityKind.book)]),
      ListEmitter(),
      kitId: 'h1',
    );
    expect(Refiner.heuristic(kit, 'only the last 80 years').brief.recencyYears, 50);
    expect(Refiner.heuristic(kit, 'more like Ukulele Kings').brief.market, 'US');
    final uk = Refiner.heuristic(kit, 'for the UK please');
    expect(uk.brief.market, 'GB');
    expect(uk.changes.where((c) => c.startsWith('Market')), hasLength(1));
  });
}
