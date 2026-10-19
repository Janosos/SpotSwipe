class Place {
  /// Umbral predeterminado en kilómetros a partir del cual un lugar se marca como "Lejos".
  static const double defaultFarThresholdKm = 4.0;

  final String id;
  final String name;
  final String category;
  final String subcategoryLabel;
  final String imageUrl;
  final double rating;
  final int reviewsCount;
  final String priceLevel;
  final double distanceKm;
  final List<String> tags;
  final double latitude;
  final double longitude;
  final String? address;
  final bool isRealMapPhoto;

  const Place({
    required this.id,
    required this.name,
    required this.category,
    this.subcategoryLabel = 'Lugar destacado',
    required this.imageUrl,
    required this.rating,
    required this.reviewsCount,
    required this.priceLevel,
    required this.distanceKm,
    required this.tags,
    required this.latitude,
    required this.longitude,
    this.address,
    this.isRealMapPhoto = false,
  });

  /// Indica si el lugar está lejos según el umbral configurado.
  bool isFarWithThreshold([double thresholdKm = defaultFarThresholdKm]) =>
      distanceKm >= thresholdKm;

  /// Getter por defecto para compatibilidad.
  bool get isFar => distanceKm >= defaultFarThresholdKm;

  /// Formatea la distancia para mostrar metros cuando es < 1 km o km cuando es >= 1 km.
  String get formattedDistance {
    if (distanceKm < 1.0) {
      final int meters = (distanceKm * 1000).round().clamp(50, 999);
      return '${meters}m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  /// Tiempo estimado caminando o en auto según la distancia.
  String get estimatedTimeLabel {
    if (distanceKm <= 1.2) {
      final int walkMinutes = (distanceKm * 12).round().clamp(2, 20);
      return '$walkMinutes min a pie';
    }
    final int driveMinutes = (distanceKm * 2.5 + 2).round().clamp(4, 60);
    return '$driveMinutes min en auto';
  }

  Place copyWith({
    String? id,
    String? name,
    String? category,
    String? subcategoryLabel,
    String? imageUrl,
    double? rating,
    int? reviewsCount,
    String? priceLevel,
    double? distanceKm,
    List<String>? tags,
    double? latitude,
    double? longitude,
    String? address,
    bool? isRealMapPhoto,
  }) {
    return Place(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      subcategoryLabel: subcategoryLabel ?? this.subcategoryLabel,
      imageUrl: imageUrl ?? this.imageUrl,
      rating: rating ?? this.rating,
      reviewsCount: reviewsCount ?? this.reviewsCount,
      priceLevel: priceLevel ?? this.priceLevel,
      distanceKm: distanceKm ?? this.distanceKm,
      tags: tags ?? this.tags,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      isRealMapPhoto: isRealMapPhoto ?? this.isRealMapPhoto,
    );
  }

  /// Ordena los lugares priorizando los más cercanos y con mejores reseñas,
  /// alejándose progresivamente en distancia.
  static List<Place> sortByClosestAndBestReviews(List<Place> places) {
    final sorted = List<Place>.from(places);
    sorted.sort((a, b) {
      // Franjas de proximidad cada 1.0 km (0-1km, 1-2km, 2-3km...)
      final int bandA = (a.distanceKm / 1.0).floor();
      final int bandB = (b.distanceKm / 1.0).floor();

      if (bandA != bandB) {
        return bandA.compareTo(bandB);
      }

      // Dentro de la misma franja de cercanía, prioriza mejor calificación y reseñas
      final double scoreA = (a.rating * 2.2) +
          (a.reviewsCount / 1000.0).clamp(0.0, 1.5) -
          (a.distanceKm * 0.4);
      final double scoreB = (b.rating * 2.2) +
          (b.reviewsCount / 1000.0).clamp(0.0, 1.5) -
          (b.distanceKm * 0.4);

      final int scoreComp = scoreB.compareTo(scoreA);
      if (scoreComp != 0) return scoreComp;

      return a.distanceKm.compareTo(b.distanceKm);
    });
    return sorted;
  }

  /// Lista inicial de respaldo antes de recibir respuesta del GPS.
  static const List<Place> mockPlaces = [
    Place(
      id: 'place_1',
      name: 'Café Nin',
      category: 'Cafeterías',
      subcategoryLabel: 'Cafetería de Especialidad',
      imageUrl:
          'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?auto=format&fit=crop&w=1000&q=80',
      rating: 4.9,
      reviewsCount: 1420,
      priceLevel: '\$\$',
      distanceKm: 0.45,
      tags: ['Brunch', 'Panadería Artesanal', 'Terraza', 'Wi-Fi'],
      latitude: 19.428152,
      longitude: -99.159124,
      address: 'Calle Havre 73, Juárez',
    ),
    Place(
      id: 'place_2',
      name: 'Hanky Panky Speakeasy',
      category: 'Bares',
      subcategoryLabel: 'Cocktail & Vinyl Bar',
      imageUrl:
          'https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=1000&q=80',
      rating: 4.8,
      reviewsCount: 980,
      priceLevel: '\$\$\$',
      distanceKm: 0.85,
      tags: ['Mixología', 'Speakeasy', 'Reserva recomendada'],
      latitude: 19.427012,
      longitude: -99.156841,
      address: 'Turín 52, Roma Norte',
    ),
    Place(
      id: 'place_3',
      name: 'Contramar',
      category: 'Restaurantes',
      subcategoryLabel: 'Cocina del Mar',
      imageUrl:
          'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=1000&q=80',
      rating: 4.9,
      reviewsCount: 2310,
      priceLevel: '\$\$\$',
      distanceKm: 1.4,
      tags: ['Mariscos Frescos', 'Terraza', 'Tostadas de Atún'],
      latitude: 19.419632,
      longitude: -99.167028,
      address: 'Calle Durango 200, Roma Norte',
    ),
    Place(
      id: 'place_4',
      name: 'Condesa DF Hotel',
      category: 'Hoteles',
      subcategoryLabel: 'Hotel Boutique & Rooftop',
      imageUrl:
          'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=1000&q=80',
      rating: 4.8,
      reviewsCount: 675,
      priceLevel: '\$\$\$',
      distanceKm: 2.1,
      tags: ['Rooftop Lounge', 'Diseño Boutique', 'Spa'],
      latitude: 19.416251,
      longitude: -99.172638,
      address: 'Av. Veracruz 102, Condesa',
    ),
  ];
}

/// Modelo para representar una zona concurrida cercana al usuario.
class BusyZone {
  final String id;
  final String name;
  final String subtitle;
  final double latitude;
  final double longitude;
  final int radiusMeters;

  const BusyZone({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 3000,
  });
}
