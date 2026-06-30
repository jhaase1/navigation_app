import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/models/person.dart';
import 'package:navigation_app/models/role.dart';
import 'package:navigation_app/models/scene.dart';
import 'package:navigation_app/models/service_order.dart';
import 'package:navigation_app/widgets/order_tab.dart';

Widget _buildTab({
  List<ServiceOrder> orders = const [],
  List<Role> roles = const [],
  List<Person> people = const [],
  List<Scene> scenes = const [],
  ValueChanged<String>? onResponse,
}) {
  return MaterialApp(
    home: Scaffold(
      body: OrderTab(
        cameras: [],
        people: people,
        roles: roles,
        scenes: scenes,
        orders: orders,
        rolandService: null,
        rolandConnected: null,
        onResponse: onResponse ?? (_) {},
      ),
    ),
  );
}

void main() {
  group('OrderTab — empty state', () {
    testWidgets('shows placeholder when no orders exist', (tester) async {
      await tester.pumpWidget(_buildTab());
      expect(find.text('No service orders configured'), findsOneWidget);
    });

    testWidgets('shows prompt to select after orders are provided',
        (tester) async {
      final order = ServiceOrder(id: 'o1', name: 'Mass', moments: []);
      await tester.pumpWidget(_buildTab(orders: [order]));
      expect(find.text('Select an order above'), findsOneWidget);
    });
  });

  group('OrderTab — order selection', () {
    testWidgets('selecting an order shows its moment tiles', (tester) async {
      final order = ServiceOrder(
        id: 'o1',
        name: 'Mass',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 3),
          const OrderMoment(id: 'm2', type: MomentType.macro, macroNumber: 7),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [order]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Macro 3'), findsOneWidget);
      expect(find.textContaining('Macro 7'), findsOneWidget);
    });

    testWidgets('moment tiles are numbered starting at 1', (tester) async {
      final order = ServiceOrder(
        id: 'o1',
        name: 'Vigil',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 1),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [order]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vigil').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('1.'), findsOneWidget);
    });

    testWidgets('switching orders resets current moment index', (tester) async {
      final orderA = ServiceOrder(
        id: 'a',
        name: 'Order A',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 1),
        ],
      );
      final orderB = ServiceOrder(
        id: 'b',
        name: 'Order B',
        moments: [
          const OrderMoment(id: 'm2', type: MomentType.macro, macroNumber: 2),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [orderA, orderB]));

      // Select Order A
      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Order A').last);
      await tester.pumpAndSettle();

      // Switch to Order B — progress counter should be gone
      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Order B').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('/ 1'), findsNothing);
      expect(find.text('Tap a moment or Next to begin'), findsOneWidget);
    });
  });

  group('OrderTab — sub-order flattening', () {
    testWidgets('sub-order moments are inlined into parent', (tester) async {
      final sub = ServiceOrder(
        id: 'sub',
        name: 'Readings',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 1),
          const OrderMoment(id: 'm2', type: MomentType.macro, macroNumber: 2),
        ],
      );
      final main = ServiceOrder(
        id: 'main',
        name: 'Main',
        moments: [
          const OrderMoment(
              id: 'm3', type: MomentType.subOrder, subOrderId: 'sub'),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [sub, main]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main').last);
      await tester.pumpAndSettle();

      // Sub-order expands to its 2 macro moments
      expect(find.textContaining('Macro 1'), findsOneWidget);
      expect(find.textContaining('Macro 2'), findsOneWidget);
    });

    testWidgets('deeply nested sub-orders are flattened', (tester) async {
      final inner = ServiceOrder(
        id: 'inner',
        name: 'Inner',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 10),
        ],
      );
      final mid = ServiceOrder(
        id: 'mid',
        name: 'Mid',
        moments: [
          const OrderMoment(
              id: 'm2', type: MomentType.subOrder, subOrderId: 'inner'),
        ],
      );
      final outer = ServiceOrder(
        id: 'outer',
        name: 'Outer',
        moments: [
          const OrderMoment(
              id: 'm3', type: MomentType.subOrder, subOrderId: 'mid'),
          const OrderMoment(id: 'm4', type: MomentType.macro, macroNumber: 20),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [inner, mid, outer]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outer').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Macro 10'), findsOneWidget);
      expect(find.textContaining('Macro 20'), findsOneWidget);
    });

    testWidgets('self-referencing order does not cause infinite loop',
        (tester) async {
      final cyclic = ServiceOrder(
        id: 'cyc',
        name: 'Cyclic',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 5),
          const OrderMoment(
              id: 'm2', type: MomentType.subOrder, subOrderId: 'cyc'),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [cyclic]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cyclic').last);
      await tester.pumpAndSettle();

      // The self-referential subOrder is skipped; only the macro appears
      expect(find.textContaining('Macro 5'), findsOneWidget);
      expect(find.textContaining('Macro 5'), findsNWidgets(1));
    });

    testWidgets('mutual cycle between two orders does not infinite loop',
        (tester) async {
      final orderA = ServiceOrder(
        id: 'a',
        name: 'Order A',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 1),
          const OrderMoment(
              id: 'm2', type: MomentType.subOrder, subOrderId: 'b'),
        ],
      );
      final orderB = ServiceOrder(
        id: 'b',
        name: 'Order B',
        moments: [
          const OrderMoment(
              id: 'm3', type: MomentType.subOrder, subOrderId: 'a'),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [orderA, orderB]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Order A').last);
      await tester.pumpAndSettle();

      // Only Order A's macro; Order B's subOrder→A is cut by cycle guard
      expect(find.textContaining('Macro 1'), findsOneWidget);
    });
  });

  group('OrderTab — role assignment panel', () {
    testWidgets('role assignment panel appears when order has roleScene moments',
        (tester) async {
      final role = Role(id: 'r1', name: 'Reader 1');
      final scene = Scene(id: 's1', name: 'Lectern');
      final order = ServiceOrder(
        id: 'o1',
        name: 'Mass',
        moments: [
          const OrderMoment(
              id: 'm1',
              type: MomentType.roleScene,
              roleId: 'r1',
              sceneId: 's1'),
        ],
      );
      await tester.pumpWidget(
          _buildTab(orders: [order], roles: [role], scenes: [scene]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      expect(
          find.text('Role assignments for this service'), findsOneWidget);
      expect(find.text('Reader 1'), findsWidgets);
    });

    testWidgets(
        'role assignment panel does not appear for macro-only order',
        (tester) async {
      final order = ServiceOrder(
        id: 'o1',
        name: 'Macros Only',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 1),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [order]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Macros Only').last);
      await tester.pumpAndSettle();

      expect(
          find.text('Role assignments for this service'), findsNothing);
    });

    testWidgets('each unique role referenced in the order gets a row',
        (tester) async {
      final roles = [
        Role(id: 'r1', name: 'Reader 1'),
        Role(id: 'r2', name: 'Priest'),
      ];
      final order = ServiceOrder(
        id: 'o1',
        name: 'Mass',
        moments: [
          const OrderMoment(
              id: 'm1',
              type: MomentType.roleScene,
              roleId: 'r1',
              sceneId: 's1'),
          const OrderMoment(
              id: 'm2',
              type: MomentType.roleScene,
              roleId: 'r2',
              sceneId: 's2'),
          // r1 appears again — should not add a duplicate row
          const OrderMoment(
              id: 'm3',
              type: MomentType.roleScene,
              roleId: 'r1',
              sceneId: 's3'),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [order], roles: roles));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      expect(find.text('Reader 1'), findsOneWidget);
      expect(find.text('Priest'), findsOneWidget);
    });
  });

  group('OrderTab — Prev/Next navigation', () {
    testWidgets('Next button fires first moment and advances counter',
        (tester) async {
      final responses = <String>[];
      final order = ServiceOrder(
        id: 'o1',
        name: 'Mass',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 1),
          const OrderMoment(id: 'm2', type: MomentType.macro, macroNumber: 2),
        ],
      );
      await tester.pumpWidget(
          _buildTab(orders: [order], onResponse: responses.add));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      // Counter not shown before first Next
      expect(find.text('Tap a moment or Next to begin'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('Prev button is disabled before any step', (tester) async {
      final order = ServiceOrder(
        id: 'o1',
        name: 'Mass',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 1),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [order]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      final prevButton = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Prev'));
      expect(prevButton.onPressed, isNull);
    });

    testWidgets('Next button is disabled at last moment', (tester) async {
      final order = ServiceOrder(
        id: 'o1',
        name: 'Mass',
        moments: [
          const OrderMoment(id: 'm1', type: MomentType.macro, macroNumber: 1),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [order]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      // Advance to the only moment
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // FilledButton.icon creates a private subclass; use a predicate instead
      final disabledNext = find.byWidgetPredicate(
        (w) => w is FilledButton && w.onPressed == null,
        description: 'disabled FilledButton (Next)',
      );
      expect(disabledNext, findsOneWidget);
    });
  });

  group('OrderTab — warning indicators', () {
    testWidgets('warning icon shown for macro moment with no number set',
        (tester) async {
      final order = ServiceOrder(
        id: 'o1',
        name: 'Mass',
        moments: [
          const OrderMoment(
              id: 'm1', type: MomentType.macro), // macroNumber is null
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [order]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('no warning icon when macro number is set', (tester) async {
      final order = ServiceOrder(
        id: 'o1',
        name: 'Mass',
        moments: [
          const OrderMoment(
              id: 'm1', type: MomentType.macro, macroNumber: 3),
        ],
      );
      await tester.pumpWidget(_buildTab(orders: [order]));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mass').last);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber), findsNothing);
    });
  });
}
