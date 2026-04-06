import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('zh')];

  static AppStrings of(BuildContext context) {
    final strings = Localizations.of<AppStrings>(context, AppStrings);
    assert(strings != null, 'AppStrings is not available in this context.');
    return strings!;
  }

  static const delegate = _AppStringsDelegate();

  bool get isChinese => locale.languageCode.toLowerCase().startsWith('zh');

  String text(String english, String chinese) {
    return isChinese ? chinese : english;
  }

  String humanizeMachineLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return text('Unknown', '未知');
    }

    final normalized = trimmed
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.isEmpty) {
      return text('Unknown', '未知');
    }

    final english = '${normalized[0].toUpperCase()}${normalized.substring(1)}';
    if (!isChinese) {
      return english;
    }

    return _chineseMachineLabels[english.toLowerCase()] ?? english;
  }

  String formatRelativeTime(DateTime? value) {
    if (value == null) {
      return text('Unknown time', '未知时间');
    }

    final local = value.toLocal();
    final now = DateTime.now();
    final difference = now.difference(local);

    if (difference.inSeconds < 45) {
      return text('just now', '刚刚');
    }
    if (difference.inMinutes < 60) {
      return isChinese
          ? '${difference.inMinutes} 分钟前'
          : '${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) {
      return isChinese
          ? '${difference.inHours} 小时前'
          : '${difference.inHours}h ago';
    }
    if (difference.inDays < 7) {
      return isChinese
          ? '${difference.inDays} 天前'
          : '${difference.inDays}d ago';
    }

    return formatAbsoluteTime(local);
  }

  String formatAbsoluteTime(DateTime? value) {
    if (value == null) {
      return text('Unknown time', '未知时间');
    }

    final local = value.toLocal();
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
        '${_pad(local.hour)}:${_pad(local.minute)}';
  }

  static const Map<String, String> _chineseMachineLabels = {
    'unknown': '未知',
    'online': '在线',
    'offline': '离线',
    'starting': '启动中',
    'syncing': '同步中',
    'active': '活动中',
    'idle': '空闲',
    'error': '错误',
    'failed': '失败',
    'connecting': '连接中',
    'connected': '已连接',
    'disconnected': '已断开',
    'completed': '已完成',
    'in progress': '进行中',
    'commentary': '评论',
    'final answer': '最终答复',
    'user': '用户',
    'assistant': '助手',
    'bridge not configured': 'App-server 未配置',
    'bridge unreachable': 'App-server 不可达',
    'ready': '就绪',
    'missing': '缺失',
  };
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppStrings.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppStrings> load(Locale locale) {
    return SynchronousFuture(AppStrings(locale));
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}

String _pad(int value) => value.toString().padLeft(2, '0');
