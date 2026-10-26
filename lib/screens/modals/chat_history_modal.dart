import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_strings.dart';
import '../../providers/chat_provider.dart';
import '../../utils/date_formatter.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/startup_mutation_access.dart';

class ChatHistoryModal extends StatefulWidget {
  const ChatHistoryModal({super.key});

  @override
  State<ChatHistoryModal> createState() => _ChatHistoryModalState();
}

class _ChatHistoryModalState extends State<ChatHistoryModal> {
  final _pendingDeletions = <int>{};

  Future<void> _confirmDeletion(ChatProvider provider, int id) async {
    if (!mounted || !_pendingDeletions.add(id)) return;
    setState(() {});
    try {
      final confirmed = await ConfirmDialog.show(
        context: context,
        title: AppStrings.deleteChat,
        message: AppStrings.deleteChatConfirm,
      );
      if (!mounted || !confirmed) return;
      await provider.deleteChat(id);
    } catch (error) {
      if (mounted) StartupMutationAccess.reportFailure(context, error);
    } finally {
      if (mounted) setState(() => _pendingDeletions.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    return StartupMutationAccess(
      builder: (context, canMutate) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      AppStrings.chatHistory,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Semantics(
                    label: AppStrings.done,
                    button: true,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(AppStrings.done),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (chatProvider.chats.isEmpty)
                Semantics(
                  label: AppStrings.previousChats,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text(AppStrings.previousChats)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: chatProvider.chats.length,
                    itemBuilder: (context, index) {
                      final chat = chatProvider.chats[index];
                      final isActive = chat.id == chatProvider.currentChat?.id;
                      return Semantics(
                        label: '${AppStrings.chatHistory}: ${chat.title}',
                        button: true,
                        selected: isActive,
                        child: ListTile(
                          leading: const Icon(Icons.chat),
                          title: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            DateFormatter.formatChatDate(chat.updatedAt),
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isActive)
                                Semantics(
                                  label: 'Active',
                                  child: const Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: Colors.green,
                                  ),
                                ),
                              Semantics(
                                label:
                                    '${AppStrings.deleteChat}: ${chat.title}',
                                button: true,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                  onPressed:
                                      !canMutate ||
                                          _pendingDeletions.contains(chat.id)
                                      ? null
                                      : () => _confirmDeletion(
                                          chatProvider,
                                          chat.id!,
                                        ),
                                ),
                              ),
                            ],
                          ),
                          selected: isActive,
                          onTap: isActive
                              ? null
                              : () async {
                                  final id = chat.id!;
                                  await chatProvider.selectChat(id);
                                  if (context.mounted) Navigator.pop(context);
                                },
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
