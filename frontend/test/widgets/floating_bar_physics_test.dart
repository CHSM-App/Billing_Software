import 'package:Vittam/widgets/floating_bar_physics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The floating app bar soaks up a drag before the list moves, in both
/// directions, and stays put when floating is switched off.
void main() {
  test('drag folds the bar first, the rest scrolls the list', () {
    final bar = AnimationController(vsync: const TestVSync(), value: 1);
    var float = true;
    final physics =
        FloatingBarPhysics(bar: bar, extent: () => 50, canFloat: () => float);
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 100,
      viewportDimension: 500,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    // Finger up 30: all spent folding the bar, list doesn't move.
    expect(physics.applyPhysicsToUserOffset(metrics, -30), 0);
    expect(bar.value, closeTo(0.4, 1e-9));
    // Finger up 40 more: 20 finishes folding, 20 scrolls the list.
    expect(physics.applyPhysicsToUserOffset(metrics, -40), closeTo(-20, 1e-9));
    expect(bar.value, 0);
    // Finger down 60: 50 brings the bar back, 10 scrolls the list.
    expect(physics.applyPhysicsToUserOffset(metrics, 60), closeTo(10, 1e-9));
    expect(bar.value, 1);

    // Pinned (search open / wide layout): the list gets the whole drag.
    float = false;
    expect(physics.applyPhysicsToUserOffset(metrics, -30), -30);
    expect(bar.value, 1);
    bar.dispose();
  });

  // The Items-page bug: a quick flick folded the app bar but left the tab
  // row (and search box) showing. The fling must carry the whole header away,
  // and coming back to the top must open it all again.
  testWidgets('a flick folds the whole header; the top opens it',
      (tester) async {
    late FoldingHeader header;
    await tester
        .pumpWidget(MaterialApp(home: _Host(onHeader: (h) => header = h)));

    Size sizeOf(String key) => tester.getSize(find.byKey(ValueKey(key)));
    expect(sizeOf('top').height, 100);
    expect(sizeOf('search').height, 50);

    await tester.fling(find.text('row 0'), const Offset(0, -60), 2000);
    await tester.pumpAndSettle();
    expect(header.bar.value, 0);
    expect(sizeOf('top').height, 0);
    expect(sizeOf('search').height, 0);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 4000);
    await tester.pumpAndSettle();
    expect(header.bar.value, 1);
    expect(sizeOf('top').height, 100);
  });

  testWidgets('wrap(): tab lists fold the header, sideways swipes do not',
      (tester) async {
    late FoldingHeader header;
    await tester
        .pumpWidget(MaterialApp(home: _WrapHost(onHeader: (h) => header = h)));

    // A sideways swipe to the second tab leaves the header alone.
    await tester.drag(find.text('a 0'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('b 0'), findsOneWidget);
    expect(header.bar.value, 1);

    // A slow vertical drag in that tab's list folds it (30 of its 50 px).
    final g = await tester.startGesture(tester.getCenter(find.text('b 2')));
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, -5));
      await tester.pump();
    }
    expect(header.bar.value, lessThan(1));
    await g.up();
  });
}

/// Orders / Kitchen: lists built by other widgets, inside a swipeable tab view.
class _WrapHost extends StatefulWidget {
  const _WrapHost({required this.onHeader});
  final ValueChanged<FoldingHeader> onHeader;
  @override
  State<_WrapHost> createState() => _WrapHostState();
}

class _WrapHostState extends State<_WrapHost> with TickerProviderStateMixin {
  late final header =
      FoldingHeader(vsync: this, extent: () => 50, canFold: () => true);
  late final tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onHeader(header);
  }

  @override
  void dispose() {
    tabs.dispose();
    header.dispose();
    super.dispose();
  }

  Widget list(String tag) => ListView.builder(
        // Its own physics, as the real tab screens have — must still chain
        // onto the folding physics handed down by wrap().
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 100,
        itemExtent: 40,
        itemBuilder: (_, i) => Text('$tag $i'),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          FoldAway(
            key: const ValueKey('title'),
            bar: header.bar,
            child: const SizedBox(height: 50),
          ),
          Expanded(
            child: header.wrap(
              context,
              TabBarView(controller: tabs, children: [list('a'), list('b')]),
            ),
          ),
        ]),
      );
}

class _Host extends StatefulWidget {
  const _Host({required this.onHeader});
  final ValueChanged<FoldingHeader> onHeader;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TickerProviderStateMixin {
  late final header =
      FoldingHeader(vsync: this, extent: () => 150, canFold: () => true);

  @override
  void initState() {
    super.initState();
    widget.onHeader(header);
  }

  @override
  void dispose() {
    header.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          FoldAway(
            key: const ValueKey('top'),
            bar: FoldAway.slice(header.bar, below: 50, height: 100, total: 150),
            child: const SizedBox(height: 100),
          ),
          FoldAway(
            key: const ValueKey('search'),
            bar: FoldAway.slice(header.bar, below: 0, height: 50, total: 150),
            child: const SizedBox(height: 50),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: header.onScroll,
              child: ListView.builder(
                physics: header.physics,
                itemCount: 100,
                itemExtent: 40,
                itemBuilder: (_, i) => Text('row $i'),
              ),
            ),
          ),
        ]),
      );
}
