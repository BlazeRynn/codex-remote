String formatRelativeTime(DateTime? value) {
  if (value == null) {
    return 'Unknown time';
  }

  final local = value.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);

  if (difference.inSeconds < 45) {
    return 'just now';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays}d ago';
  }

  return formatAbsoluteTime(local);
}

String formatAbsoluteTime(DateTime? value) {
  if (value == null) {
    return 'Unknown time';
  }

  final local = value.toLocal();
  return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
      '${_pad(local.hour)}:${_pad(local.minute)}';
}

String _pad(int value) => value.toString().padLeft(2, '0');
