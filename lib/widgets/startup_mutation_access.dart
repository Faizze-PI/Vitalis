import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_deletion_error.dart';
import '../services/startup_access_guard.dart';
import '../utils/app_logger.dart';

/// Keeps visible controls in step with the same guard used by persistence.
/// Missing or unreadable permission evidence renders mutation controls disabled.
class StartupMutationAccess extends StatelessWidget {
  const StartupMutationAccess({super.key, required this.builder});

  final Widget Function(BuildContext context, bool canMutate) builder;

  static void reportFailure(BuildContext context, Object error) {
    AppLogger.instance.warning(
      'Saved content change failed (${error.runtimeType})',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          error is StartupAccessDenied
              ? 'Editing is unavailable while the app is recovering.'
              : error is ChatDeletionError
              ? error.message
              : 'The change could not be saved. Please retry.',
        ),
      ),
    );
  }

  bool _allowed(StartupAccessGuard? guard) {
    if (guard == null) return false;
    try {
      return guard.allows(StartupAccessOperation.mutateContent);
    } catch (error) {
      AppLogger.instance.warning(
        'Content permission unavailable (${error.runtimeType})',
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final guard = context.watch<StartupAccessGuard?>();
    final changes = guard?.changes;
    if (changes == null) return builder(context, _allowed(guard));
    return ListenableBuilder(
      listenable: changes,
      builder: (context, _) => builder(context, _allowed(guard)),
    );
  }
}
