import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_metrics.dart';
import '../constants/app_strings.dart';
import '../services/chat_state_controller.dart';

class ChatInputField extends StatefulWidget {
  final Future<void> Function(String) onSend;
  final Future<void> Function()? onStop;
  final ChatStatus status;

  const ChatInputField({
    super.key,
    required this.onSend,
    this.onStop,
    this.status = ChatStatus.idle,
  });

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  final _controller = TextEditingController();

  bool get _isActive =>
      widget.status == ChatStatus.generating ||
      widget.status == ChatStatus.interrupting;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      _controller.clear();
      unawaited(widget.onSend(text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppMetrics.spaceXs),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: AppStrings.messageInput,
                textField: true,
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: widget.status == ChatStatus.interrupting
                        ? AppStrings.stopping
                        : AppStrings.typeMessage,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppMetrics.spaceMd,
                      vertical: AppMetrics.spaceSm,
                    ),
                    counterText: '',
                  ),
                  maxLines: 4,
                  minLines: 1,
                  enabled: !_isActive,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _isActive ? null : (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: AppMetrics.spaceXs),
            if (widget.status == ChatStatus.interrupting)
              Semantics(
                label: AppStrings.stopping,
                liveRegion: true,
                child: const SizedBox(
                  width: AppMetrics.iconButtonSize,
                  height: AppMetrics.iconButtonSize,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_isActive && widget.onStop != null)
              Semantics(
                label: AppStrings.stopGenerating,
                button: true,
                child: IconButton(
                  icon: const Icon(
                    Icons.stop_circle_outlined,
                    color: AppColors.healthRed,
                    size: 28,
                  ),
                  onPressed: () => unawaited(widget.onStop!()),
                  tooltip: AppStrings.stopGenerating,
                ),
              )
            else
              Semantics(
                label: AppStrings.sendMessage,
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isActive ? null : _send,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
