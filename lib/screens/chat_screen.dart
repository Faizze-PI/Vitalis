import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../models/note.dart';
import '../providers/chat_provider.dart';
import '../providers/generation_provider.dart';
import '../providers/health_provider.dart';
import '../widgets/chat_input_field.dart';
import '../widgets/conversation_status_bar.dart';
import '../widgets/attached_notes_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/response_frame_observer.dart';
import '../widgets/animated_dots.dart';
import '../constants/app_colors.dart';
import '../constants/app_metrics.dart';
import '../constants/app_strings.dart';
import '../constants/app_constants.dart';
import '../app_router.dart';
import '../services/chat_state_controller.dart';
import '../services/model_warmup_service.dart';
import '../services/model_registry_service.dart';
import '../services/selected_model_readiness.dart';
import '../services/startup_access_guard.dart';
import '../models/model_descriptor.dart';
import '../utils/app_logger.dart';
import 'modals/chat_history_modal.dart';
import 'modals/chat_name_modal.dart';
import 'modals/hamburger_menu.dart';
import 'modals/persona_selection_modal.dart';
import 'modals/notes_list_selection_modal.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _disposed = false;
  ChatProvider? _chatProvider;
  GenerationProvider? _generationProvider;
  String? _modelLabelId;
  Future<ModelDescriptor?>? _modelLabelLookup;

  Widget _modelLabel(String modelId) {
    if (_modelLabelId != modelId) {
      _modelLabelId = modelId;
      _modelLabelLookup = context.read<ModelRegistryService>().findById(
        modelId,
      );
    }
    return FutureBuilder<ModelDescriptor?>(
      key: ValueKey(modelId),
      future: _modelLabelLookup,
      builder: (context, snapshot) {
        final name = snapshot.connectionState != ConnectionState.done
            ? 'Checking model…'
            : snapshot.data?.displayName ?? 'Model unavailable';
        return Tooltip(
          message: name,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppMetrics.spaceXxs),
              const Icon(
                Icons.expand_more_rounded,
                size: AppMetrics.iconSizeSm,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _observeResponseFrame(
    Widget child,
    GenerationProvider generation,
    Object? identity,
  ) {
    if (identity == null ||
        !identical(identity, generation.responseFrameIdentity) ||
        generation.lastResponseFrameTiming?.firstReceivedTextMicros == null) {
      return child;
    }
    return ResponseFrameObserver(
      responseIdentity: identity,
      onFrame: generation.recordResponseFrame,
      child: child,
    );
  }

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    _generationProvider = context.read<GenerationProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = _chatProvider;
      if (provider == null) return;
      await provider.loadChats();
      if (provider.currentChat == null && provider.chats.isNotEmpty) {
        await provider.selectChat(provider.chats.first.id!);
      }
      if (provider.currentChat == null && mounted) {
        await context.read<SelectedModelReadiness>().select(
          provider.settings.modelId,
        );
      }
      final access = context.read<StartupAccessGuard?>();
      if (provider.currentChat == null &&
          mounted &&
          (access?.snapshot().canMutateContent ?? true)) {
        await provider.createChat();
      }
      // Lazy warmup: only once per app lifecycle
      if (mounted && (access?.snapshot().canInfer ?? true)) {
        final warmup = context.read<ModelWarmupService>();
        if (!warmup.isWarmedUp && !warmup.isWarmingUp) {
          warmup.warmup(modelId: provider.settings.modelId);
        }
      }
    });
    _chatProvider!.addListener(_onProviderChange);
    _generationProvider!.addListener(_onProviderChange);
  }

  @override
  void dispose() {
    _disposed = true;
    _chatProvider?.removeListener(_onProviderChange);
    _generationProvider?.removeListener(_onProviderChange);
    _chatProvider = null;
    _generationProvider = null;
    _scrollController.dispose();
    super.dispose();
  }

  void _onProviderChange() {
    if (_disposed || !mounted) return;
    final gen = context.read<GenerationProvider>();
    if (gen.isSending) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _chooseModel(ChatProvider chatProvider) async {
    final registry = context.read<ModelRegistryService>();
    final installed = (await registry.listModels())
        .where((model) => model.isInstalled)
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Model for this chat')),
            for (final ModelDescriptor model in installed)
              ListTile(
                leading: model.id == chatProvider.settings.modelId
                    ? const Icon(Icons.check_circle)
                    : const Icon(Icons.memory),
                title: Text(model.displayName),
                subtitle: Text(model.quantization ?? model.source),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    await chatProvider.switchModel(model.id);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${model.displayName} is ready'),
                        ),
                      );
                    }
                  } catch (error) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Model could not be switched. Please retry.',
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Find more models'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.pushNamed(context, AppRoutes.modelLibrary);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Future<void> _showMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => const HamburgerMenu(),
    );

    if (!mounted || action == null) return;
    await _runMenuAction(action);
  }

  Future<void> _showContextActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text(AppStrings.attachNote),
              onTap: () => Navigator.pop(sheet, 'attach_note'),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text(AppStrings.selectPersona),
              onTap: () => Navigator.pop(sheet, 'select_persona'),
            ),
          ],
        ),
      ),
    );
    if (mounted && action != null) await _runMenuAction(action);
  }

  Future<void> _runMenuAction(String action) async {
    if (!mounted) return;
    final chatProvider = context.read<ChatProvider>();

    try {
      switch (action) {
        case 'remove_persona':
          if (!await chatProvider.removePersona())
            throw StateError('Persona change was not saved');
        case 'rename':
          await _renameChat(chatProvider);
        case 'model_library':
          await Navigator.pushNamed(context, AppRoutes.modelLibrary);
        case 'chat_history':
          await chatProvider.loadChats();
          if (!mounted) return;
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => const ChatHistoryModal(),
          );
        case 'select_persona':
          await showModalBottomSheet(
            context: context,
            builder: (ctx) => const PersonaSelectionModal(),
          );
        case 'attach_note':
          final note = await showModalBottomSheet<Note>(
            context: context,
            builder: (ctx) => const NotesListSelectionModal(),
          );
          if (note != null && mounted) {
            await chatProvider.attachNote(note);
          }
        case 'settings':
          await Navigator.pushNamed(context, AppRoutes.chatSettings);
        case 'export':
          await _exportConversation(chatProvider);
        case 'debug':
          if (await canNavigateToDebug(context)) {
            await Navigator.pushNamed(context, AppRoutes.debug);
          }
      }
    } catch (error) {
      AppLogger.instance.warning(
        'Conversation action failed (${error.runtimeType})',
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That action is unavailable right now. Please retry.',
            ),
          ),
        );
    }
  }

  Future<void> _renameChat(ChatProvider chatProvider) async {
    final controller = TextEditingController(
      text: chatProvider.currentChat?.title ?? '',
    );
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.renameChat),
        content: Semantics(
          label: AppStrings.chatName,
          textField: true,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: AppStrings.chatName),
            inputFormatters: [
              LengthLimitingTextInputFormatter(AppConstants.maxChatTitleLength),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancel),
          ),
          Semantics(
            label: AppStrings.rename,
            button: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text(AppStrings.rename),
            ),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.isNotEmpty && mounted) {
      final chatId = chatProvider.currentChat?.id;
      if (chatId != null) {
        await chatProvider.updateChatTitle(chatId, newTitle);
      }
    }
  }

  Future<void> _exportConversation(ChatProvider chatProvider) async {
    try {
      final text = await chatProvider.exportConversation();
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.conversationCopied)),
      );
    } catch (error) {
      AppLogger.instance.warning(
        'Conversation export failed (${error.runtimeType})',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conversation could not be copied. Please retry.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Consumer<ChatProvider>(
        builder: (context, chatProvider, _) {
          // Listening to selected readiness rebuilds this screen after a chat
          // change or successful model recovery.
          context.watch<SelectedModelReadiness>();
          final access = context.watch<StartupAccessGuard?>();
          final canInfer = access?.snapshot().canInfer ?? true;
          final generationProvider = context.watch<GenerationProvider>();
          final status = generationProvider.chatStatus;
          final streamText = chatProvider.generatingContent ?? '';
          final isSending = generationProvider.isSending;

          final showThinking =
              isSending &&
              streamText.isEmpty &&
              chatProvider.messages.isNotEmpty;

          final showTps =
              !isSending &&
              generationProvider.lastTps > 0 &&
              chatProvider.messages.isNotEmpty;

          final isGenerating = status == ChatStatus.generating;
          final healthProvider = context.watch<HealthProvider>();

          return Scaffold(
            appBar: AppBar(
              toolbarHeight: AppMetrics.spaceXxl + AppMetrics.spaceLg,
              leading: IconButton(
                tooltip: Navigator.canPop(context)
                    ? 'Back to Chats'
                    : AppStrings.chatHistory,
                icon: Icon(
                  Navigator.canPop(context)
                      ? Icons.arrow_back
                      : Icons.menu_rounded,
                ),
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.maybePop(context);
                  } else {
                    _runMenuAction('chat_history');
                  }
                },
              ),
              titleSpacing: 0,
              title: Semantics(
                label: 'Change model for this chat',
                button: true,
                enabled: canInfer,
                child: InkWell(
                  onTap: canInfer ? () => _chooseModel(chatProvider) : null,
                  borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppMetrics.spaceXs,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chatProvider.currentChat?.title ?? 'Chat',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppMetrics.spaceXxs),
                        _modelLabel(chatProvider.settings.modelId),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  tooltip: AppStrings.newChat,
                  icon: const Icon(Icons.add_rounded),
                  onPressed: canInfer
                      ? () async {
                          final title = await showDialog<String>(
                            context: context,
                            builder: (_) => const ChatNameModal(),
                          );
                          if (title != null && mounted)
                            await context.read<ChatProvider>().createChat(
                              title: title,
                            );
                        }
                      : null,
                ),
                IconButton(
                  tooltip: AppStrings.openMenu,
                  icon: const Icon(Icons.more_horiz_rounded),
                  onPressed: _showMenu,
                ),
              ],
            ),
            body: PopScope(
              canPop: !isGenerating,
              onPopInvokedWithResult: (didPop, _) {
                if (isGenerating && mounted) {
                  // Inform user generation is active — block back.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Generation in progress. Stop it first.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Column(
                children: [
                  ConversationStatusBar(
                    safe: healthProvider.isSafeForHeavy,
                    rssMb: healthProvider.rssMb,
                    battery: healthProvider.batteryKnown
                        ? healthProvider.batteryLevel
                        : null,
                    lastTps: generationProvider.lastTps,
                  ),

                  // Error banner
                  if (chatProvider.hasError &&
                      chatProvider.errorMessage.isNotEmpty)
                    MaterialBanner(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppMetrics.spaceMd,
                        vertical: AppMetrics.spaceXs,
                      ),
                      content: Semantics(
                        label: 'Error: ${chatProvider.errorMessage}',
                        liveRegion: true,
                        child: Text(chatProvider.errorMessage),
                      ),
                      leading: const Icon(
                        Icons.error_outline,
                        color: AppColors.healthRed,
                      ),
                      actions: [
                        Semantics(
                          label: AppStrings.dismiss,
                          button: true,
                          child: TextButton(
                            onPressed: () => chatProvider.clearError(),
                            child: const Text(AppStrings.dismiss),
                          ),
                        ),
                      ],
                    ),

                  // Truncation warning
                  if (generationProvider.showTruncationWarning)
                    Semantics(
                      liveRegion: true,
                      child: MaterialBanner(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppMetrics.spaceMd,
                          vertical: AppMetrics.spaceXs,
                        ),
                        content: const Text(AppStrings.truncationWarningBody),
                        leading: const Icon(
                          Icons.info_outline,
                          color: AppColors.healthOrange,
                        ),
                        actions: [
                          Semantics(
                            label: AppStrings.dismiss,
                            button: true,
                            child: TextButton(
                              onPressed: () =>
                                  generationProvider.dismissTruncationWarning(),
                              child: const Text(AppStrings.dismiss),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Context usage bar
                  if (chatProvider.messages.isNotEmpty &&
                      chatProvider.contextUsage > 0.1)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppMetrics.spaceMd,
                        vertical: AppMetrics.spaceXxs,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppMetrics.contextBarRadius,
                              ),
                              child: Semantics(
                                label:
                                    'Context window ${(chatProvider.contextUsage * 100).toInt()}% used',
                                child: LinearProgressIndicator(
                                  value: chatProvider.contextUsage,
                                  minHeight: AppMetrics.contextBarHeight,
                                  backgroundColor: AppColors.contextBarBg(
                                    context,
                                  ),
                                  color: chatProvider.contextUsage > 0.8
                                      ? AppColors.healthRed
                                      : chatProvider.contextUsage > 0.6
                                      ? AppColors.healthOrange
                                      : AppColors.healthGreen,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppMetrics.spaceXs),
                          Text(
                            '${(chatProvider.contextUsage * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: chatProvider.contextUsage > 0.8
                                  ? AppColors.healthRed
                                  : chatProvider.contextUsage > 0.6
                                  ? AppColors.healthOrange
                                  : AppColors.healthGreen,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Messages
                  Expanded(
                    child: GestureDetector(
                      onTap: _dismissKeyboard,
                      child: chatProvider.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : chatProvider.messages.isEmpty
                          ? Semantics(
                              label: AppStrings.noMessages,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: AppMetrics.spaceXl,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: AppMetrics.spaceMd),
                                    Text(
                                      canInfer
                                          ? 'Start a conversation'
                                          : 'Your conversation is saved',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: AppMetrics.spaceXs),
                                    Text(
                                      canInfer
                                          ? 'Ask a question, or add a note for context.'
                                          : 'Choose or recover a model to continue.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(AppMetrics.spaceMd),
                              itemCount:
                                  chatProvider.messages.length +
                                  (isSending && streamText.isNotEmpty ? 1 : 0) +
                                  (showThinking ? 1 : 0) +
                                  (showTps ? 1 : 0) +
                                  (chatProvider.hasOlderMessages ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (chatProvider.hasOlderMessages &&
                                    index == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppMetrics.spaceSm,
                                    ),
                                    child: Center(
                                      child: TextButton(
                                        onPressed: () =>
                                            chatProvider.loadOlderMessages(),
                                        child: const Text(
                                          'Load earlier messages',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final adjustedIndex =
                                    chatProvider.hasOlderMessages
                                    ? index - 1
                                    : index;
                                final streamingIndex =
                                    chatProvider.messages.length;
                                if (showThinking &&
                                    adjustedIndex == streamingIndex) {
                                  return Semantics(
                                    label: AppStrings.assistantResponse,
                                    liveRegion: true,
                                    child: const Padding(
                                      padding: EdgeInsets.only(
                                        bottom: AppMetrics.spaceSm,
                                      ),
                                      child: Row(
                                        children: [
                                          Text('Preparing response'),
                                          SizedBox(width: AppMetrics.spaceXs),
                                          AnimatedDots(),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                if (isSending &&
                                    streamText.isNotEmpty &&
                                    adjustedIndex == streamingIndex) {
                                  return _observeResponseFrame(
                                    MessageBubble(
                                      message: Message(
                                        chatId:
                                            chatProvider.currentChat?.id ?? 0,
                                        role: MessageRole.assistant,
                                        content: streamText,
                                      ),
                                    ),
                                    generationProvider,
                                    generationProvider.responseFrameIdentity,
                                  );
                                }
                                final tpsOffset =
                                    streamingIndex +
                                    (isSending && streamText.isNotEmpty
                                        ? 1
                                        : 0) +
                                    (showThinking ? 1 : 0);
                                if (showTps && adjustedIndex == tpsOffset) {
                                  final tpsText =
                                      '${generationProvider.lastTokenCount} tokens · ${generationProvider.lastTps.toStringAsFixed(1)} tok/s';
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppMetrics.spaceXxs,
                                    ),
                                    child: Center(
                                      child: Semantics(
                                        label: tpsText,
                                        child: Text(
                                          tpsText,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Colors.grey.shade500
                                                : Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final message =
                                    chatProvider.messages[adjustedIndex];
                                return _observeResponseFrame(
                                  MessageBubble(
                                    message: message,
                                    onRetry: message.isError
                                        ? () => chatProvider.retryLastMessage()
                                        : null,
                                  ),
                                  generationProvider,
                                  chatProvider.responseFrameIdentityFor(
                                    message,
                                  ),
                                );
                              },
                            ),
                    ),
                  ),

                  if (chatProvider.attachedNotes.isNotEmpty ||
                      chatProvider.currentPersona != null)
                    AttachedNotesBar(
                      notes: chatProvider.attachedNotes,
                      persona: chatProvider.currentPersona,
                      enabled: canInfer && !isSending,
                      onRemovePersona: () => _runMenuAction('remove_persona'),
                      onRemove: (note) async {
                        try {
                          await chatProvider.clearAttachedNote(note);
                        } catch (error) {
                          AppLogger.instance.warning(
                            'Note detach failed (${error.runtimeType})',
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'The note could not be detached. Please retry.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  if (!canInfer)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Saved chats are available to read. Inference will be available after model and safety checks pass.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              AppRoutes.modelLibrary,
                            ),
                            icon: const Icon(Icons.memory),
                            label: const Text('Open Model Library'),
                          ),
                        ],
                      ),
                    )
                  else
                    ChatInputField(
                      key: ValueKey(chatProvider.currentChat?.id),
                      onAttach: _showContextActions,
                      onSend: (text) async {
                        final saved = await chatProvider.submitMessage(text);
                        if (!saved) throw StateError('Message was not saved');
                        _scrollToBottom();
                      },
                      onStop: chatProvider.stopSending,
                      status: generationProvider.chatStatus,
                    ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      AppLogger.instance.errorFailure('ChatScreen build error', e);
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
