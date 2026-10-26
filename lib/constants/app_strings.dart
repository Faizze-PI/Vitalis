/// All Vitalis user-facing strings in one place.
/// Phase 8: Localization seed. Future: replace with ARB + AppLocalizations.
class AppStrings {
  AppStrings._();

  // General
  static const String appName = 'Vitalis';
  static const String cancel = 'Cancel';
  static const String confirm = 'Confirm';
  static const String done = 'Done';
  static const String save = 'Save';
  static const String delete = 'Delete';
  static const String dismiss = 'Dismiss';
  static const String retry = 'Retry';
  static const String rename = 'Rename';
  static const String create = 'Create';
  static const String close = 'Close';
  static const String copy = 'Copy';

  // Setup / Onboarding
  static const String setupTitle = 'Setup';
  static const String welcomeTitle = 'Welcome to Vitalis';
  static const String welcomeSubtitle = 'Download the AI model to get started';
  static const String modelReady = 'Model Ready!';
  static const String startChatting = 'Start Chatting';
  static const String downloadModel = 'Download AI Model';
  static const String downloadingModel = 'Downloading model...';
  static const String cancelDownload = 'Cancel';

  // Chat Screen
  static const String newChat = 'New Chat';
  static const String renameChat = 'Rename Chat';
  static const String chatName = 'Chat name';
  static const String noMessages = 'No messages yet';
  static const String conversationCopied = 'Conversation copied to clipboard';
  static const String messageCopied = 'Copied to clipboard';
  static const String tokensPerSec = '{count} tokens · {tps} tok/s';
  static const String notePrefix = 'Note: ';
  static const String stopGenerating = 'Stop generating';
  static const String sendMessage = 'Send message';
  static const String messageInput = 'Message input';
  static const String stopping = 'Stopping...';
  static const String typeMessage = 'Type a message...';
  static const String openMenu = 'Open menu';
  static const String attachedNote = 'Attached note:';

  // Chat Input
  static const String userMessage = 'User message';
  static const String assistantResponse = 'Assistant response';

  // Hamburger Menu
  static const String chatOptions = 'Chat Options';
  static const String chatHistory = 'Chat History';
  static const String selectPersona = 'Select Persona';
  static const String attachNote = 'Attach Note';
  static const String exportConversation = 'Export Conversation';
  static const String debugMenu = 'Debug';

  // Chat History
  static const String previousChats = 'No previous chats';
  static const String justNow = 'just now';
  static const String minutesAgo = '{count}m ago';
  static const String hoursAgo = '{count}h ago';
  static const String daysAgo = '{count}d ago';

  // Delete Chat
  static const String deleteChat = 'Delete Chat';
  static const String deleteChatConfirm =
      'Are you sure you want to delete this chat?';

  // Persona
  static const String personaNone = 'None';
  static const String createNewPersona = 'Create New Persona';
  static const String createPersona = 'Create Persona';
  static const String deletePersona = 'Delete Persona';
  static const String deletePersonaConfirm = 'Delete "{name}"?';
  static const String personaName = 'Name';
  static const String systemPrompt = 'System Prompt';
  static const String validationNamePrompt = 'Name and prompt are required';

  // Notes
  static const String selectNote = 'Select Note';
  static const String noNotes = 'No notes available';
  static const String createNewNote = 'Create New Note';
  static const String newNote = 'New Note';
  static const String editNote = 'Edit Note';
  static const String deleteNote = 'Delete Note';
  static const String deleteNoteConfirm = 'Delete "{title}"?';
  static const String noteTitle = 'Title';
  static const String noteContent = 'Content';
  static const String validationTitleContent = 'Title and content are required';

  // Settings
  static const String settingsTitle = 'Settings';
  static const String appearance = 'Appearance';
  static const String darkMode = 'Dark Mode';
  static const String toggleDark = 'Toggle dark theme';
  static const String privacy = 'Privacy';
  static const String privacyMode = 'Privacy Mode';
  static const String privacyModeDesc = 'PII masking active on all logs';
  static const String privacyModeOff = 'PII masking disabled (dev only)';
  static const String whatIsLogged = 'What is logged?';
  static const String loggedFields =
      'Timestamps, severity levels, sanitized messages. Emails, phone numbers, and IP addresses are automatically removed.';
  static const String clearLogs = 'Clear Logs';
  static const String clearLogsConfirm = 'Delete all log files?';
  static const String privacyPolicy = 'Privacy Policy';
  static const String modelInfo = 'Model Info';
  static const String modelName = 'Model';
  static const String quantization = 'Quantization';
  static const String parameters = 'Parameters';
  static const String contextWindow = 'Context Window';
  static const String fileSize = 'File Size';
  static const String notDownloaded = 'Not downloaded';
  static const String notFound = 'Not found';
  static const String unknown = 'Unknown';
  static const String modelSettings = 'Model Settings';
  static const String temperatureLabel = 'Temperature';
  static const String topPLabel = 'Top P';
  static const String topKLabel = 'Top K';
  static const String maxTokensLabel = 'Max Tokens';
  static const String resetModel = 'Reset Model';
  static const String resetModelConfirm =
      'This will delete the downloaded model. You will need to download it again.';
  static const String resetModelButton = 'Reset Model Download';
  static const String devModeEnabled = 'Developer mode enabled';

  // Debug
  static const String debugTitle = 'Debug';
  static const String clearLogsTooltip = 'Clear logs';
  static const String exportLogsTooltip = 'Export logs';
  static const String systemSection = 'System';
  static const String ramUsage = 'RAM Usage';
  static const String tokenThroughput = 'Token Throughput';
  static const String lastTokens = 'Last Tokens';
  static const String debugContextUsageLabel = 'Context Usage';
  static const String contextTruncated =
      'Context truncated — older messages omitted';
  static const String truncationWarningBody =
      'Older messages were omitted to fit the context window.';
  static const String batteryHealth = 'Battery & Health';
  static const String level = 'Level';
  static const String charging = 'Charging';
  static const String yes = 'Yes';
  static const String no = 'No';
  static const String batterySaver = 'Battery Saver';
  static const String active = 'Active';
  static const String inactive = 'Inactive';
  static const String heavyOpSafe = 'Heavy Op Safe';
  static const String downloadSafe = 'Download Safe';
  static const String logsSection = 'Logs (last 50 lines)';
  static const String emptyLogs = '(empty)';
  static const String disableDevMode = 'Disable Developer Mode';
  static const String devModeDisabled = 'Developer mode disabled';

  // Health Bar
  static const String systemNormal = 'System: Normal';
  static const String systemWarm = 'System: Warm';
  static const String systemHot = 'System: Hot';
  static const String healthStatus = 'Health status';
  static const String detailsExpanded = 'System details expanded';

  // Errors
  static const String errorOccurred = 'Error';
  static const String noResponse = 'No response generated. Tap to retry.';
  static const String thermalEmergency = 'Generation stopped — device too hot.';
  static const String batteryEmergency =
      'Generation stopped — battery too low.';
  static const String generationInProgress =
      'Generation in progress. Stop it first.';
  static const String privacyModeOn = 'INFO logs disabled. WARN/ERROR only.';
  static const String privacyPolicyError = 'Could not open privacy policy URL.';
  static const String exportLogsTitle = 'Export Logs';
  static const String exportLogsWarning =
      'Logs may contain conversation context. Only share with trusted recipients.';
  static const String exportLogsSubject = 'Vitalis Debug Logs';
  static const String generationTimeout =
      'The response took too long to generate. Please try again.';
  static const String healthCheckFailed =
      'Your device isn\'t ready right now. Please try again in a moment.';
  static const String generationFailed = 'Generation failed: {error}';
  static const String generationStartFailed =
      'Failed to start generation: {error}';
  static const String downloadFailed =
      'Download failed. Check your connection.';
  static const String batteryTooLow =
      'Battery is too low for AI responses. Please plug in your device.';
  static const String deviceNotReady =
      'Your device isn\'t ready right now. Please try again in a moment.';
  static const String somethingWentWrong = 'Something went wrong';
  static const String tryAgain = 'Try Again';

  // Empty States
  static const String noChatsYet = 'No chats yet';
  static const String startAConversation =
      'Start a conversation to get started';
  static const String noNotesYet = 'No notes yet';
  static const String createNoteToStart = 'Create a note to get started';
  static const String noPersonasYet = 'No personas yet';
  static const String createPersonaToStart = 'Create a persona to get started';

  // Character Counter
  static const String characterCount = '{current} / {max}';

  // Dark Mode
  static const String darkModeToggle = 'Dark Mode';
}
