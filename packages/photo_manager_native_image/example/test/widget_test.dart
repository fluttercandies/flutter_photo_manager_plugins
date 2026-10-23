import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('gallery page renders without crashing', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Native thumbnails'), findsOneWidget);
  });
}
