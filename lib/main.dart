import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'core/services/api_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/storage_service.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/attendance_provider.dart';
import 'core/providers/gps_tracking_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Set up communication port for flutter_foreground_task background isolate
  FlutterForegroundTask.initCommunicationPort();
  await initializeDateFormatting('id', null);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final storageService = StorageService();
  final apiService = ApiService(storageService);

  await FcmService.initialize(apiService);

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: apiService),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(apiService, storageService),
        ),
        ChangeNotifierProvider(create: (_) => AttendanceProvider(apiService)),
        ChangeNotifierProvider(create: (_) => GpsTrackingProvider()),
      ],
      child: const MySimtekTeknisiApp(),
    ),
  );
}
