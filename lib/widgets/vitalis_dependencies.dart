import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import '../providers/generation_provider.dart';
import '../providers/health_provider.dart';
import '../providers/model_library_provider.dart';
import '../providers/note_provider.dart';
import '../providers/persona_provider.dart';
import '../providers/theme_provider.dart';
import '../services/chat_state_controller.dart';
import '../services/hardware_sentinel_service.dart';
import '../services/model_download_manager.dart';
import '../services/model_download_service.dart';
import '../services/model_downloader.dart';
import '../services/model_hub_client.dart';
import '../services/model_registry_service.dart';
import '../services/model_warmup_service.dart';
import '../services/startup_access_guard.dart';
import '../services/selected_model_readiness.dart';

typedef WarmupServiceFactory =
    ModelWarmupService Function(
      HardwareSentinelService sentinel,
      ModelRegistryService registry,
    );
typedef ChatControllerFactory =
    ChatStateController Function(HardwareSentinelService sentinel);

/// The app's existing Provider graph, isolated from routing for lifecycle tests.
class VitalisDependencies extends StatelessWidget {
  const VitalisDependencies({
    super.key,
    required this.sentinel,
    required this.child,
    this.createWarmup,
    this.createController,
    this.startupAccess,
    this.selectedModel,
  });

  final HardwareSentinelService sentinel;
  final Widget child;
  final WarmupServiceFactory? createWarmup;
  final ChatControllerFactory? createController;
  final StartupAccessGuard? startupAccess;
  final SelectedModelReadiness? selectedModel;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StartupAccessGuard?>.value(value: startupAccess),
        if (selectedModel != null)
          ChangeNotifierProvider<SelectedModelReadiness>.value(
            value: selectedModel!,
          ),
        Provider<ModelRegistryService>(
          create: (_) => ModelRegistryService(
            checkProbeSafety: sentinel.checkHeavyOperation,
            probeSafetyChanges: sentinel.onHealthChanged,
          ),
          dispose: (_, registry) => registry.dispose(),
        ),
        ChangeNotifierProvider<ModelWarmupService>(
          create: (context) {
            final registry = context.read<ModelRegistryService>();
            return createWarmup?.call(sentinel, registry) ??
                ModelWarmupService(sentinel: sentinel, modelRegistry: registry);
          },
        ),
        ChangeNotifierProvider(
          create: (context) => GenerationProvider(
            controller:
                createController?.call(sentinel) ??
                ChatStateController(sentinel: sentinel),
            warmup: context.read<ModelWarmupService>(),
            startupAccess: startupAccess,
          ),
        ),
        ChangeNotifierProxyProvider<GenerationProvider, ChatProvider>(
          create: (context) => ChatProvider(
            modelRegistry: context.read<ModelRegistryService>(),
            startupAccess: startupAccess,
            modelReadiness: selectedModel,
          ),
          update: (_, generation, chat) {
            chat!.setGenerationProvider(generation);
            return chat;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => NoteProvider(startupAccess: startupAccess),
        ),
        ChangeNotifierProvider(
          create: (context) => PersonaProvider(
            startupAccess: startupAccess,
            onCommittedChange: (id, persona) =>
                context.read<ChatProvider>().applyPersonaChange(id, persona),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ModelDownloadService(
            downloader: ModelDownloader(
              sentinel: sentinel,
              environment: AndroidModelDownloadEnvironment(
                registry: context.read<ModelRegistryService>(),
              ),
              resetRegistry: context.read<ModelRegistryService>(),
            ),
          ),
        ),
        Provider<ModelDownloadManager>(
          create: (context) => ModelDownloadManager(
            jobs: DatabaseDownloadJobStore(),
            files: const ApplicationModelFileStore(),
            transfers: Platform.isAndroid
                ? const AndroidDurableTransferAdapter()
                : DioTransferAdapter(),
            registry: context.read<ModelRegistryService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ModelLibraryProvider(
            hub: HuggingFaceModelHubClient(),
            registry: context.read<ModelRegistryService>(),
            downloads: context.read<ModelDownloadManager>(),
            selectedModel: selectedModel,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => HealthProvider(sentinel: sentinel),
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: child,
    );
  }
}
