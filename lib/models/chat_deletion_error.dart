/// Redacted failure of a chat-deletion operation.
final class ChatDeletionError extends StateError {
  ChatDeletionError({this.deletionCommitted = false})
    : super(
        deletionCommitted
            ? 'Chat was deleted, but history could not be refreshed. Please reopen history.'
            : 'Chat deletion could not be completed',
      );

  final bool deletionCommitted;
}

final class ChatDeletionPending extends StateError {
  ChatDeletionPending() : super('This chat is being deleted');
}
