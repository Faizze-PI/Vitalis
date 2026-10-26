import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/providers/note_provider.dart';
import 'package:vitalis_app/providers/persona_provider.dart';
import 'package:vitalis_app/providers/theme_provider.dart';
import 'package:vitalis_app/services/model_download_service.dart';
import 'package:vitalis_app/services/model_downloader.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:vitalis_app/app_router.dart';

class MockSentinel implements HardwareSentinelService {
  @override
  int get currentLevel => 100;
  @override
  bool get isCharging => true;
  @override
  bool get isInSaveMode => false;
  @override
  bool get isDisposed => false;
  @override
  ConnectivityResult get connectivityType => ConnectivityResult.wifi;
  @override
  int get memoryPressureLevel => 0;
  @override
  bool isSafeForHeavyOperation() => true;
  @override
  bool isSafeForDownload() => true;
  @override
  String? unsafeReasonHeavy() => null;
  @override
  String? unsafeReasonDownload() => null;
  @override
  void checkHeavyOperation() {}
  @override
  void checkDownload() {}
  @override
  Stream<bool> get onHealthChanged => const Stream.empty();
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}

Widget makeTestApp({String initialRoute = '/'}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ChatProvider()),
      ChangeNotifierProvider(create: (_) => NoteProvider()),
      ChangeNotifierProvider(create: (_) => PersonaProvider()),
      ChangeNotifierProvider(
        create: (_) => ModelDownloadService(
          downloader: ModelDownloader(sentinel: MockSentinel()),
        ),
      ),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      title: 'Vitalis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      initialRoute: initialRoute,
      onGenerateRoute: onGenerateRoute,
    ),
  );
}

Future<void> initIntegrationTest() async {
  SharedPreferences.setMockInitialValues({});
}
