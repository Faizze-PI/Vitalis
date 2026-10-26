// ARCHITECTURE: main.dart is the Composition Root for dependency injection.
// All services and providers are wired here with mandatory constructor injection.
// Singletons: AppLogger, HardwareSentinelService (app-scoped).
// Injectable: All other services/providers (created in main()).
// Flow: DatabaseHelper → HardwareSentinelService → ModelWarmupService → Providers.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'services/hardware_sentinel_service.dart';
import 'services/legacy_model_preference_migration.dart';
import 'services/startup_coordinator.dart';
import 'models/bundled_model_manifest.dart';
import 'models/model_descriptor.dart';
import 'services/model_startup_inspector.dart';
import 'services/selected_model_readiness.dart';
import 'services/startup_access_guard.dart';
import 'services/startup_capability_source.dart';
import 'services/application_error_reporter.dart';
import 'app_router.dart';
import 'database/database_helper.dart';
import 'utils/app_logger.dart';
import 'widgets/startup_shell.dart';
import 'widgets/vitalis_dependencies.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BundledModelManifest.validate();
  final sentinel = HardwareSentinelService.instance;
  final database = DatabaseHelper.instance;
  final inspector = ModelStartupInspector(
    findModel: (id) async {
      final row = await database.getModel(id);
      return row == null ? null : ModelDescriptor.fromMap(row);
    },
    modelFiles: database.getModelFiles,
  );
  final selectedModel = SelectedModelReadiness(inspector.inspect);

  final errorReporter = ApplicationErrorReporter(logger: AppLogger.instance);
  FlutterError.onError = errorReporter.framework;
  PlatformDispatcher.instance.onError = errorReporter.platform;

  final startup = StartupCoordinator(
    openDatabase: () async {
      await database.database;
    },
    loadLogger: () async {
      await AppLogger.instance.loadPersistedState();
      _configureNativeDiagnostics();
    },
    migrateLegacyPreferences: () async {
      await LegacyModelPreferenceMigration().run();
    },
    initializeSafety: sentinel.init,
    assessModel: () =>
        selectedModel.assessForBootstrap(BundledModelManifest.id),
    traceSink: AppLogger.instance.infoSync,
  );
  final startupAccess = StartupAccessGuard(
    StartupCapabilitySource(startup, selectedModel).snapshot,
    changes: Listenable.merge([startup, selectedModel]),
  );
  runApp(
    StartupShell(
      coordinator: startup,
      readyBuilder: (_) => VitalisApp(
        sentinel: sentinel,
        startupAccess: startupAccess,
        selectedModel: selectedModel,
      ),
    ),
  );
}

void _configureNativeDiagnostics() {
  NativeLog.sink = kDebugMode
      ? (level, message) {
          if (level == NativeLogLevel.error) {
            unawaited(AppLogger.instance.error('native: $message'));
          } else if (level == NativeLogLevel.warning) {
            unawaited(AppLogger.instance.warning('native: $message'));
          } else {
            unawaited(AppLogger.instance.info('native: $message'));
          }
        }
      : null;
}

class VitalisApp extends StatelessWidget {
  final HardwareSentinelService sentinel;
  final StartupAccessGuard startupAccess;
  final SelectedModelReadiness selectedModel;

  const VitalisApp({
    super.key,
    required this.sentinel,
    required this.startupAccess,
    required this.selectedModel,
  });

  @override
  Widget build(BuildContext context) {
    return VitalisDependencies(
      sentinel: sentinel,
      startupAccess: startupAccess,
      selectedModel: selectedModel,
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Vitalis',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeProvider.mode,
            initialRoute: AppRoutes.setup,
            onGenerateRoute: onGenerateRoute,
          );
        },
      ),
    );
  }
}
