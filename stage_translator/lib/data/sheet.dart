// lib/data/sheet.dart
//
// One saved chord sheet. Stored as JSON, one file per sheet.

class Sheet {
  final String id;
  final String title;

  /// The sheet as scanned and reviewed, in its own key, with no labels.
  final String rawText;

  /// The translated sheet as shown in the editor, including hand edits.
  final String translatedText;

  /// Key the chords in [rawText] are written in.
  final String sheetKey;

  /// Key the player performs in (always Doh).
  final String performanceKey;

  /// Key the letters in [translatedText] are currently written in. Equals
  /// [performanceKey] when transposing, [sheetKey] when keeping letters.
  final String lettersKey;

  final bool transposeLetters;
  final bool showQuality;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Sheet({
    required this.id,
    required this.title,
    required this.rawText,
    required this.translatedText,
    required this.sheetKey,
    required this.performanceKey,
    required this.lettersKey,
    this.transposeLetters = true,
    this.showQuality = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Sheet copyWith({
    String? title,
    String? rawText,
    String? translatedText,
    String? sheetKey,
    String? performanceKey,
    String? lettersKey,
    bool? transposeLetters,
    bool? showQuality,
    DateTime? updatedAt,
  }) =>
      Sheet(
        id: id,
        title: title ?? this.title,
        rawText: rawText ?? this.rawText,
        translatedText: translatedText ?? this.translatedText,
        sheetKey: sheetKey ?? this.sheetKey,
        performanceKey: performanceKey ?? this.performanceKey,
        lettersKey: lettersKey ?? this.lettersKey,
        transposeLetters: transposeLetters ?? this.transposeLetters,
        showQuality: showQuality ?? this.showQuality,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'title': title,
        'rawText': rawText,
        'translatedText': translatedText,
        'sheetKey': sheetKey,
        'performanceKey': performanceKey,
        'lettersKey': lettersKey,
        'transposeLetters': transposeLetters,
        'showQuality': showQuality,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Sheet.fromJson(Map<String, dynamic> j) => Sheet(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Untitled',
        rawText: j['rawText'] as String? ?? '',
        translatedText: j['translatedText'] as String? ?? '',
        sheetKey: j['sheetKey'] as String? ?? 'C',
        performanceKey: j['performanceKey'] as String? ?? 'C',
        lettersKey: j['lettersKey'] as String? ?? (j['performanceKey'] as String? ?? 'C'),
        transposeLetters: j['transposeLetters'] as bool? ?? true,
        showQuality: j['showQuality'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
