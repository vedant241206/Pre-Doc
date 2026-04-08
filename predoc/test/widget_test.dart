import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predoc/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Predoc app smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PredocApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
