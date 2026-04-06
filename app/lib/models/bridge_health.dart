import '../utils/json_utils.dart';

class BridgeHealth {
  const BridgeHealth({
    required this.reachable,
    required this.status,
    this.version,
    this.message,
  });

  const BridgeHealth.offline([this.message])
    : reachable = false,
      status = 'offline',
      version = null;

  final bool reachable;
  final String status;
  final String? version;
  final String? message;

  String get label {
    if (reachable) {
      return status;
    }
    return message?.trim().isNotEmpty == true ? message!.trim() : 'offline';
  }

  factory BridgeHealth.fromJson(Map<String, dynamic> json) {
    final status = readString(json, const [
      'status',
      'state',
    ], fallback: 'online');

    return BridgeHealth(
      reachable: readBool(json, const ['ok', 'healthy']) ?? true,
      status: status,
      version: readString(json, const ['version', 'bridgeVersion']),
      message: readString(json, const ['message', 'detail']),
    );
  }
}
