import 'formats.dart';
import 'json.dart';
import 'kinds.dart';

/// Where a creator wants comps to sit on the popularity curve.
enum SizePref {
  indie('Indie', 'Small, devoted audiences. Great for micro-budget and debut work.'),
  breakout('Breakout', 'Recognisable but not ubiquitous. What agents and buyers want to see.'),
  mainstream('Mainstream', 'Big, broad hits. Use when you need shorthand, not positioning.');

  const SizePref(this.label, this.help);

  final String label;
  final String help;

  static SizePref fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => SizePref.breakout);
}

/// Something the creator says their work is like. Either typed free text or an
/// entity picked from Qloo autocomplete (then [id] is set).
class AnchorInput {
  const AnchorInput({required this.name, this.kind, this.id, this.suggested = false});

  final String name;
  final EntityKind? kind;
  final String? id;

  /// True when the agent proposed this anchor rather than the creator.
  final bool suggested;

  Json toJson() => compact({'name': name, 'kind': kind?.name, 'id': id, 'suggested': suggested ? true : null});

  factory AnchorInput.fromJson(Json json) => AnchorInput(
        name: asString(json['name']) ?? '',
        kind: json['kind'] == null ? null : EntityKind.fromName(asString(json['kind'])),
        id: asString(json['id']),
        suggested: asBool(json['suggested']),
      );
}

/// Markets Meets can map. `query` goes to Qloo's `filter.location.query`.
class Market {
  const Market(this.code, this.name, this.query);

  final String code;
  final String name;
  final String query;

  static const global = Market('GLOBAL', 'Global', '');

  static const all = <Market>[
    Market('US', 'United States', 'United States'),
    Market('GB', 'United Kingdom', 'United Kingdom'),
    Market('CA', 'Canada', 'Canada'),
    Market('AU', 'Australia', 'Australia'),
    Market('IE', 'Ireland', 'Ireland'),
    Market('NZ', 'New Zealand', 'New Zealand'),
    Market('DE', 'Germany', 'Germany'),
    Market('FR', 'France', 'France'),
    Market('ES', 'Spain', 'Spain'),
    Market('IT', 'Italy', 'Italy'),
    Market('NL', 'Netherlands', 'Netherlands'),
    Market('SE', 'Sweden', 'Sweden'),
    Market('IN', 'India', 'India'),
    Market('JP', 'Japan', 'Japan'),
    Market('KR', 'South Korea', 'South Korea'),
    Market('PH', 'Philippines', 'Philippines'),
    Market('BR', 'Brazil', 'Brazil'),
    Market('MX', 'Mexico', 'Mexico'),
    Market('ZA', 'South Africa', 'South Africa'),
    Market('NG', 'Nigeria', 'Nigeria'),
    global,
  ];

  static Market fromCode(String? code) =>
      all.firstWhere((m) => m.code == code, orElse: () => all.first);
}

/// What the creator tells Meets about their project.
class Brief {
  const Brief({
    required this.format,
    this.title = '',
    this.logline = '',
    this.anchors = const [],
    this.themes = const [],
    this.myComps = const [],
    this.ages = const [],
    this.market = 'US',
    this.recencyYears = 5,
    this.size = SizePref.breakout,
    this.excludeIds = const [],
  });

  final WorkFormat format;
  final String title;

  /// Logline or short description, free text.
  final String logline;

  /// "It's like..." touchstones. These seed every Qloo request.
  final List<AnchorInput> anchors;

  /// Themes, moods or genres in plain words ("found family", "heist").
  final List<String> themes;

  /// Comps the creator already plans to use; Meets checks them.
  final List<AnchorInput> myComps;

  /// Optional audience age bands to weight results toward.
  final List<AgeBand> ages;

  /// Market code from [Market.all].
  final String market;

  /// How recent comps should be, in years. 0 means any year.
  final int recencyYears;
  final SizePref size;

  /// Entities the creator asked to drop.
  final List<String> excludeIds;

  Market get marketInfo => Market.fromCode(market);

  Brief copyWith({
    WorkFormat? format,
    String? title,
    String? logline,
    List<AnchorInput>? anchors,
    List<String>? themes,
    List<AnchorInput>? myComps,
    List<AgeBand>? ages,
    String? market,
    int? recencyYears,
    SizePref? size,
    List<String>? excludeIds,
  }) =>
      Brief(
        format: format ?? this.format,
        title: title ?? this.title,
        logline: logline ?? this.logline,
        anchors: anchors ?? this.anchors,
        themes: themes ?? this.themes,
        myComps: myComps ?? this.myComps,
        ages: ages ?? this.ages,
        market: market ?? this.market,
        recencyYears: recencyYears ?? this.recencyYears,
        size: size ?? this.size,
        excludeIds: excludeIds ?? this.excludeIds,
      );

  /// Basic checks shared by the app (form validation) and the server (API).
  List<String> problems() {
    final out = <String>[];
    if (anchors.where((a) => a.name.trim().isNotEmpty).isEmpty && logline.trim().length < 12) {
      out.add('Add at least one "it\'s like..." touchstone, or describe your project in a sentence.');
    }
    if (anchors.length > 8) out.add('Use at most 8 touchstones.');
    if (myComps.length > 8) out.add('Check at most 8 of your own comps at a time.');
    if (logline.length > 1200) out.add('Keep the description under 1,200 characters.');
    if (title.length > 120) out.add('Keep the title under 120 characters.');
    if (themes.length > 8) out.add('Use at most 8 themes.');
    if (recencyYears < 0 || recencyYears > 50) out.add('Recency must be between 0 and 50 years.');
    return out;
  }

  Json toJson() => compact({
        'format': format.name,
        'title': title,
        'logline': logline,
        'anchors': anchors.map((a) => a.toJson()).toList(),
        'themes': themes,
        'myComps': myComps.map((a) => a.toJson()).toList(),
        'ages': ages.map((a) => a.key).toList(),
        'market': market,
        'recencyYears': recencyYears,
        'size': size.name,
        'excludeIds': excludeIds,
      });

  factory Brief.fromJson(Json json) => Brief(
        format: WorkFormat.fromName(asString(json['format'])),
        title: (asString(json['title']) ?? '').trim(),
        logline: (asString(json['logline']) ?? '').trim(),
        anchors: listOf(json['anchors'], AnchorInput.fromJson).where((a) => a.name.trim().isNotEmpty).toList(),
        themes: stringsOf(json['themes']).map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
        myComps: listOf(json['myComps'], AnchorInput.fromJson).where((a) => a.name.trim().isNotEmpty).toList(),
        ages: stringsOf(json['ages']).map(AgeBand.fromKey).whereType<AgeBand>().toList(),
        market: asString(json['market']) ?? 'US',
        recencyYears: asInt(json['recencyYears']) ?? 5,
        size: SizePref.fromName(asString(json['size'])),
        excludeIds: stringsOf(json['excludeIds']),
      );
}
