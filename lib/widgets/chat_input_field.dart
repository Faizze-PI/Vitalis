import 'package:flutter/material.dart';
import '../constants/app_metrics.dart';
import '../constants/app_strings.dart';
import '../services/chat_state_controller.dart';

class ChatInputField extends StatefulWidget {
  const ChatInputField({
    super.key,
    required this.onSend,
    this.onStop,
    this.onAttach,
    this.status = ChatStatus.idle,
  });
  final Future<void> Function(String) onSend;
  final Future<void> Function()? onStop;
  final VoidCallback? onAttach;
  final ChatStatus status;

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  final _controller = TextEditingController();
  bool _submitting = false;
  int _draftRevision = 0;
  bool get _isActive =>
      widget.status == ChatStatus.generating ||
      widget.status == ChatStatus.interrupting;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_draftChanged);
  }

  void _draftChanged() {
    _draftRevision++;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_draftChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_isActive || _submitting || _controller.text.trim().isEmpty) return;
    final draft = _controller.text;
    _controller.clear();
    final submittedRevision = _draftRevision;
    setState(() => _submitting = true);
    try {
      await widget.onSend(draft.trim());
    } catch (_) {
      if (!mounted) return;
      if (_draftRevision == submittedRevision && _controller.text.isEmpty) {
        _controller.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message could not be sent. Please retry.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _stop() async {
    try {
      await widget.onStop?.call();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Stopping needs attention. Check the conversation status.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canSend =
        !_isActive && !_submitting && _controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.spaceSm,
          vertical: AppMetrics.spaceXs,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppMetrics.inputBorderRadius),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppMetrics.spaceXxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.onAttach != null)
                  IconButton(
                    tooltip: 'Attach note or choose persona',
                    onPressed: _isActive || _submitting
                        ? null
                        : widget.onAttach,
                    icon: const Icon(Icons.add_rounded),
                  ),
                Expanded(
                  child: Semantics(
                    label: AppStrings.messageInput,
                    textField: true,
                    child: TextField(
                      controller: _controller,
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: widget.status == ChatStatus.interrupting
                            ? AppStrings.stopping
                            : AppStrings.typeMessage,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppMetrics.spaceXs,
                          vertical: AppMetrics.spaceSm,
                        ),
                      ),
                      maxLines: 4,
                      minLines: 1,
                      enabled: !_isActive && !_submitting,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _isActive || _submitting
                          ? null
                          : (_) => _send(),
                    ),
                  ),
                ),
                if (widget.status == ChatStatus.interrupting)
                  Semantics(
                    label: AppStrings.stopping,
                    liveRegion: true,
                    child: const SizedBox.square(
                      dimension: AppMetrics.inputMinHeight,
                      child: Center(
                        child: SizedBox.square(
                          dimension: AppMetrics.iconSizeLg,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  )
                else if (_isActive && widget.onStop != null)
                  IconButton.filledTonal(
                    tooltip: AppStrings.stopGenerating,
                    style: IconButton.styleFrom(
                      backgroundColor: colors.errorContainer,
                      foregroundColor: colors.onErrorContainer,
                    ),
                    onPressed: _stop,
                    icon: const Icon(Icons.stop_rounded),
                  )
                else
                  IconButton.filled(
                    tooltip: AppStrings.sendMessage,
                    onPressed: canSend ? _send : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
