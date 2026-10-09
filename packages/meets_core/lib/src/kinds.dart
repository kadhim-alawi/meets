/// Qloo entity categories that Meets works with.
enum EntityKind {
  book('urn:entity:book', 'Book', 'Books'),
  movie('urn:entity:movie', 'Film', 'Films'),
  tvShow('urn:entity:tv_show', 'TV show', 'TV shows'),
  artist('urn:entity:artist', 'Artist', 'Artists'),
  videoGame('urn:entity:videogame', 'Game', 'Games'),
  podcast('urn:entity:podcast', 'Podcast', 'Podcasts'),
  person('urn:entity:person', 'Person', 'People'),
  brand('urn:entity:brand', 'Brand', 'Brands'),
  place('urn:entity:place', 'Place', 'Places'),
  destination('urn:entity:destination', 'Destination', 'Destinations'),
  unknown('urn:entity', 'Entity', 'Entities');

  const EntityKind(this.urn, this.label, this.plural);

  final String urn;
  final String label;
  final String plural;

  /// Qloo's own docs spell the game type two ways (`videogame` in the
  /// Insights reference, `video_game` in the hackathon guide).
  static const videoGameAlias = 'urn:entity:video_game';

  static EntityKind fromUrn(String? urn) {
    if (urn == null) return EntityKind.unknown;
    if (urn == videoGameAlias) return EntityKind.videoGame;
    for (final kind in values) {
      if (kind.urn == urn) return kind;
    }
    // Deprecated person sub-types still show up in `types` lists.
    if (urn.startsWith('urn:entity:') &&
        const ['actor', 'author', 'director'].contains(urn.split(':').last)) {
      return EntityKind.person;
    }
    return EntityKind.unknown;
  }

  static EntityKind fromName(String? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return EntityKind.unknown;
  }

  /// Short verb phrase used in copy: "readers also watch", "fans also play".
  String get consumeVerb => switch (this) {
        EntityKind.book => 'read',
        EntityKind.movie || EntityKind.tvShow => 'watch',
        EntityKind.artist => 'listen to',
        EntityKind.videoGame => 'play',
        EntityKind.podcast => 'listen to',
        EntityKind.person => 'follow',
        EntityKind.brand => 'buy from',
        EntityKind.place || EntityKind.destination => 'visit',
        EntityKind.unknown => 'love',
      };
}

/// Qloo's demographic age bands, in display order.
enum AgeBand {
  under25('24_and_younger', '≤24'),
  from25to29('25_to_29', '25–29'),
  from30to34('30_to_34', '30–34'),
  from35to44('35_to_44', '35–44'),
  from45to54('45_to_54', '45–54'),
  over55('55_and_older', '55+');

  const AgeBand(this.key, this.label);

  final String key;
  final String label;

  static AgeBand? fromKey(String? key) {
    for (final band in values) {
      if (band.key == key) return band;
    }
    return null;
  }
}
