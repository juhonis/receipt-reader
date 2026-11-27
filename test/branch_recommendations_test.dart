import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:receipt_domain/receipt_domain.dart';
import 'package:receipt_parser/receipt_parser.dart';
import 'package:receipt_reader/app.dart';
import 'package:receipt_reader/branch_recommendations.dart';
import 'package:receipt_reader/review_page.dart';
import 'package:receipt_reader/receipt_import.dart';

import 'support/fake_store.dart';
import 'ocr_review_guidance_test.dart' show reveal;

class _BranchStore extends FakeStore {
  _BranchStore(this.choices);
  final List<ReceiptBranch> choices;
  Completer<void>? gate;
  @override
  Future<List<ReceiptBranch>> branches() async {
    await gate?.future;
    return choices;
  }
}

ReceiptBranch _branch(String name) => ReceiptBranch(
  id: DurableId.generate(),
  name: name,
  revision: RevisionId(DurableId.generate(), BigInt.one),
);

ReceiptDraft _draft({String name = 'TEST MARKET NORTH'}) => parseReceipt(
  OcrPage(800, 600, [
    OcrWord(name, PixelBox(20, 20, 400, 36)),
    OcrWord('19.11.2026', PixelBox(20, 80, 200, 96)),
    OcrWord('TEST PRODUCT', PixelBox(20, 150, 200, 166)),
    OcrWord('2,00', PixelBox(650, 150, 720, 166)),
    OcrWord('YHTEENSÄ', PixelBox(20, 200, 200, 216)),
    OcrWord('2,00', PixelBox(650, 200, 720, 216)),
  ]),
  itemTop: 120,
  priceColumnLeft: 600,
);

Future<void> _open(
  WidgetTester tester,
  _BranchStore store, {
  Future<OcrPage> Function(ReceiptEvidence)? recognizer,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // In-memory synthetic pixels and seeded geometry test review behavior, not
  // engine accuracy. This source is portable to Android and Windows.
  final evidence = (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(800, 600);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return ReceiptEvidence.decode(bytes!.buffer.asUint8List());
  }))!;
  addTearDown(evidence.dispose);
  await tester.pumpWidget(const ReceiptReaderApp());
  Navigator.of(tester.element(find.text('Kokeile kuitin tarkistusta'))).push(
    MaterialPageRoute<void>(
      builder: (_) => ReviewPage(
        draft: recognizer == null ? _draft() : null,
        evidence: evidence,
        recognizer: recognizer,
        store: store,
      ),
    ),
  );
  // A pending database load leaves an indeterminate progress indicator.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

String _name(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('branch'))).controller!.text;

String? _choice(WidgetTester tester) => tester
    .state<FormFieldState<String>>(find.byKey(const Key('ocr-branch')))
    .value;

void main() {
  test('matching preserves punctuation, diacritics and full-name identity', () {
    final exact = _branch('test   märket, north');
    final duplicate = _branch('TEST MÄRKET, NORTH');
    final candidates = [ReceiptBranchCandidate('  TEST MÄRKET, NORTH  ', [])];
    expect(
      recommendedBranches(candidates, [
        exact,
        duplicate,
        _branch('TEST MARKET, NORTH'),
        _branch('TEST MÄRKET NORTH'),
        _branch('TEST MÄRKET, NORTH EAST'),
        _branch('TEST MÄRKET,'),
      ]),
      [exact, duplicate],
    );
  });
  runBranchRecommendationTests();
}

/// Also run on both native platforms; all data stays in a fake store.
void runBranchRecommendationTests() {
  testWidgets(
    'unique header match selects the existing identity without saving',
    (tester) async {
      final match = _branch('test   market north');
      final store = _BranchStore([match, _branch('TEST MARKET SOUTH')]);
      await _open(tester, store);
      await tester.pumpAndSettle();
      await reveal(tester, 'branch');
      expect(_name(tester), match.name);
      expect(_choice(tester), match.id.value);
      expect(find.byKey(const Key('ocr-branch-auto-selected')), findsOneWidget);
      expect(store.saved, isEmpty);
      await reveal(tester, 'ocr-save');
      expect(store.saved, isEmpty);
      await tester.tap(find.byKey(const Key('ocr-save')));
      await tester.pumpAndSettle();
      expect(store.saved.single.document.snapshot.branch.id, match.id);
      expect(
        store.saved.single.document.snapshot.branch.revision,
        match.revision,
      );
    },
  );

  testWidgets(
    'duplicate normalized names remain selectable and do not auto-select',
    (tester) async {
      final matches = [
        _branch('TEST MARKET NORTH'),
        _branch('test market north'),
      ];
      final store = _BranchStore(matches);
      await _open(tester, store);
      await tester.pumpAndSettle();
      await reveal(tester, 'branch');
      expect(_name(tester), isEmpty);
      expect(_choice(tester), isNull);
      expect(find.byKey(const Key('ocr-branch-auto-selected')), findsNothing);
      await tester.tap(
        find.byKey(ValueKey('ocr-branch-match-${matches.last.id.value}')),
      );
      await tester.pumpAndSettle();
      expect(_choice(tester), matches.last.id.value);
      expect(_name(tester), matches.last.name);
      expect(store.saved, isEmpty);
    },
  );

  testWidgets(
    'unknown name needs an explicit action before new-branch fields fill',
    (tester) async {
      final store = _BranchStore([]);
      await _open(tester, store);
      await tester.pumpAndSettle();
      await reveal(tester, 'branch');
      expect(_name(tester), isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('ocr-branch-name-TEST MARKET NORTH')),
      );
      await tester.pumpAndSettle();
      expect(_choice(tester), 'new');
      expect(_name(tester), 'TEST MARKET NORTH');
      await tester.enterText(
        find.byKey(const Key('branch')),
        'My corrected branch',
      );
      await tester.pumpAndSettle();
      expect(_name(tester), 'My corrected branch');
      expect(store.saved, isEmpty);
    },
  );

  testWidgets(
    'recommendations wait for the database before selecting a branch',
    (tester) async {
      final store = _BranchStore([_branch('TEST MARKET NORTH')])
        ..gate = Completer<void>();
      await _open(tester, store);
      await revealWhileLoading(tester);
      expect(_name(tester), isEmpty);
      expect(find.byKey(const Key('ocr-branch')), findsNothing);
      store.gate!.complete();
      await tester.pumpAndSettle();
      expect(_name(tester), store.choices.single.name);
      expect(_choice(tester), store.choices.single.id.value);
    },
  );

  testWidgets(
    'explicit selection replaces automatic choice and clears its notice',
    (tester) async {
      final match = _branch('TEST MARKET NORTH'),
          other = _branch('TEST MARKET SOUTH');
      final store = _BranchStore([match, other]);
      await _open(tester, store);
      await tester.pumpAndSettle();
      await reveal(tester, 'ocr-branch');
      await tester.tap(find.byKey(const Key('ocr-branch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(other.name).last);
      await tester.pumpAndSettle();
      expect(_choice(tester), other.id.value);
      expect(_name(tester), other.name);
      expect(find.byKey(const Key('ocr-branch-auto-selected')), findsNothing);
    },
  );

  testWidgets('applying a layout updates an already mounted branch selector', (
    tester,
  ) async {
    final match = _branch('TEST MARKET NORTH');
    final store = _BranchStore([match]);
    await _open(
      tester,
      store,
      recognizer: (_) async => _draft().parseContext!.page,
    );
    await tester.pumpAndSettle();
    expect(_choice(tester), isNull);
    await tester.tap(find.byKey(const Key('recognize')));
    await tester.pumpAndSettle();
    await reveal(tester, 'ocr-use-layout');
    await tester.tap(find.byKey(const Key('ocr-use-layout')));
    await tester.pumpAndSettle();
    await reveal(tester, 'branch');
    expect(_name(tester), match.name);
    expect(_choice(tester), match.id.value);
  });

  testWidgets('a branch chosen during recognition survives the late result', (
    tester,
  ) async {
    final match = _branch('TEST MARKET NORTH'),
        other = _branch('TEST MARKET SOUTH');
    final result = Completer<OcrPage>();
    await _open(
      tester,
      _BranchStore([match, other]),
      recognizer: (_) => result.future,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recognize')));
    await tester.pump();
    await revealWhileLoading(tester);
    await tester.tap(find.byKey(const Key('ocr-branch')));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text(other.name).last);
    await tester.pump();
    result.complete(_draft().parseContext!.page);
    await tester.pumpAndSettle();
    expect(_name(tester), other.name);
    expect(_choice(tester), other.id.value);
    expect(find.byKey(const Key('ocr-branch-auto-selected')), findsNothing);
  });

  testWidgets('header suggestions fit compact screens with enlarged text', (
    tester,
  ) async {
    await _open(tester, _BranchStore([]));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 960);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await reveal(tester, 'ocr-branch-name-TEST MARKET NORTH');
    expect(tester.takeException(), isNull);
  });
}

Future<void> revealWhileLoading(WidgetTester tester) async {
  final list = find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;
  final position = tester.state<ScrollableState>(list).position;
  for (
    var i = 0;
    i < 80 && find.byKey(const Key('branch')).evaluate().isEmpty;
    i++
  ) {
    position.jumpTo((position.pixels + 200).clamp(0, position.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 20));
  }
}
