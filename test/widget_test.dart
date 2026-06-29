import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lockin/app_blocker');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getState':
              return <String, dynamic>{
                'isBlockingActive': false,
                'blockedPackages': <String>[],
                'usageByPackage': <String, int>{},
                'unlockText': '',
              };
            case 'getInstalledApps':
              return <Map<String, dynamic>>[];
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('shows Lockin home screen', (tester) async {
    await tester.pumpWidget(const LockinApp());
    await tester.pump();

    expect(find.text('Lockin'), findsOneWidget);
    expect(find.text('STATUS: UGASENO'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
