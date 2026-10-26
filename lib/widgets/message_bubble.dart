import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../models/message.dart';
import '../constants/app_metrics.dart';
import '../constants/app_strings.dart';
import '../utils/date_formatter.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.onRetry});
  final Message message;
  final VoidCallback? onRetry;

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: message.content));
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStrings.messageCopied)));
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message could not be copied. Please retry.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = message.isError
        ? colors.onErrorContainer
        : colors.onSurface;
    final style = theme.textTheme.bodyLarge?.copyWith(color: foreground);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppMetrics.spaceLg),
      child: Align(
        alignment: isUser
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: isUser ? 0.88 : 1,
          child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Semantics(
                label: isUser
                    ? '${AppStrings.userMessage}: ${message.content}'
                    : '${AppStrings.assistantResponse}: ${message.content}',
                hint: DateFormatter.formatRelative(message.timestamp),
                excludeSemantics: true,
                customSemanticsActions: {
                  const CustomSemanticsAction(label: 'Copy message'): () =>
                      _copy(context),
                },
                child: GestureDetector(
                  onLongPress: () => _copy(context),
                  child: Container(
                    padding: isUser || message.isError
                        ? const EdgeInsets.symmetric(
                            horizontal: AppMetrics.spaceMd,
                            vertical: AppMetrics.spaceSm,
                          )
                        : const EdgeInsets.symmetric(
                            vertical: AppMetrics.spaceXxs,
                          ),
                    decoration: BoxDecoration(
                      color: message.isError
                          ? colors.errorContainer
                          : isUser
                          ? colors.surfaceContainerHighest
                          : null,
                      borderRadius: BorderRadius.circular(
                        AppMetrics.bubbleRadius,
                      ),
                    ),
                    child: isUser
                        ? Text(message.content, style: style)
                        : MarkdownBody(
                            data: message.content,
                            styleSheet: MarkdownStyleSheet.fromTheme(theme)
                                .copyWith(
                                  p: style,
                                  code: theme.textTheme.bodyMedium?.copyWith(
                                    fontFamily: 'monospace',
                                    color: foreground,
                                    backgroundColor:
                                        colors.surfaceContainerHighest,
                                  ),
                                  codeblockDecoration: BoxDecoration(
                                    color: colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(
                                      AppMetrics.radiusSm,
                                    ),
                                  ),
                                ),
                          ),
                  ),
                ),
              ),
              if (!isUser || message.isError)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copy message',
                      onPressed: () => _copy(context),
                      icon: const Icon(
                        Icons.copy_outlined,
                        size: AppMetrics.iconSizeMd,
                      ),
                    ),
                    if (message.isError && onRetry != null)
                      TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(
                          Icons.refresh,
                          size: AppMetrics.iconSizeMd,
                        ),
                        label: const Text(AppStrings.retry),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
