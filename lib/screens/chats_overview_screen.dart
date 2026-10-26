import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_router.dart';
import '../models/chat.dart';
import '../providers/chat_provider.dart';
import '../utils/date_formatter.dart';
import '../widgets/startup_mutation_access.dart';
import 'modals/chat_name_modal.dart';
import 'modals/chat_history_modal.dart';

class ChatsOverviewScreen extends StatefulWidget {
  const ChatsOverviewScreen({super.key, this.active = true});
  final bool active;
  @override
  State<ChatsOverviewScreen> createState() => _ChatsOverviewScreenState();
}

class _ChatsOverviewScreenState extends State<ChatsOverviewScreen> {
  final _search = TextEditingController();
  bool _pending = false;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant ChatsOverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _load();
      });
    }
  }

  Future<void> _load() async {
    if (!mounted || _pending) return;
    setState(() {
      _pending = true;
      _loading = true;
      _loadFailed = false;
    });
    try {
      final provider = context.read<ChatProvider>();
      await provider.loadChats();
      if (mounted) setState(() => _loadFailed = provider.hasHistoryError);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted)
        setState(() {
          _pending = false;
          _loading = false;
        });
    }
  }

  Future<void> _open(Chat chat) async {
    if (_pending || chat.id == null) return;
    setState(() => _pending = true);
    try {
      final provider = context.read<ChatProvider>();
      final needsSelection = provider.currentChat?.id != chat.id;
      if (needsSelection) await provider.selectChat(chat.id!);
      if (!mounted) return;
      if ((needsSelection && provider.hasError) ||
          provider.currentChat?.id != chat.id) {
        throw StateError('Chat selection was not established');
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await Navigator.pushNamed(context, AppRoutes.chat);
      if (mounted) await provider.loadChats();
    } catch (_) {
      if (mounted) _reportOpenFailure();
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  void _reportOpenFailure() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Could not open the conversation. Please retry.'),
    ),
  );

  Future<void> _create() async {
    if (_pending) return;
    setState(() => _pending = true);
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (_) => const ChatNameModal(),
      );
      if (!mounted || title == null) return;
      final provider = context.read<ChatProvider>();
      final chat = await provider.createChat(
        title: title.isEmpty ? null : title,
      );
      if (!mounted) return;
      if (chat == null || chat.id != provider.currentChat?.id) {
        throw StateError('Chat creation was not established');
      }
      await Navigator.pushNamed(context, AppRoutes.chat);
      if (mounted) await provider.loadChats();
    } catch (error) {
      if (mounted) StartupMutationAccess.reportFailure(context, error);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StartupMutationAccess(
    builder: (context, canMutate) {
      final provider = context.watch<ChatProvider>();
      final query = _search.text.trim().toLowerCase();
      final chats =
          provider.chats
              .where((chat) => chat.title.toLowerCase().contains(query))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return Scaffold(
        appBar: AppBar(
          title: const Text('Chats'),
          actions: [
            IconButton(
              tooltip: 'Manage chat history',
              icon: const Icon(Icons.more_horiz),
              onPressed: _pending
                  ? null
                  : () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => const ChatHistoryModal(),
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: canMutate && !_pending ? _create : null,
          tooltip: canMutate
              ? 'New Chat'
              : 'Model recovery is required before creating a chat',
          icon: const Icon(Icons.add),
          label: const Text('New Chat'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search conversations',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (_loading)
              const LinearProgressIndicator(
                semanticsLabel: 'Loading conversations',
              ),
            if (_loadFailed)
              MaterialBanner(
                content: const Text('Could not load conversations.'),
                actions: [
                  TextButton(
                    onPressed: _pending ? null : _load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(
              child: chats.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _loadFailed
                              ? 'Your saved data has not been reset.'
                              : _loading
                              ? 'Loading conversations…'
                              : query.isNotEmpty
                              ? 'No matching conversations'
                              : 'Start a conversation. It stays on your device.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        return ListTile(
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(
                            chat.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            DateFormatter.formatChatDate(chat.updatedAt),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _pending ? null : () => _open(chat),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
