import 'package:flutter/material.dart';

import '../services/startup_coordinator.dart';

class StartupShell extends StatefulWidget {
  const StartupShell({
    super.key,
    required this.coordinator,
    required this.readyBuilder,
  });

  final StartupCoordinator coordinator;
  final WidgetBuilder readyBuilder;

  @override
  State<StartupShell> createState() => _StartupShellState();
}

class _StartupShellState extends State<StartupShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.coordinator.start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.coordinator,
      builder: (context, _) {
        if (widget.coordinator.canEnterApp) {
          return widget.readyBuilder(context);
        }
        final failed = widget.coordinator.state == StartupState.failed;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Semantics(
                    liveRegion: true,
                    label: failed
                        ? 'Vitalis startup needs attention'
                        : 'Vitalis is starting',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          failed
                              ? Icons.storage_rounded
                              : Icons.hourglass_top_rounded,
                          size: 56,
                          color: failed ? Colors.orange : null,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          failed
                              ? 'Vitalis needs attention'
                              : 'Preparing Vitalis',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.coordinator.failure ??
                              'Opening your local data safely. This does not load a model.',
                          textAlign: TextAlign.center,
                        ),
                        if (!failed) ...[
                          const SizedBox(height: 24),
                          const CircularProgressIndicator(),
                        ],
                        if (failed) ...[
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: widget.coordinator.canRetry
                                ? widget.coordinator.start
                                : null,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry startup'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
