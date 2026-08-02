// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yolguven/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App builds successfully smoke test', (
    WidgetTester tester,
  ) async {
    const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geolocatorChannel, (call) async {
          if (call.method != 'getCurrentPosition') {
            throw MissingPluginException('Unsupported method: ${call.method}');
          }

          return <String, dynamic>{
            'latitude': 38.6810,
            'longitude': 39.2264,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'accuracy': 1.0,
            'altitude': 0.0,
            'altitude_accuracy': 1.0,
            'heading': 0.0,
            'heading_accuracy': 1.0,
            'speed': 0.0,
            'speed_accuracy': 1.0,
            'is_mocked': true,
          };
        });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(geolocatorChannel, null);
    });

    // Build our app and trigger a frame.
    await tester.pumpWidget(const PotholeApp());
    await tester.pump();

    // Verify that the app builds without crashing
    expect(find.byType(PotholeApp), findsOneWidget);
  });
}
