import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';
import '../../constants/app_strings.dart';

class ChatNameModal extends StatefulWidget {
  const ChatNameModal({super.key});

  @override
  State<ChatNameModal> createState() => _ChatNameModalState();
}

class _ChatNameModalState extends State<ChatNameModal> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppStrings.newChat,
      child: AlertDialog(
        title: const Text(AppStrings.newChat),
        content: Semantics(
          label: AppStrings.chatName,
          textField: true,
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: AppStrings.chatName),
            maxLength: AppConstants.maxChatTitleLength,
            buildCounter:
                (_, {required currentLength, required isFocused, maxLength}) =>
                    Text('$currentLength/$maxLength'),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
        ),
        actions: [
          Semantics(
            label: AppStrings.cancel,
            button: true,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(AppStrings.cancel),
            ),
          ),
          Semantics(
            label: AppStrings.create,
            button: true,
            child: TextButton(
              onPressed: () => Navigator.pop(context, _controller.text.trim()),
              child: const Text(AppStrings.create),
            ),
          ),
        ],
      ),
    );
  }
}
