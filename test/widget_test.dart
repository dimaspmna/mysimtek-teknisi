// This is a basic Flutter widget test.

import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'package:mysimtek_teknisi/app.dart';
import 'package:mysimtek_teknisi/core/services/api_service.dart';
import 'package:mysimtek_teknisi/core/services/storage_service.dart';
import 'package:mysimtek_teknisi/core/providers/auth_provider.dart';

void main() {
  testWidgets('App starts with login screen', (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'test-api-key',
        appId: '1:1234567890:android:testapp',
        messagingSenderId: '1234567890',
        projectId: 'test-project',
      ),
    );

    final storageService = StorageService();
    final apiService = ApiService(storageService);

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: apiService),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(apiService, storageService),
          ),
        ],
        child: const MySimtekTeknisiApp(),
      ),
    );

    // Let splash/auth async init complete with bounded frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify that login screen is shown
    expect(find.text('MySimtek - Teknisi'), findsOneWidget);
  });
}
