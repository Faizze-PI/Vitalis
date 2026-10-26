import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_strings.dart';
import '../../models/persona.dart';
import '../../providers/chat_provider.dart';
import '../../providers/persona_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../../constants/app_constants.dart';
import '../../widgets/startup_mutation_access.dart';
import '../../widgets/saved_text_preview.dart';

class PersonaSelectionModal extends StatefulWidget {
  const PersonaSelectionModal({super.key});

  @override
  State<PersonaSelectionModal> createState() => _PersonaSelectionModalState();
}

class _PersonaSelectionModalState extends State<PersonaSelectionModal> {
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PersonaProvider>().loadPersonas();
    });
  }

  void _selectPersona(Persona persona) => _savePersona(persona);

  void _removePersona() => _savePersona(null);

  Future<void> _savePersona(Persona? persona) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final chat = context.read<ChatProvider>();
      final saved = await (persona == null
          ? chat.removePersona()
          : chat.setPersona(persona));
      if (!saved) throw StateError('Persona could not be saved. Please retry.');
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) StartupMutationAccess.reportFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showCreateDialog() {
    final navigator = Navigator.of(context);
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: navigator.context,
        builder: (context) => _CreatePersonaDialog(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return StartupMutationAccess(
      builder: (context, canMutate) => Consumer<PersonaProvider>(
        builder: (context, personaProvider, _) {
          final canEdit = canMutate && !_saving;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      AppStrings.selectPersona,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_saving)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Saving persona',
                    ),
                  if (!canMutate)
                    const Text(
                      'Saved personas are read-only while the app is recovering.',
                    ),
                  if (personaProvider.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    Semantics(
                      label: AppStrings.personaNone,
                      button: true,
                      child: ListTile(
                        leading: const Icon(Icons.clear),
                        title: const Text(AppStrings.personaNone),
                        enabled: canEdit,
                        onTap: canEdit ? _removePersona : null,
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ...personaProvider.personas.map(
                            (persona) => Semantics(
                              label:
                                  '${canMutate ? AppStrings.selectPersona : 'View persona'}: ${persona.name}',
                              button: true,
                              child: ListTile(
                                leading: const Icon(Icons.person),
                                title: Text(persona.name),
                                subtitle: Text(
                                  persona.systemPrompt,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Semantics(
                                  label:
                                      '${AppStrings.deletePersona}: ${persona.name}',
                                  button: true,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                    onPressed: !canEdit
                                        ? null
                                        : () async {
                                            final confirmed =
                                                await ConfirmDialog.show(
                                                  context: context,
                                                  title:
                                                      AppStrings.deletePersona,
                                                  message: AppStrings
                                                      .deletePersonaConfirm
                                                      .replaceFirst(
                                                        '{name}',
                                                        persona.name,
                                                      ),
                                                  confirmLabel:
                                                      AppStrings.delete,
                                                );
                                            if (confirmed == true && mounted) {
                                              try {
                                                final deleted = await context
                                                    .read<PersonaProvider>()
                                                    .deletePersona(persona.id!);
                                                if (!deleted) {
                                                  throw StateError(
                                                    'Persona could not be deleted. Please retry.',
                                                  );
                                                }
                                              } catch (error) {
                                                if (mounted)
                                                  StartupMutationAccess.reportFailure(
                                                    context,
                                                    error,
                                                  );
                                              }
                                            }
                                          },
                                  ),
                                ),
                                onTap: _saving
                                    ? null
                                    : canMutate
                                    ? () => _selectPersona(persona)
                                    : () => showSavedTextPreview(
                                        context,
                                        title: persona.name,
                                        content: persona.systemPrompt,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Semantics(
                      label: AppStrings.createNewPersona,
                      button: true,
                      child: ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text(AppStrings.createNewPersona),
                        enabled: canEdit,
                        onTap: canEdit ? _showCreateDialog : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CreatePersonaDialog extends StatefulWidget {
  @override
  State<_CreatePersonaDialog> createState() => _CreatePersonaDialogState();
}

class _CreatePersonaDialogState extends State<_CreatePersonaDialog> {
  final _nameController = TextEditingController();
  final _promptController = TextEditingController();
  String? _validationError;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final prompt = _promptController.text.trim();
    if (name.isEmpty || prompt.isEmpty) {
      setState(() => _validationError = AppStrings.validationNamePrompt);
      return;
    }
    setState(() {
      _validationError = null;
      _saving = true;
    });

    final provider = context.read<PersonaProvider>();
    try {
      final created = await provider.createPersona(name, prompt);
      if (mounted && created != null)
        Navigator.pop(context);
      else if (mounted)
        setState(
          () => _validationError =
              'The persona could not be saved. Please retry.',
        );
    } catch (error) {
      if (mounted) {
        setState(
          () => _validationError =
              'The persona could not be saved while the app is recovering.',
        );
        StartupMutationAccess.reportFailure(context, error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StartupMutationAccess(
      builder: (context, canMutate) => Semantics(
        label: AppStrings.createPersona,
        child: AlertDialog(
          title: const Text(AppStrings.createPersona),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!canMutate)
                  const Text('Read-only while the app is recovering.'),
                Semantics(
                  label: AppStrings.personaName,
                  textField: true,
                  child: TextField(
                    controller: _nameController,
                    readOnly: !canMutate || _saving,
                    decoration: const InputDecoration(
                      labelText: AppStrings.personaName,
                    ),
                    maxLength: AppConstants.maxPersonaNameLength,
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => Text('$currentLength/$maxLength'),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: AppStrings.systemPrompt,
                  textField: true,
                  child: TextField(
                    controller: _promptController,
                    readOnly: !canMutate || _saving,
                    decoration: const InputDecoration(
                      labelText: AppStrings.systemPrompt,
                      helperText: 'Storage safety limit: 1 MiB',
                    ),
                    maxLines: 3,
                  ),
                ),
                if (_validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _validationError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
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
                onPressed: canMutate && !_saving ? _create : null,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text(AppStrings.create),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
