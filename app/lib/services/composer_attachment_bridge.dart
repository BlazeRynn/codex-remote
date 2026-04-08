import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/codex_input_part.dart';
import '../utils/json_utils.dart';

class ComposerAttachmentBridge {
  const ComposerAttachmentBridge();

  static const MethodChannel _channel = MethodChannel(
    'codex_control/attachments',
  );

  Future<List<CodexInputPart>> pickAttachments() {
    return _invokeListMethod('pickAttachments');
  }

  Future<List<CodexInputPart>> readClipboardAttachments() {
    return _invokeListMethod('readClipboardAttachments');
  }

  Future<List<CodexInputPart>> _invokeListMethod(String method) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return const [];
    }

    final List<Object?>? response;
    try {
      response = await _channel.invokeMethod<List<Object?>>(method);
    } on MissingPluginException {
      return const [];
    }
    return asJsonList(response)
        .map(asJsonMap)
        .map(CodexInputPart.fromPlatformMap)
        .whereType<CodexInputPart>()
        .toList(growable: false);
  }
}

const composerAttachmentBridge = ComposerAttachmentBridge();
