import '../models/startup_capabilities.dart';
import 'selected_model_readiness.dart';
import 'startup_coordinator.dart';

/// Combines completed bootstrap prerequisites with the currently selected model.
/// Changing chats cannot inherit the readiness of the previously selected model.
final class StartupCapabilitySource {
  const StartupCapabilitySource(this.coordinator, this.selectedModel);

  final StartupCoordinator coordinator;
  final SelectedModelReadiness selectedModel;

  StartupCapabilities snapshot() {
    final bootstrap = coordinator.capabilities;
    return bootstrap.withModelReadiness(
      selectedModel.modelId == null
          ? StartupModelReadiness.unknown
          : selectedModel.readiness,
    );
  }
}
