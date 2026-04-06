enum CodexComposerMode {
  chat,
  agent,
  agentFullAccess;

  String get label {
    switch (this) {
      case CodexComposerMode.chat:
        return 'Chat';
      case CodexComposerMode.agent:
        return 'Agent';
      case CodexComposerMode.agentFullAccess:
        return 'Agent (Full Access)';
    }
  }

  String get bridgeValue {
    switch (this) {
      case CodexComposerMode.chat:
        return 'chat';
      case CodexComposerMode.agent:
        return 'agent';
      case CodexComposerMode.agentFullAccess:
        return 'agent_full_access';
    }
  }

  static CodexComposerMode fromBridgeValue(String value) {
    switch (value.trim()) {
      case 'chat':
        return CodexComposerMode.chat;
      case 'agent_full_access':
        return CodexComposerMode.agentFullAccess;
      case 'agent':
      default:
        return CodexComposerMode.agent;
    }
  }
}
