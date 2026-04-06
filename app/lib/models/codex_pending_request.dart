import '../utils/json_utils.dart';

class CodexPendingAction {
  const CodexPendingAction({
    required this.id,
    required this.label,
    required this.recommended,
    required this.destructive,
  });

  final String id;
  final String label;
  final bool recommended;
  final bool destructive;

  factory CodexPendingAction.fromJson(Map<String, dynamic> json) {
    return CodexPendingAction(
      id: readString(json, const ['id'], fallback: 'action'),
      label: readString(json, const ['label'], fallback: 'Continue'),
      recommended: readBool(json, const ['recommended']) ?? false,
      destructive: readBool(json, const ['destructive']) ?? false,
    );
  }
}

class CodexPendingOption {
  const CodexPendingOption({
    required this.id,
    required this.label,
    this.description,
    required this.recommended,
  });

  final String id;
  final String label;
  final String? description;
  final bool recommended;

  factory CodexPendingOption.fromJson(Map<String, dynamic> json) {
    return CodexPendingOption(
      id: readString(json, const ['id'], fallback: 'option'),
      label: readString(json, const ['label'], fallback: 'Option'),
      description: readString(json, const ['description']).trim().isEmpty
          ? null
          : readString(json, const ['description']),
      recommended: readBool(json, const ['recommended']) ?? false,
    );
  }
}

class CodexPendingQuestion {
  const CodexPendingQuestion({
    required this.id,
    required this.label,
    required this.prompt,
    required this.allowFreeform,
    required this.multiSelect,
    required this.options,
  });

  final String id;
  final String label;
  final String prompt;
  final bool allowFreeform;
  final bool multiSelect;
  final List<CodexPendingOption> options;

  factory CodexPendingQuestion.fromJson(Map<String, dynamic> json) {
    return CodexPendingQuestion(
      id: readString(json, const ['id'], fallback: 'question'),
      label: readString(json, const ['label'], fallback: 'Question'),
      prompt: readString(json, const ['prompt', 'question'], fallback: ''),
      allowFreeform: readBool(json, const ['allowFreeform']) ?? false,
      multiSelect: readBool(json, const ['multiSelect']) ?? false,
      options: asJsonList(
        json['options'],
      ).map(asJsonMap).map(CodexPendingOption.fromJson).toList(
        growable: false,
      ),
    );
  }
}

enum CodexPendingFieldType { text, number, boolean, singleSelect, multiSelect }

class CodexPendingFormField {
  const CodexPendingFormField({
    required this.id,
    required this.label,
    this.description,
    required this.type,
    required this.required,
    required this.options,
    this.defaultValue,
  });

  final String id;
  final String label;
  final String? description;
  final CodexPendingFieldType type;
  final bool required;
  final List<CodexPendingOption> options;
  final Object? defaultValue;

  factory CodexPendingFormField.fromJson(Map<String, dynamic> json) {
    return CodexPendingFormField(
      id: readString(json, const ['id'], fallback: 'field'),
      label: readString(json, const ['label'], fallback: 'Field'),
      description: readString(json, const ['description']).trim().isEmpty
          ? null
          : readString(json, const ['description']),
      type: _fieldTypeFromString(
        readString(json, const ['type'], fallback: 'text'),
      ),
      required: readBool(json, const ['required']) ?? false,
      options: asJsonList(
        json['options'],
      ).map(asJsonMap).map(CodexPendingOption.fromJson).toList(
        growable: false,
      ),
      defaultValue: json['defaultValue'],
    );
  }

  static CodexPendingFieldType _fieldTypeFromString(String value) {
    switch (value.trim()) {
      case 'number':
        return CodexPendingFieldType.number;
      case 'boolean':
        return CodexPendingFieldType.boolean;
      case 'single_select':
        return CodexPendingFieldType.singleSelect;
      case 'multi_select':
        return CodexPendingFieldType.multiSelect;
      case 'text':
      default:
        return CodexPendingFieldType.text;
    }
  }
}

class CodexPendingRequest {
  const CodexPendingRequest({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    required this.actions,
    required this.questions,
    required this.formFields,
    required this.receivedAt,
    this.threadId,
    this.turnId,
    this.itemId,
    this.detail,
    this.command,
    this.cwd,
    this.url,
    this.permissions = const {},
    this.raw = const {},
  });

  final String id;
  final String kind;
  final String title;
  final String message;
  final List<CodexPendingAction> actions;
  final List<CodexPendingQuestion> questions;
  final List<CodexPendingFormField> formFields;
  final DateTime receivedAt;
  final String? threadId;
  final String? turnId;
  final String? itemId;
  final String? detail;
  final String? command;
  final String? cwd;
  final String? url;
  final Map<String, dynamic> permissions;
  final Map<String, dynamic> raw;

  factory CodexPendingRequest.fromJson(Map<String, dynamic> json) {
    return CodexPendingRequest(
      id: readString(json, const ['id'], fallback: 'pending-request'),
      kind: readString(json, const ['kind'], fallback: 'request'),
      title: readString(json, const ['title'], fallback: 'Pending request'),
      message: readString(json, const ['message'], fallback: ''),
      actions: asJsonList(
        json['actions'],
      ).map(asJsonMap).map(CodexPendingAction.fromJson).toList(growable: false),
      questions: asJsonList(
        json['questions'],
      ).map(asJsonMap).map(CodexPendingQuestion.fromJson).toList(
        growable: false,
      ),
      formFields: asJsonList(
        json['formFields'],
      ).map(asJsonMap).map(CodexPendingFormField.fromJson).toList(
        growable: false,
      ),
      receivedAt:
          readDate(json, const ['receivedAt', 'occurredAt']) ??
          DateTime.now().toUtc(),
      threadId: readString(json, const ['threadId']).trim().isEmpty
          ? null
          : readString(json, const ['threadId']),
      turnId: readString(json, const ['turnId']).trim().isEmpty
          ? null
          : readString(json, const ['turnId']),
      itemId: readString(json, const ['itemId']).trim().isEmpty
          ? null
          : readString(json, const ['itemId']),
      detail: readString(json, const ['detail']).trim().isEmpty
          ? null
          : readString(json, const ['detail']),
      command: readString(json, const ['command']).trim().isEmpty
          ? null
          : readString(json, const ['command']),
      cwd: readString(json, const ['cwd']).trim().isEmpty
          ? null
          : readString(json, const ['cwd']),
      url: readString(json, const ['url']).trim().isEmpty
          ? null
          : readString(json, const ['url']),
      permissions: asJsonMap(json['permissions']),
      raw: asJsonMap(json['raw']),
    );
  }
}
