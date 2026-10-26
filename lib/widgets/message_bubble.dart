import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../models/message.dart';
import '../constants/app_colors.dart';
import '../constants/app_metrics.dart';
import '../constants/app_strings.dart';
import '../utils/date_formatter.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onRetry;

  const MessageBubble({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppMetrics.spaceSm),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Semantics(
              label: AppStrings.assistantResponse,
              image: true,
              child: CircleAvatar(
                radius: AppMetrics.avatarRadius,
                backgroundColor: message.isError
                    ? AppColors.healthRed.withValues(alpha: 0.2)
                    : null,
                child: Icon(
                  message.isError ? Icons.error_outline : Icons.smart_toy,
                  size: AppMetrics.iconSizeMd,
                  color: message.isError ? AppColors.healthRed : null,
                ),
              ),
            ),
          if (!isUser) const SizedBox(width: AppMetrics.spaceXs),
          Flexible(
            child: Semantics(
              label: isUser
                  ? '${AppStrings.userMessage}: ${message.content}'
                  : '${AppStrings.assistantResponse}: ${message.content}',
              // The label already includes the complete message. Excluding
              // descendants prevents TalkBack/UIAutomator from announcing the
              // same reply once for the label and again for Markdown content.
              excludeSemantics: true,
              child: GestureDetector(
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(AppStrings.messageCopied),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppMetrics.spaceSm),
                      decoration: BoxDecoration(
                        color: message.isError
                            ? AppColors.errorLight
                            : isUser
                            ? AppColors.userBubble
                            : theme.brightness == Brightness.dark
                            ? AppColors.assistantBubbleDark
                            : AppColors.assistantBubbleLight,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(
                            AppMetrics.bubbleRadius,
                          ),
                          topRight: const Radius.circular(
                            AppMetrics.bubbleRadius,
                          ),
                          bottomLeft: Radius.circular(
                            isUser
                                ? AppMetrics.bubbleRadius
                                : AppMetrics.bubbleTightRadius,
                          ),
                          bottomRight: Radius.circular(
                            isUser
                                ? AppMetrics.bubbleTightRadius
                                : AppMetrics.bubbleRadius,
                          ),
                        ),
                      ),
                      child: isUser
                          ? Text(
                              message.content,
                              style: const TextStyle(color: AppColors.userText),
                            )
                          : MarkdownBody(
                              data: message.content,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  color: theme.brightness == Brightness.dark
                                      ? AppColors.assistantTextDark
                                      : AppColors.assistantTextLight,
                                ),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppMetrics.spaceXxs,
                        left: AppMetrics.spaceXxs,
                        right: AppMetrics.spaceXxs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label: DateFormatter.formatRelative(
                              message.timestamp,
                            ),
                            child: Text(
                              DateFormatter.formatRelative(message.timestamp),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                          if (message.isError && onRetry != null) ...[
                            const SizedBox(width: AppMetrics.spaceXs),
                            Semantics(
                              label: AppStrings.retry,
                              button: true,
                              child: GestureDetector(
                                onTap: onRetry,
                                child: Text(
                                  AppStrings.retry,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: AppMetrics.spaceXs),
            Semantics(
              label: AppStrings.userMessage,
              image: true,
              child: const CircleAvatar(
                radius: AppMetrics.avatarRadius,
                child: Icon(Icons.person, size: AppMetrics.iconSizeMd),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
