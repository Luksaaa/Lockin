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
                'usageLimitMs': 40 * 60 * 1000,
                'usageWindowMs': 4 * 60 * 60 * 1000,
                'isTestMode': false,
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

    expect(find.text('40 min'), findsOneWidget);
    expect(find.text('4 h'), findsOneWidget);
    expect(find.text('raspon 30 min-30 min'), findsOneWidget);
    expect(find.text('STATUS: UGASENO'), findsOneWidget);
    expect(find.text('Dodaj aplikacije'), findsOneWidget);
  });
}
