/// Verified selected file content, separate from notes and model instructions.
final class FileContext {
  const FileContext({required this.name, required this.text});
  final String name, text;
}
