Map<String, dynamic> asJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}

List<dynamic> asJsonList(dynamic value) {
  if (value is List) {
    return value;
  }
  return const [];
}

String readString(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) {
      continue;
    }

    final text = value.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }

  return fallback;
}

int? readInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }

  return null;
}

bool? readBool(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
          return true;
        case 'false':
        case '0':
        case 'no':
          return false;
      }
    }
    if (value is num) {
      return value != 0;
    }
  }

  return null;
}

DateTime? readDate(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final parsed = _coerceDate(json[key]);
    if (parsed != null) {
      return parsed;
    }
  }

  return null;
}

DateTime? _coerceDate(Object? value) {
  if (value is DateTime) {
    return value;
  }
  if (value is int) {
    return _fromEpoch(value);
  }
  if (value is num) {
    return _fromEpoch(value.toInt());
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed;
    }

    final epoch = int.tryParse(value);
    if (epoch != null) {
      return _fromEpoch(epoch);
    }
    return null;
  }
  if (value is Map) {
    final map = asJsonMap(value);

    for (final key in const [
      'occurredAt',
      'timestamp',
      'createdAt',
      'updatedAt',
      'value',
      'dateTime',
      'datetime',
      'iso',
      'iso8601',
    ]) {
      final nested = _coerceDate(map[key]);
      if (nested != null) {
        return nested;
      }
    }

    final milliseconds = _coerceInt(
      map['millisecondsSinceEpoch'] ??
          map['milliseconds'] ??
          map['millis'] ??
          map['ms'] ??
          map['epochMilliseconds'] ??
          map['epochMillis'] ??
          map['unixMs'],
    );
    if (milliseconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }

    final seconds = _coerceInt(
      map['seconds'] ??
          map['_seconds'] ??
          map['epochSeconds'] ??
          map['unixSeconds'] ??
          map['secs'] ??
          map['sec'],
    );
    if (seconds != null) {
      final nanoseconds =
          _coerceInt(
            map['nanoseconds'] ??
                map['_nanoseconds'] ??
                map['nanos'] ??
                map['ns'],
          ) ??
          0;
      return _fromEpoch(
        seconds,
      ).add(Duration(microseconds: nanoseconds ~/ 1000));
    }
  }
  return null;
}

int? _coerceInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

DateTime _fromEpoch(int value) {
  final milliseconds = value > 9999999999 ? value : value * 1000;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}
