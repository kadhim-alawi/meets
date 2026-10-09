import 'kinds.dart';

/// A piece of pitch copy Meets writes for a format.
class CopySpec {
  const CopySpec(this.id, this.title, this.hint);

  final String id;
  final String title;
  final String hint;
}

/// A targeting list Meets builds for a format.
class TargetSpec {
  const TargetSpec(this.id, this.platform, this.how, this.kinds);

  final String id;
  final String platform;
  final String how;

  /// Which scans feed the list, in priority order.
  final List<EntityKind> kinds;
}

const _commonCopy = [
  CopySpec('comp_line', 'Comp line', 'The one-line "X meets Y" that opens every pitch.'),
  CopySpec('audience', 'Who it\'s for', 'A short, evidence-backed paragraph about the audience.'),
  CopySpec('fans_of', 'For fans of', 'A one-liner for bios, store pages, press kits and posts.'),
  CopySpec('ad_hooks', 'Ad hooks', 'Three hooks, each aimed at fans of one comp.'),
];

/// The kind of thing the creator is making. Decides which Qloo category is the
/// "shelf" for comps, which other categories round out the audience, and which
/// pitch copy and targeting lists to write.
enum WorkFormat {
  book(
    label: 'Book',
    noun: 'book',
    audience: 'readers',
    primary: EntityKind.book,
    cross: [EntityKind.movie, EntityKind.tvShow, EntityKind.artist, EntityKind.podcast],
    channels: [EntityKind.podcast, EntityKind.brand],
    recencyParam: 'filter.publication_year.min',
    pitch: CopySpec('pitch', 'Query letter comps', 'The comparables paragraph for a query letter or proposal.'),
    targets: [
      TargetSpec('amazon', 'Amazon Ads', 'Product and author targets for a Sponsored Products campaign.', [EntityKind.book]),
      TargetSpec('bookbub', 'BookBub Ads', 'Comp authors and titles to target readers of.', [EntityKind.book]),
      TargetSpec('meta', 'Meta (Facebook/Instagram)', 'Interests that reach the same people outside the bookstore.',
          [EntityKind.tvShow, EntityKind.movie, EntityKind.artist, EntityKind.podcast]),
    ],
  ),
  film(
    label: 'Film',
    noun: 'film',
    audience: 'viewers',
    primary: EntityKind.movie,
    cross: [EntityKind.tvShow, EntityKind.book, EntityKind.artist, EntityKind.podcast],
    channels: [EntityKind.podcast, EntityKind.brand],
    recencyParam: 'filter.release_year.min',
    pitch: CopySpec('pitch', 'Pitch deck: comps slide', 'Comps and audience for a pitch deck or financing package.'),
    targets: [
      TargetSpec('meta', 'Meta (Facebook/Instagram)', 'Interests for trailer and screening campaigns.',
          [EntityKind.movie, EntityKind.tvShow, EntityKind.artist]),
      TargetSpec('youtube', 'YouTube / Google', 'Titles to use as custom-segment keywords.', [EntityKind.movie, EntityKind.tvShow]),
      TargetSpec('podcast_ads', 'Podcast ads', 'Shows whose listeners match your audience.', [EntityKind.podcast]),
    ],
  ),
  tv(
    label: 'TV series',
    noun: 'series',
    audience: 'viewers',
    primary: EntityKind.tvShow,
    cross: [EntityKind.movie, EntityKind.book, EntityKind.podcast, EntityKind.artist],
    channels: [EntityKind.podcast, EntityKind.brand],
    recencyParam: 'filter.latest_known_year.min',
    pitch: CopySpec('pitch', 'Series pitch: comps', 'Comps and audience for a series pitch or lookbook.'),
    targets: [
      TargetSpec('meta', 'Meta (Facebook/Instagram)', 'Interests for launch and awareness campaigns.',
          [EntityKind.tvShow, EntityKind.movie, EntityKind.podcast]),
      TargetSpec('youtube', 'YouTube / Google', 'Titles to use as custom-segment keywords.', [EntityKind.tvShow, EntityKind.movie]),
      TargetSpec('podcast_ads', 'Podcast ads', 'Shows whose listeners match your audience.', [EntityKind.podcast]),
    ],
  ),
  music(
    label: 'Music',
    noun: 'release',
    audience: 'listeners',
    primary: EntityKind.artist,
    cross: [EntityKind.movie, EntityKind.tvShow, EntityKind.podcast, EntityKind.book],
    channels: [EntityKind.brand, EntityKind.podcast],
    recencyParam: null,
    pitch: CopySpec('pitch', 'Playlist & press pitch', 'The "sounds like / for fans of" pitch for editors, blogs and promoters.'),
    targets: [
      TargetSpec('spotify', 'Spotify / streaming ads', 'Similar artists for fan-targeted campaigns (e.g. Marquee, Showcase).', [EntityKind.artist]),
      TargetSpec('meta', 'Meta (Facebook/Instagram)', 'Artist and culture interests for release-day ads.',
          [EntityKind.artist, EntityKind.tvShow, EntityKind.movie]),
      TargetSpec('youtube', 'YouTube', 'Artists to use as custom-segment keywords for video ads.', [EntityKind.artist]),
    ],
  ),
  game(
    label: 'Game',
    noun: 'game',
    audience: 'players',
    primary: EntityKind.videoGame,
    cross: [EntityKind.movie, EntityKind.tvShow, EntityKind.artist, EntityKind.podcast],
    channels: [EntityKind.podcast, EntityKind.brand],
    recencyParam: null,
    pitch: CopySpec('pitch', 'Store page & publisher pitch', 'The "if you like..." block for a store page or publisher deck.'),
    targets: [
      TargetSpec('steam', 'Steam & store pages', 'Games to reference in tags, "more like this" and press outreach.', [EntityKind.videoGame]),
      TargetSpec('meta', 'Meta (Facebook/Instagram)', 'Interests for wishlist campaigns.',
          [EntityKind.videoGame, EntityKind.tvShow, EntityKind.movie]),
      TargetSpec('reddit', 'Reddit & YouTube', 'Titles to use as community and keyword targets.', [EntityKind.videoGame, EntityKind.tvShow]),
    ],
  ),
  podcast(
    label: 'Podcast',
    noun: 'show',
    audience: 'listeners',
    primary: EntityKind.podcast,
    cross: [EntityKind.book, EntityKind.tvShow, EntityKind.artist, EntityKind.movie],
    channels: [EntityKind.brand, EntityKind.person],
    recencyParam: null,
    pitch: CopySpec('pitch', 'Network & sponsor pitch', 'Comps and audience for a network, guest or sponsor pitch.'),
    targets: [
      TargetSpec('podcast_ads', 'Podcast ad swaps & ads', 'Shows to cross-promote with or advertise on.', [EntityKind.podcast]),
      TargetSpec('meta', 'Meta (Facebook/Instagram)', 'Interests that reach likely listeners.',
          [EntityKind.tvShow, EntityKind.book, EntityKind.artist]),
      TargetSpec('sponsors', 'Sponsor shortlist', 'Brands this audience already loves.', [EntityKind.brand]),
    ],
  ),
  standup(
    label: 'Stand-up',
    noun: 'act',
    audience: 'fans',
    primary: EntityKind.person,
    cross: [EntityKind.tvShow, EntityKind.movie, EntityKind.podcast, EntityKind.artist],
    channels: [EntityKind.podcast, EntityKind.brand],
    recencyParam: null,
    pitch: CopySpec('pitch', 'Booking pitch', 'Comps and audience for a club, festival or special pitch.'),
    targets: [
      TargetSpec('meta', 'Meta (Facebook/Instagram)', 'Comedian and show interests for ticket campaigns.',
          [EntityKind.person, EntityKind.tvShow, EntityKind.podcast]),
      TargetSpec('podcast_ads', 'Podcast ads & guest spots', 'Shows whose listeners match your fans.', [EntityKind.podcast]),
      TargetSpec('youtube', 'YouTube', 'Comedians and shows to use as custom-segment keywords.', [EntityKind.person, EntityKind.tvShow]),
    ],
  );

  const WorkFormat({
    required this.label,
    required this.noun,
    required this.audience,
    required this.primary,
    required this.cross,
    required this.channels,
    required this.recencyParam,
    required this.pitch,
    required this.targets,
  });

  final String label;

  /// "book", "film", "series" ... used in copy.
  final String noun;

  /// "readers", "viewers", "listeners" ...
  final String audience;

  /// The shelf comps come from.
  final EntityKind primary;

  /// Other categories that describe the same audience.
  final List<EntityKind> cross;

  /// Categories that tell the creator where to reach the audience.
  final List<EntityKind> channels;

  /// Insights parameter that keeps comps recent, if Qloo has one for [primary].
  final String? recencyParam;
  final CopySpec pitch;
  final List<TargetSpec> targets;

  List<CopySpec> get copySpecs => [_commonCopy.first, pitch, ..._commonCopy.skip(1)];

  static WorkFormat fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => WorkFormat.book);
}
