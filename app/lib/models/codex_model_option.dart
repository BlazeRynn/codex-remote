import '../utils/json_utils.dart';

class CodexModelOption {
  const CodexModelOption({
    required this.id,
    required this.model,
    required this.displayName,
    required this.description,
    required this.isDefault,
    this.defaultReasoningEffort,
    this.supportedReasoningEfforts = const [],
  });

  final String id;
  final String model;
  final String displayName;
  final String description;
  final bool isDefault;
  final String? defaultReasoningEffort;
  final List<String> supportedReasoningEfforts;

  factory CodexModelOption.fromJson(Map<String, dynamic> json) {
    return CodexModelOption(
      id: readString(json, const ['id'], fallback: 'unknown-model'),
      model: readString(json, const ['model'], fallback: 'unknown'),
      displayName: readString(
        json,
        const ['displayName', 'model'],
        fallback: 'Unknown model',
      ),
      description: readString(
        json,
        const ['description'],
        fallback: 'No description available.',
      ),
      isDefault: readBool(json, const ['isDefault']) ?? false,
      defaultReasoningEffort: readString(
        json,
        const ['defaultReasoningEffort'],
      ).trim().isEmpty
          ? null
          : readString(json, const ['defaultReasoningEffort']),
      supportedReasoningEfforts: asJsonList(
        json['supportedReasoningEfforts'],
      ).map((value) => value.toString()).toList(growable: false),
    );
  }
}
