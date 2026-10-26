import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/app_metrics.dart';
import '../constants/app_strings.dart';
import '../services/model_download_service.dart';
import '../services/model_registry_service.dart';
import '../services/selected_model_readiness.dart';
import '../services/startup_access_guard.dart';
import '../models/bundled_model_manifest.dart';
import '../database/database_helper.dart';
import '../utils/app_logger.dart';
import '../widgets/progress_bar.dart';
import '../app_router.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _isLoading = true;

  Future<void> _downloadModel(ModelDownloadService service) async {
    if (!mounted) return;
    try {
      await service.downloadModel();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Download could not be started or completed. Please retry.',
          ),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final installed =
          (await context.read<ModelRegistryService>().listModels()).any(
            (model) => model.isInstalled,
          );
      final hasSavedChats =
          (await DatabaseHelper.instance.getChats()).isNotEmpty;
      if ((installed || hasSavedChats) && mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.chat);
        return;
      }
    } catch (e) {
      AppLogger.instance.warningFailure('Setup registry check failed', e);
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    try {
      if (_isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      return Scaffold(
        appBar: AppBar(title: const Text('')),
        body: Consumer<ModelDownloadService>(
          builder: (context, downloadService, _) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      AppStrings.welcomeTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.welcomeSubtitle,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  if (downloadService.isDownloading) ...[
                    ProgressBar(
                      progress: downloadService.progress,
                      label: AppStrings.downloadingModel,
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      label:
                          '${(downloadService.progress * 100).toStringAsFixed(1)} percent',
                      child: Text(
                        '${(downloadService.progress * 100).toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (downloadService.downloadSpeed > 0)
                      Text(
                        '${downloadService.downloadSpeed.toStringAsFixed(1)} MB/s',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 16),
                    Semantics(
                      label: AppStrings.cancelDownload,
                      button: true,
                      child: TextButton(
                        onPressed: downloadService.isCancelling
                            ? null
                            : () => downloadService.cancelDownload(),
                        child: const Text(AppStrings.cancelDownload),
                      ),
                    ),
                  ] else if (downloadService.state ==
                      DownloadState.completed) ...[
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppStrings.modelReady,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      label: AppStrings.startChatting,
                      button: true,
                      child: ElevatedButton(
                        onPressed: () async {
                          final selected = context
                              .read<SelectedModelReadiness>();
                          await selected.select(
                            BundledModelManifest.id,
                            refresh: true,
                          );
                          if (!mounted) return;
                          final access = context.read<StartupAccessGuard?>();
                          if (!(access?.snapshot().canInfer ?? true)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Model verification is still needed. Open Model Library to recover it.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (mounted) {
                            Navigator.of(
                              context,
                            ).pushReplacementNamed(AppRoutes.chat);
                          }
                        },
                        child: const Text(AppStrings.startChatting),
                      ),
                    ),
                  ] else if (downloadService.state == DownloadState.error) ...[
                    const Icon(Icons.error, color: Colors.red, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      downloadService.statusMessage,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      label: AppStrings.retry,
                      button: true,
                      child: ElevatedButton(
                        onPressed: () => _downloadModel(downloadService),
                        child: const Text(AppStrings.retry),
                      ),
                    ),
                  ] else ...[
                    Semantics(
                      label: AppStrings.downloadModel,
                      button: true,
                      child: ElevatedButton(
                        onPressed: () => _downloadModel(downloadService),
                        child: const Text(AppStrings.downloadModel),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamed(AppRoutes.modelLibrary),
                    icon: const Icon(Icons.memory),
                    label: const Text('Open Model Library'),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } catch (e) {
      AppLogger.instance.errorFailure('SetupScreen build error', e);
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.healthRed,
              ),
              const SizedBox(height: AppMetrics.spaceMd),
              const Text(
                AppStrings.somethingWentWrong,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppMetrics.spaceXs),
              ElevatedButton(
                onPressed: () => setState(() {}),
                child: const Text(AppStrings.tryAgain),
              ),
            ],
          ),
        ),
      );
    }
  }
}
