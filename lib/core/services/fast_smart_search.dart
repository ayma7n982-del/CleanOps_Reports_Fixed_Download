/// A lightweight, offline-capable Arabic search index.
/// Only the supplied, already-authorized records are indexed.
class FastSearchRecord {
  final String collection;
  final String id;
  final String category;
  final Map<String, dynamic> data;
  final String title;
  late final List<String> words;
  late final List<String> titleWords;
  late final String compactText;

  FastSearchRecord({
    required this.collection,
    required this.id,
    required this.category,
    required this.data,
  }) : title = _displayTitle(data, id) {
    final parts = <String>[category, title, id];
    const fields = <String>[
      'name', 'nameAr', 'fullName', 'displayName', 'username', 'workerName',
      'groupName', 'groupNumber', 'groupId', 'municipalityName',
      'municipality', 'municipalityId', 'councilName', 'locationName',
      'location', 'address', 'street', 'area', 'landfill', 'dumpsiteName',
      'containerName', 'containerNumber', 'equipmentName', 'machine',
      'plateNumber', 'type', 'model', 'title', 'description', 'detail',
      'status', 'machineStatus', 'issueStatus', 'role', 'cycleName',
      'number', 'notes', 'body',
    ];
    for (final key in fields) {
      final value = data[key];
      if (value is String && value.isNotEmpty) {
        parts.add(value.length <= 180 ? value : value.substring(0, 180));
      } else if (value is num) {
        parts.add(value.toString());
      }
    }
    final normalized = FastSmartSearch.normalize(parts.join(' '));
    words = normalized.split(' ').where((part) => part.isNotEmpty).toSet().toList();
    titleWords = FastSmartSearch.normalize(title).split(' ');
    compactText = normalized.replaceAll(' ', '');
  }

  static String _displayTitle(Map<String, dynamic> data, String id) {
    const fields = <String>[
      'name', 'nameAr', 'fullName', 'displayName', 'workerName',
      'locationName', 'containerName', 'equipmentName', 'machine',
      'groupName', 'cycleName', 'title', 'username', 'number',
    ];
    for (final key in fields) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return id;
  }
}

class FastSmartSearch {
  final Map<String, List<FastSearchRecord>> _sources = {};

  int get recordCount => _sources.values.fold(0, (count, rows) => count + rows.length);

  void replaceSource(
    String source,
    String category,
    Iterable<Map<String, dynamic>> documents, {
    String Function(Map<String, dynamic>)? categoryFor,
  }) {
    final unique = <String, FastSearchRecord>{};
    for (final document in documents) {
      if (document['isDeleted'] == true) continue;
      final id = (document['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      unique[id] = FastSearchRecord(
        collection: source,
        id: id,
        category: categoryFor?.call(document) ?? category,
        data: document,
      );
    }
    _sources[source] = unique.values.toList(growable: false);
  }

  static String normalize(String value) {
    const digits = <String, String>{
      '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
      '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
      '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
      '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
    };
    var text = value.toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');
    for (final digit in digits.entries) {
      text = text.replaceAll(digit.key, digit.value);
    }
    return text.replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // Synonyms are expanded only after two typed characters; one character
  // always finds real word prefixes without flooding results.
  static const _synonyms = <List<String>>[
    ['عامل', 'عمال', 'عاملين', 'موظف', 'موظفين', 'طاقم', 'قوى عامله'],
    ['مجموعه', 'مجموعات', 'فريق', 'فرق', 'طواقم'],
    ['مكب', 'مكبات', 'مطمر', 'مطامر', 'مردم', 'مرادم'],
    ['حاويه', 'حاويات', 'سله', 'سلال', 'كونتينر', 'حاوية'],
    ['نقله', 'نقل', 'ترحيل', 'ترحيلات', 'رحله', 'رحلات'],
    ['معده', 'معدات', 'كاره', 'كارات', 'عربه', 'اليات', 'مركبه'],
    ['بلديه', 'بلديات', 'مجلس محلي', 'بلدية'],
    ['دوره', 'دورات', 'ورديه', 'وردية'],
    ['حضور', 'دوام', 'مداومه', 'بصمه'],
    ['غياب', 'غيابات', 'متغيب'],
    ['تقرير', 'تقارير', 'احصائيات', 'تحليل', 'ملخص'],
    ['ممتلئ', 'ممتلئه', 'full', 'filled'],
    ['فارغ', 'فارغه', 'empty'],
    ['طارئ', 'طوارئ', 'استغاثه', 'sos', 'بلاغ'],
  ];

  static List<String> _variants(String term) {
    if (term.length < 2) return [term];
    final results = <String>{term};
    for (final group in _synonyms) {
      final normalized = group.map(normalize).toList();
      if (normalized.any((word) => word == term || word.startsWith(term))) {
        results.addAll(normalized);
      }
    }
    return results.toList();
  }

  static int _editDistance(String first, String second, int maxDistance) {
    if ((first.length - second.length).abs() > maxDistance) {
      return maxDistance + 1;
    }
    if (first == second) return 0;
    if (first.length == second.length) {
      final differences = <int>[];
      for (var i = 0; i < first.length; i++) {
        if (first.codeUnitAt(i) != second.codeUnitAt(i)) differences.add(i);
      }
      if (differences.length == 2 &&
          differences[1] == differences[0] + 1 &&
          first.codeUnitAt(differences[0]) == second.codeUnitAt(differences[1]) &&
          first.codeUnitAt(differences[1]) == second.codeUnitAt(differences[0])) {
        return 1;
      }
    }
    var previous = List<int>.generate(second.length + 1, (i) => i);
    for (var i = 0; i < first.length; i++) {
      final next = List<int>.filled(second.length + 1, 0);
      next[0] = i + 1;
      var rowMin = next[0];
      for (var j = 0; j < second.length; j++) {
        final cost = first.codeUnitAt(i) == second.codeUnitAt(j) ? 0 : 1;
        final value = _min3(next[j] + 1, previous[j + 1] + 1, previous[j] + cost);
        next[j + 1] = value;
        if (value < rowMin) rowMin = value;
      }
      if (rowMin > maxDistance) return maxDistance + 1;
      previous = next;
    }
    return previous.last;
  }

  static int _min3(int a, int b, int c) {
    var min = a < b ? a : b;
    return c < min ? c : min;
  }

  static int _termScore(FastSearchRecord entry, String variant, bool synonym) {
    var best = 0;
    for (final word in entry.words) {
      if (word == variant) {
        best = 100;
      } else if (word.startsWith(variant)) {
        if (best < 76) best = 76;
      } else if (variant.length >= 3 && word.contains(variant)) {
        if (best < 45) best = 45;
      } else if (variant.length >= 3) {
        final maxEdits = variant.length >= 6 ? 2 : 1;
        if ((word.length - variant.length).abs() <= maxEdits &&
            _editDistance(word, variant, maxEdits) <= maxEdits &&
            best < 28) {
          best = 28;
        }
      }
      if (best == 100) break;
    }
    if (best == 0) return 0;
    if (synonym) best = best > 22 ? best - 22 : 8;
    if (entry.titleWords.any((word) => word == variant || word.startsWith(variant))) {
      best += 18;
    }
    return best;
  }

  List<FastSearchRecord> find(String input, {int limit = 60}) {
    final query = normalize(input);
    if (query.isEmpty) return const [];
    final terms = query.split(' ').where((t) => t.isNotEmpty).toList();
    final variants = [for (final term in terms) _variants(term)];
    final ranked = <(int, FastSearchRecord)>[];
    for (final rows in _sources.values) {
      for (final record in rows) {
        var score = 0;
        var matchAll = true;
        for (var i = 0; i < terms.length; i++) {
          var best = 0;
          for (final candidate in variants[i]) {
            final value = _termScore(record, candidate, candidate != terms[i]);
            if (value > best) best = value;
          }
          if (best == 0) {
            matchAll = false;
            break;
          }
          score += best;
        }
        if (!matchAll) continue;
        if (normalize(record.id) == query) score += 250;
        if (normalize(record.title).startsWith(query)) score += 50;
        if (record.compactText.contains(query.replaceAll(' ', ''))) score += 12;
        ranked.add((score, record));
      }
    }
    ranked.sort((a, b) {
      final relevance = b.$1.compareTo(a.$1);
      return relevance != 0 ? relevance : a.$2.title.compareTo(b.$2.title);
    });
    return ranked.take(limit).map((item) => item.$2).toList(growable: false);
  }
}
