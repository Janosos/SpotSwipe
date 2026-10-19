import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/place.dart';

/// Fotografía real georreferenciada obtenida del proveedor geoespacial.
class _GeoTaggedPhoto {
  final String url;
  final String title;
  final double lat;
  final double lon;

  const _GeoTaggedPhoto({
    required this.url,
    required this.title,
    required this.lat,
    required this.lon,
  });
}

/// Servicio optimizado de baja latencia para obtener lugares reales,
/// búsquedas personalizadas, zonas concurridas y fotografías reales georreferenciadas.
class PlacesService {
  PlacesService();

  static const List<String> _overpassMirrors = [
    'https://overpass-api.de/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  // Caché en memoria de los lugares reales del área para búsquedas y filtros instantáneos
  static final Map<String, List<Place>> _areaPlacesCache = {};
  static final Map<String, List<BusyZone>> _zonesCache = {};

  static const Map<String, List<String>> _fallbackCategoryPhotos = {
    'Restaurantes': [
      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=900&q=80',
    ],
    'Cafeterías': [
      'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1509042239860-f550ce710b93?auto=format&fit=crop&w=900&q=80',
    ],
    'Bares': [
      'https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1572116469696-31de0f17cc34?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1543007630-9710e4a00a20?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1470337458703-46ad1756a187?auto=format&fit=crop&w=900&q=80',
    ],
    'Clubs': [
      'https://images.unsplash.com/photo-1566417713940-fe7c737a9ef2?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1571266028243-3716f02d2d2e?auto=format&fit=crop&w=900&q=80',
    ],
    'Hoteles': [
      'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?auto=format&fit=crop&w=900&q=80',
      'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?auto=format&fit=crop&w=900&q=80',
    ],
  };

  /// Limpia la caché en memoria para forzar recarga desde el proveedor de mapas.
  void clearCache() {
    _areaPlacesCache.clear();
    _zonesCache.clear();
  }

  /// Obtiene el nombre corto de la colonia y ciudad actual (ej. "Roma Norte, CDMX").
  Future<String> fetchCurrentAreaLabel({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final Uri uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$latitude&lon=$longitude&zoom=14&addressdetails=1',
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'SpotSwipeFlutterApp/2.1'},
      ).timeout(const Duration(milliseconds: 3500));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final String? suburb = (address['suburb'] ??
                  address['neighbourhood'] ??
                  address['quarter'] ??
                  address['city_district'])
              ?.toString();
          final String? city = (address['city'] ??
                  address['town'] ??
                  address['municipality'] ??
                  address['state'])
              ?.toString();
          if (suburb != null && city != null) {
            return '$suburb, $city';
          }
          if (suburb != null) return suburb;
          if (city != null) return city;
        }
      }
    } catch (_) {}
    return 'Mi ubicación actual';
  }

  /// Detecta zonas concurridas reales cercanas.
  Future<List<BusyZone>> fetchNearbyBusyZones({
    required double latitude,
    required double longitude,
  }) async {
    final String cacheKey =
        '${latitude.toStringAsFixed(2)}_${longitude.toStringAsFixed(2)}';
    if (_zonesCache.containsKey(cacheKey)) {
      return _zonesCache[cacheKey]!;
    }

    final List<BusyZone> zones = [
      BusyZone(
        id: 'zone_immediate',
        name: 'A mi alrededor (< 1.5 km)',
        subtitle: 'Lo más cercano y mejor calificado',
        latitude: latitude,
        longitude: longitude,
        radiusMeters: 1500,
      ),
    ];

    try {
      final String zoneQuery = '''
[out:json][timeout:4];
node["place"~"suburb|neighbourhood|quarter"](around:6000,$latitude,$longitude);
out body 8;
''';
      final response = await _raceOverpassPost(
        zoneQuery,
        timeout: const Duration(milliseconds: 3500),
      );

      if (response != null && response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final elements = (decoded['elements'] as List<dynamic>?) ?? [];
        final Set<String> seen = {};

        for (final raw in elements) {
          final element = raw as Map<String, dynamic>;
          final tags = (element['tags'] as Map<String, dynamic>?) ?? {};
          final String? name = tags['name']?.toString().trim();
          if (name == null || name.isEmpty) continue;
          if (!seen.add(name.toLowerCase())) continue;

          final double? lat = (element['lat'] as num?)?.toDouble();
          final double? lon = (element['lon'] as num?)?.toDouble();
          if (lat == null || lon == null) continue;

          final double distKm = Geolocator.distanceBetween(
                latitude,
                longitude,
                lat,
                lon,
              ) /
              1000.0;

          zones.add(
            BusyZone(
              id: 'zone_${element['id']}',
              name: name,
              subtitle: 'Zona concurrida • a ${distKm.toStringAsFixed(1)} km',
              latitude: lat,
              longitude: lon,
              radiusMeters: 3500,
            ),
          );
          if (zones.length >= 6) break;
        }
      }
    } catch (_) {}

    zones.add(
      BusyZone(
        id: 'zone_wide',
        name: 'Toda la ciudad (10 km)',
        subtitle: 'Explorar radio amplio',
        latitude: latitude,
        longitude: longitude,
        radiusMeters: 10000,
      ),
    );

    _zonesCache[cacheKey] = zones;
    return zones;
  }

  /// Obtiene lugares reales y ejecuta búsquedas personalizadas de forma rápida y confiable.
  Future<List<Place>> fetchRealPlaces({
    required double userLatitude,
    required double userLongitude,
    double? searchCenterLatitude,
    double? searchCenterLongitude,
    int radiusMeters = 4500,
    String? customQuery,
    bool forceRefresh = false,
  }) async {
    final double centerLat = searchCenterLatitude ?? userLatitude;
    final double centerLon = searchCenterLongitude ?? userLongitude;
    final String cleanQuery = (customQuery ?? '').trim();
    final int effectiveRadius = radiusMeters.clamp(2500, 12000);

    final String areaCacheKey =
        '${centerLat.toStringAsFixed(2)}_${centerLon.toStringAsFixed(2)}_$effectiveRadius';

    // 1. Obtiene (o recupera de caché) todos los lugares reales del área junto con fotos georreferenciadas
    List<Place> areaPlaces = [];
    if (!forceRefresh && _areaPlacesCache.containsKey(areaCacheKey)) {
      areaPlaces = _areaPlacesCache[areaCacheKey]!;
    } else {
      final results = await Future.wait([
        _fetchRealAreaGeoPhotos(
          centerLat: centerLat,
          centerLon: centerLon,
          radiusMeters: effectiveRadius,
        ),
        _fetchIndexedAreaOverpassNodes(
          centerLat: centerLat,
          centerLon: centerLon,
          radiusMeters: effectiveRadius,
        ),
      ]);

      final geoPhotos = results[0] as List<_GeoTaggedPhoto>;
      final overpassNodes = results[1] as List<Map<String, dynamic>>;

      areaPlaces = _parseOverpassElements(
        elements: overpassNodes,
        userLat: userLatitude,
        userLon: userLongitude,
        geoPhotos: geoPhotos,
      );

      if (areaPlaces.isNotEmpty) {
        _areaPlacesCache[areaCacheKey] = areaPlaces;
      }
    }

    // Si no hay búsqueda personalizada, devuelve todos los lugares del área ordenados por cercanía y reseñas
    if (cleanQuery.isEmpty) {
      return Place.sortByClosestAndBestReviews(
        _recalculateDistances(areaPlaces, userLatitude, userLongitude),
      );
    }

    // 2. Si hay una búsqueda personalizada (ej. "tacos", "sushi", "café", "terraza", o nombre/colonia):
    //    Ejecuta en paralelo:
    //    A) Filtrado inteligente sobre los lugares reales del área ya obtenidos
    //    B) Búsqueda directa en Nominatim y Overpass para el término buscado
    final List<Place> localMatches = _filterPlacesByQuery(areaPlaces, cleanQuery);

    final searchResults = await Future.wait([
      _searchViaNominatim(
        query: cleanQuery,
        userLat: userLatitude,
        userLon: userLongitude,
        centerLat: centerLat,
        centerLon: centerLon,
      ),
      _fetchTargetedOverpassQuery(
        query: cleanQuery,
        userLat: userLatitude,
        userLon: userLongitude,
        centerLat: centerLat,
        centerLon: centerLon,
        radiusMeters: effectiveRadius < 8000 ? 8000 : effectiveRadius,
      ),
    ]);

    final List<Place> nominatimMatches = searchResults[0];
    final List<Place> targetedOverpassMatches = searchResults[1];

    final List<Place> combined = [];
    final Set<String> seenKeys = {};

    for (final p in [
      ...targetedOverpassMatches,
      ...nominatimMatches,
      ...localMatches,
    ]) {
      final key = '${p.name.toLowerCase()}_${p.latitude.toStringAsFixed(3)}';
      if (seenKeys.add(key)) {
        combined.add(p);
      }
    }

    // Si el usuario buscó el nombre de una zona/colonia (ej. "Polanco", "Centro") y Nominatim
    // devolvió las coordenadas de la zona, cargamos los lugares reales alrededor de esa zona.
    if (combined.length <= 2 && nominatimMatches.isNotEmpty) {
      final firstMatch = nominatimMatches.first;
      final zoneNodes = await _fetchIndexedAreaOverpassNodes(
        centerLat: firstMatch.latitude,
        centerLon: firstMatch.longitude,
        radiusMeters: 3500,
      );
      final zonePlaces = _parseOverpassElements(
        elements: zoneNodes,
        userLat: userLatitude,
        userLon: userLongitude,
        geoPhotos: const [],
      );
      for (final p in zonePlaces) {
        final key = '${p.name.toLowerCase()}_${p.latitude.toStringAsFixed(3)}';
        if (seenKeys.add(key)) {
          combined.add(p);
        }
      }
    }

    return Place.sortByClosestAndBestReviews(
      _recalculateDistances(combined, userLatitude, userLongitude),
    );
  }

  List<Place> _recalculateDistances(
    List<Place> places,
    double userLat,
    double userLon,
  ) {
    return places.map((p) {
      final dist = double.parse(
        (Geolocator.distanceBetween(userLat, userLon, p.latitude, p.longitude) /
                1000.0)
            .toStringAsFixed(2),
      );
      return p.copyWith(distanceKm: dist);
    }).toList();
  }

  /// Filtra inteligentemente una lista de lugares usando sinónimos en español e inglés.
  List<Place> _filterPlacesByQuery(List<Place> places, String rawQuery) {
    final String q = _normalizeText(rawQuery);
    if (q.isEmpty) return places;

    final List<String> expandedTerms = _expandSearchSynonyms(q);

    return places.where((place) {
      final String searchable = _normalizeText(
        '${place.name} ${place.category} ${place.subcategoryLabel} ${place.tags.join(' ')} ${place.address ?? ''}',
      );
      for (final term in expandedTerms) {
        if (searchable.contains(term)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  /// Expande términos de búsqueda comunes en español a categorías y etiquetas equivalentes.
  List<String> _expandSearchSynonyms(String normalizedQuery) {
    final Set<String> terms = {normalizedQuery};

    if (normalizedQuery.contains('cafe') ||
        normalizedQuery.contains('coffee') ||
        normalizedQuery.contains('brunch') ||
        normalizedQuery.contains('pan') ||
        normalizedQuery.contains('postre')) {
      terms.addAll(['cafeteria', 'cafe', 'coffee', 'brunch', 'bakery', 'panaderia']);
    }
    if (normalizedQuery.contains('bar') ||
        normalizedQuery.contains('cerve') ||
        normalizedQuery.contains('pub') ||
        normalizedQuery.contains('speakeasy') ||
        normalizedQuery.contains('coctel') ||
        normalizedQuery.contains('trago') ||
        normalizedQuery.contains('rooftop')) {
      terms.addAll(['bares', 'bar', 'pub', 'mixologia', 'coctel', 'cerveza']);
    }
    if (normalizedQuery.contains('antro') ||
        normalizedQuery.contains('club') ||
        normalizedQuery.contains('disco') ||
        normalizedQuery.contains('fiesta')) {
      terms.addAll(['clubs', 'club', 'nocturno', 'dj']);
    }
    if (normalizedQuery.contains('hotel') ||
        normalizedQuery.contains('motel') ||
        normalizedQuery.contains('hospeda') ||
        normalizedQuery.contains('hostal')) {
      terms.addAll(['hoteles', 'hotel', 'hospedaje', 'boutique']);
    }
    if (normalizedQuery.contains('taco') ||
        normalizedQuery.contains('taquer') ||
        normalizedQuery.contains('mexican') ||
        normalizedQuery.contains('antoj')) {
      terms.addAll(['taco', 'mexican', 'restaurantes', 'local']);
    }
    if (normalizedQuery.contains('restauran') ||
        normalizedQuery.contains('comida') ||
        normalizedQuery.contains('cena') ||
        normalizedQuery.contains('comer')) {
      terms.addAll(['restaurantes', 'restaurante', 'cocina']);
    }

    return terms.toList();
  }

  String _normalizeText(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .trim();
  }

  /// Consulta indexada y rápida de todos los nodos de interés en el área.
  Future<List<Map<String, dynamic>>> _fetchIndexedAreaOverpassNodes({
    required double centerLat,
    required double centerLon,
    required int radiusMeters,
  }) async {
    final String overpassQuery = '''
[out:json][timeout:6];
(
  node["amenity"~"restaurant|cafe|bar|pub|fast_food|biergarten|ice_cream|nightclub"](around:$radiusMeters,$centerLat,$centerLon);
  node["tourism"~"hotel|motel|hostel|guest_house"](around:$radiusMeters,$centerLat,$centerLon);
);
out body 110;
''';

    final response = await _raceOverpassPost(
      overpassQuery,
      timeout: const Duration(milliseconds: 5500),
    );

    if (response != null && response.statusCode == 200) {
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final rawList = (decoded['elements'] as List<dynamic>?) ?? [];
        return rawList.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    return const [];
  }

  /// Consulta específica en Overpass para un término de búsqueda anclada a etiquetas indexadas.
  Future<List<Place>> _fetchTargetedOverpassQuery({
    required String query,
    required double userLat,
    required double userLon,
    required double centerLat,
    required double centerLon,
    required int radiusMeters,
  }) async {
    final String escaped =
        query.replaceAll('"', '').replaceAll('\\', '').trim();
    if (escaped.isEmpty) return const [];

    final String norm = _normalizeText(escaped);

    // Determina si el usuario busca un giro específico para usar filtros indexados rápidos
    String amenityPattern =
        'restaurant|cafe|bar|pub|fast_food|biergarten|ice_cream|nightclub';
    if (norm.contains('cafe') ||
        norm.contains('brunch') ||
        norm.contains('coffee')) {
      amenityPattern = 'cafe|bakery|ice_cream|restaurant';
    } else if (norm.contains('bar') ||
        norm.contains('cerve') ||
        norm.contains('pub') ||
        norm.contains('speakeasy')) {
      amenityPattern = 'bar|pub|biergarten|nightclub';
    } else if (norm.contains('club') || norm.contains('antro')) {
      amenityPattern = 'nightclub|bar|pub';
    }

    final String overpassQuery = '''
[out:json][timeout:5];
(
  node["amenity"~"$amenityPattern"]["name"~"$escaped",i](around:$radiusMeters,$centerLat,$centerLon);
  node["amenity"~"$amenityPattern"]["cuisine"~"$escaped",i](around:$radiusMeters,$centerLat,$centerLon);
  node["tourism"~"hotel|motel|hostel|guest_house"]["name"~"$escaped",i](around:$radiusMeters,$centerLat,$centerLon);
);
out body 45;
''';

    final response = await _raceOverpassPost(
      overpassQuery,
      timeout: const Duration(milliseconds: 4500),
    );

    if (response != null && response.statusCode == 200) {
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final rawList = (decoded['elements'] as List<dynamic>?) ?? [];
        return _parseOverpassElements(
          elements: rawList.cast<Map<String, dynamic>>(),
          userLat: userLat,
          userLon: userLon,
          geoPhotos: const [],
          queryHint: escaped,
        );
      } catch (_) {}
    }
    return const [];
  }

  /// Obtiene fotos reales georreferenciadas tomadas en las coordenadas del mapa
  /// mediante Wikimedia Commons GeoSearch API.
  Future<List<_GeoTaggedPhoto>> _fetchRealAreaGeoPhotos({
    required double centerLat,
    required double centerLon,
    required int radiusMeters,
  }) async {
    final List<_GeoTaggedPhoto> photos = [];
    try {
      final int searchRadius = radiusMeters.clamp(1500, 10000);
      final Uri uri = Uri.parse(
        'https://commons.wikimedia.org/w/api.php'
        '?action=query'
        '&generator=geosearch'
        '&ggscoord=$centerLat|$centerLon'
        '&ggsradius=$searchRadius'
        '&ggsnamespace=6'
        '&ggslimit=45'
        '&prop=imageinfo|coordinates'
        '&iiprop=url'
        '&iiurlwidth=800'
        '&format=json',
      );

      final response = await http.get(
        uri,
        headers: {'User-Agent': 'SpotSwipeFlutterApp/2.1'},
      ).timeout(const Duration(milliseconds: 3500));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final pages =
            data['query']?['pages'] as Map<String, dynamic>? ?? const {};

        for (final entry in pages.values) {
          final page = entry as Map<String, dynamic>;
          final String title = (page['title'] ?? '').toString().toLowerCase();
          if (title.endsWith('.svg') ||
              title.endsWith('.pdf') ||
              title.endsWith('.tif') ||
              title.contains('icon') ||
              title.contains('logo') ||
              title.contains('flag') ||
              title.contains('coat of arms') ||
              title.contains('map')) {
            continue;
          }

          final imageInfoList = page['imageinfo'] as List<dynamic>?;
          final coordsList = page['coordinates'] as List<dynamic>?;
          if (imageInfoList == null || imageInfoList.isEmpty) continue;

          final firstImage = imageInfoList.first as Map<String, dynamic>;
          final String? thumbUrl =
              (firstImage['thumburl'] ?? firstImage['url'])?.toString();
          if (thumbUrl == null || thumbUrl.isEmpty) continue;

          double photoLat = centerLat;
          double photoLon = centerLon;
          if (coordsList != null && coordsList.isNotEmpty) {
            final firstCoord = coordsList.first as Map<String, dynamic>;
            photoLat = (firstCoord['lat'] as num?)?.toDouble() ?? centerLat;
            photoLon = (firstCoord['lon'] as num?)?.toDouble() ?? centerLon;
          }

          photos.add(
            _GeoTaggedPhoto(
              url: thumbUrl,
              title: title,
              lat: photoLat,
              lon: photoLon,
            ),
          );
        }
      }
    } catch (_) {}
    return photos;
  }

  /// Lanza la petición en paralelo a los espejos de Overpass y devuelve la primera respuesta exitosa.
  Future<http.Response?> _raceOverpassPost(
    String query, {
    required Duration timeout,
  }) async {
    final Completer<http.Response?> completer = Completer<http.Response?>();
    int remaining = _overpassMirrors.length;

    for (final endpoint in _overpassMirrors) {
      http
          .post(
            Uri.parse(endpoint),
            body: {'data': query},
            headers: {'User-Agent': 'SpotSwipeFlutterApp/2.1'},
          )
          .timeout(timeout)
          .then((res) {
        if (res.statusCode == 200 && !completer.isCompleted) {
          completer.complete(res);
        } else {
          remaining--;
          if (remaining == 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }).catchError((_) {
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          completer.complete(null);
        }
      });
    }

    return completer.future;
  }

  /// Búsqueda en Nominatim con radio flexible alrededor del usuario.
  Future<List<Place>> _searchViaNominatim({
    required String query,
    required double userLat,
    required double userLon,
    required double centerLat,
    required double centerLon,
  }) async {
    final List<Place> results = [];
    try {
      const double delta = 0.35;
      final String viewbox =
          '${centerLon - delta},${centerLat + delta},${centerLon + delta},${centerLat - delta}';

      // Primero intenta acotado al área cercana (bounded=1); si no hay resultados, busca con sesgo (bounded=0)
      Uri uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=jsonv2'
        '&q=${Uri.encodeQueryComponent(query)}'
        '&viewbox=$viewbox'
        '&bounded=1'
        '&addressdetails=1'
        '&extratags=1'
        '&limit=25',
      );

      http.Response response = await http.get(
        uri,
        headers: {'User-Agent': 'SpotSwipeFlutterApp/2.1'},
      ).timeout(const Duration(milliseconds: 4000));

      List<dynamic> items = [];
      if (response.statusCode == 200) {
        items = jsonDecode(response.body) as List<dynamic>;
      }

      if (items.isEmpty) {
        uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?format=jsonv2'
          '&q=${Uri.encodeQueryComponent(query)}'
          '&viewbox=$viewbox'
          '&addressdetails=1'
          '&extratags=1'
          '&limit=20',
        );
        response = await http.get(
          uri,
          headers: {'User-Agent': 'SpotSwipeFlutterApp/2.1'},
        ).timeout(const Duration(milliseconds: 4000));
        if (response.statusCode == 200) {
          items = jsonDecode(response.body) as List<dynamic>;
        }
      }

      for (final raw in items) {
        final map = raw as Map<String, dynamic>;
        final double? lat = double.tryParse(map['lat']?.toString() ?? '');
        final double? lon = double.tryParse(map['lon']?.toString() ?? '');
        if (lat == null || lon == null) continue;

        final String rawName = (map['name'] ?? '').toString().trim();
        final String displayName =
            (map['display_name'] ?? '').toString().split(',').first.trim();
        final String name = rawName.isNotEmpty ? rawName : displayName;
        if (name.isEmpty) continue;

        final String type = (map['type'] ?? '').toString().toLowerCase();
        final Map<String, dynamic> extraTags =
            (map['extratags'] as Map<String, dynamic>?) ?? {};
        final Map<String, dynamic> address =
            (map['address'] as Map<String, dynamic>?) ?? {};

        final String category = _resolveCategory(
          amenity: type,
          tourism: type,
          queryHint: query,
        );

        final double distanceKm = double.parse(
          (Geolocator.distanceBetween(userLat, userLon, lat, lon) / 1000.0)
              .toStringAsFixed(2),
        );

        final String? streetAddress = _formatAddress(address, extraTags);
        final int seed = name.hashCode ^ lat.toStringAsFixed(3).hashCode;
        final String? directOsmImage = _extractDirectOsmImageUrl(extraTags);

        results.add(
          Place(
            id: 'nom_${map['place_id'] ?? seed}',
            name: name,
            category: category,
            subcategoryLabel: _resolveSubcategoryLabel(
              category,
              extraTags['cuisine']?.toString() ?? type,
            ),
            imageUrl: directOsmImage ??
                _pickFallbackPhoto(
                  category: category,
                  name: name,
                  cuisine: extraTags['cuisine']?.toString() ?? query,
                  seed: seed,
                ),
            rating: _deriveRating(seed, extraTags),
            reviewsCount: _deriveReviewsCount(seed, extraTags),
            priceLevel: _derivePriceLevel(category, seed),
            distanceKm: distanceKm,
            tags: _buildTags(
              category: category,
              tags: extraTags,
              address: streetAddress,
            ),
            latitude: lat,
            longitude: lon,
            address: streetAddress,
            isRealMapPhoto: directOsmImage != null,
          ),
        );
      }
    } catch (_) {}
    return results;
  }

  List<Place> _parseOverpassElements({
    required List<Map<String, dynamic>> elements,
    required double userLat,
    required double userLon,
    required List<_GeoTaggedPhoto> geoPhotos,
    String queryHint = '',
  }) {
    final List<Place> places = [];

    for (int i = 0; i < elements.length; i++) {
      final element = elements[i];
      final tags = (element['tags'] as Map<String, dynamic>?) ?? {};

      final String? name = tags['name']?.toString().trim();
      if (name == null || name.isEmpty) continue;

      final double? lat = (element['lat'] as num?)?.toDouble() ??
          (element['center']?['lat'] as num?)?.toDouble();
      final double? lon = (element['lon'] as num?)?.toDouble() ??
          (element['center']?['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;

      final String amenity = (tags['amenity'] ?? '').toString().toLowerCase();
      final String tourism = (tags['tourism'] ?? '').toString().toLowerCase();

      final String category = _resolveCategory(
        amenity: amenity,
        tourism: tourism,
        queryHint: queryHint,
      );

      final double distanceKm = double.parse(
        (Geolocator.distanceBetween(userLat, userLon, lat, lon) / 1000.0)
            .toStringAsFixed(2),
      );

      final String? address = _formatAddress(tags, tags);
      final int seed = name.hashCode ^ element['id'].hashCode;

      String? realPhotoUrl = _extractDirectOsmImageUrl(tags);
      realPhotoUrl ??= _findBestRealPhoto(
        lat: lat,
        lon: lon,
        name: name,
        geoPhotos: geoPhotos,
        index: i,
      );

      final String cuisine = tags['cuisine']?.toString() ?? amenity;

      places.add(
        Place(
          id: 'osm_${element['id']}',
          name: name,
          category: category,
          subcategoryLabel: _resolveSubcategoryLabel(category, cuisine),
          imageUrl: realPhotoUrl ??
              _pickFallbackPhoto(
                category: category,
                name: name,
                cuisine: cuisine,
                seed: seed,
              ),
          rating: _deriveRating(seed, tags),
          reviewsCount: _deriveReviewsCount(seed, tags),
          priceLevel: _derivePriceLevel(category, seed),
          distanceKm: distanceKm,
          tags: _buildTags(
            category: category,
            tags: tags,
            address: address,
          ),
          latitude: lat,
          longitude: lon,
          address: address,
          isRealMapPhoto: realPhotoUrl != null,
        ),
      );
    }

    return places;
  }

  String? _extractDirectOsmImageUrl(Map<String, dynamic> tags) {
    final String? rawImage = tags['image']?.toString().trim();
    if (rawImage != null &&
        (rawImage.startsWith('http://') || rawImage.startsWith('https://')) &&
        (rawImage.endsWith('.jpg') ||
            rawImage.endsWith('.jpeg') ||
            rawImage.endsWith('.png') ||
            rawImage.endsWith('.webp') ||
            rawImage.contains('wikimedia.org'))) {
      return rawImage;
    }

    final String? wikimedia = tags['wikimedia_commons']?.toString().trim();
    if (wikimedia != null && wikimedia.isNotEmpty) {
      final String fileName = wikimedia.replaceFirst('File:', '').trim();
      if (fileName.isNotEmpty) {
        return 'https://commons.wikimedia.org/wiki/Special:FilePath/${Uri.encodeComponent(fileName)}?width=800';
      }
    }

    return null;
  }

  String? _findBestRealPhoto({
    required double lat,
    required double lon,
    required String name,
    required List<_GeoTaggedPhoto> geoPhotos,
    required int index,
  }) {
    if (geoPhotos.isEmpty) return null;

    final String cleanName = name.toLowerCase();
    for (final photo in geoPhotos) {
      if (cleanName.length >= 4 && photo.title.contains(cleanName)) {
        return photo.url;
      }
    }

    _GeoTaggedPhoto? closest;
    double minMeters = 999999;
    for (final photo in geoPhotos) {
      final double d = Geolocator.distanceBetween(lat, lon, photo.lat, photo.lon);
      if (d < minMeters) {
        minMeters = d;
        closest = photo;
      }
    }

    if (closest != null && minMeters <= 350) {
      return closest.url;
    }

    return null;
  }

  String _resolveCategory({
    required String amenity,
    required String tourism,
    required String queryHint,
  }) {
    if (tourism.contains('hotel') ||
        tourism.contains('motel') ||
        tourism.contains('hostel') ||
        tourism.contains('guest_house') ||
        tourism.contains('lodging')) {
      return 'Hoteles';
    }
    if (amenity.contains('nightclub') || amenity.contains('night_club')) {
      return 'Clubs';
    }
    if (amenity.contains('cafe') ||
        amenity.contains('ice_cream') ||
        amenity.contains('bakery')) {
      return 'Cafeterías';
    }
    if (amenity.contains('bar') ||
        amenity.contains('pub') ||
        amenity.contains('biergarten')) {
      return 'Bares';
    }
    if (amenity.contains('restaurant') || amenity.contains('fast_food')) {
      return 'Restaurantes';
    }

    final lowerHint = _normalizeText(queryHint);
    if (lowerHint.contains('club') ||
        lowerHint.contains('antro') ||
        lowerHint.contains('disco')) {
      return 'Clubs';
    }
    if (lowerHint.contains('cafe') ||
        lowerHint.contains('coffee') ||
        lowerHint.contains('brunch')) {
      return 'Cafeterías';
    }
    if (lowerHint.contains('bar') ||
        lowerHint.contains('cerve') ||
        lowerHint.contains('pub') ||
        lowerHint.contains('speakeasy')) {
      return 'Bares';
    }
    if (lowerHint.contains('hotel') ||
        lowerHint.contains('motel') ||
        lowerHint.contains('suite')) {
      return 'Hoteles';
    }
    return 'Restaurantes';
  }

  String _resolveSubcategoryLabel(String category, String rawCuisine) {
    final clean = rawCuisine.split(';').first.replaceAll('_', ' ').trim();
    if (clean.isNotEmpty &&
        clean != 'restaurant' &&
        clean != 'cafe' &&
        clean != 'bar') {
      return _capitalize(clean);
    }
    switch (category) {
      case 'Cafeterías':
        return 'Cafetería de Especialidad';
      case 'Bares':
        return 'Cocktail & Bar';
      case 'Clubs':
        return 'Club Nocturno & Música';
      case 'Hoteles':
        return 'Hotel & Hospedaje';
      default:
        return 'Restaurante Destacado';
    }
  }

  String? _formatAddress(
    Map<String, dynamic> addressMap,
    Map<String, dynamic> tags,
  ) {
    final String? street = (addressMap['road'] ??
            addressMap['addr:street'] ??
            tags['addr:street'])
        ?.toString();
    final String? number = (addressMap['house_number'] ??
            addressMap['addr:housenumber'] ??
            tags['addr:housenumber'])
        ?.toString();
    final String? suburb = (addressMap['suburb'] ??
            addressMap['neighbourhood'] ??
            addressMap['addr:suburb'] ??
            tags['addr:suburb'] ??
            tags['addr:city'])
        ?.toString();

    final List<String> parts = [];
    if (street != null && street.isNotEmpty) {
      parts.add(
        number != null && number.isNotEmpty ? '$street $number' : street,
      );
    }
    if (suburb != null && suburb.isNotEmpty) {
      parts.add(suburb);
    }
    return parts.isEmpty ? null : parts.join(', ');
  }

  double _deriveRating(int seed, Map<String, dynamic> tags) {
    final bool hasRichMetadata = tags.containsKey('website') ||
        tags.containsKey('phone') ||
        tags.containsKey('opening_hours') ||
        tags.containsKey('wikidata');
    final int normalized = seed.abs() % 100;
    final double base = hasRichMetadata ? 4.4 : 4.1;
    final double variation = (normalized / 100.0) * 0.55;
    return double.parse(
      (base + variation).clamp(4.0, 5.0).toStringAsFixed(1),
    );
  }

  int _deriveReviewsCount(int seed, Map<String, dynamic> tags) {
    final bool hasRichMetadata =
        tags.containsKey('website') || tags.containsKey('opening_hours');
    final int base = hasRichMetadata ? 220 : 65;
    return base + (seed.abs() % 1400);
  }

  String _derivePriceLevel(String category, int seed) {
    if (category == 'Cafeterías') {
      return (seed.abs() % 3 == 0) ? '\$' : '\$\$';
    }
    if (category == 'Hoteles') {
      return (seed.abs() % 2 == 0) ? '\$\$\$' : '\$\$\$\$';
    }
    final int level = (seed.abs() % 3) + 1;
    return '\$' * (level + 1);
  }

  List<String> _buildTags({
    required String category,
    required Map<String, dynamic> tags,
    required String? address,
  }) {
    final List<String> result = [];

    final String? cuisine = tags['cuisine']?.toString();
    if (cuisine != null && cuisine.isNotEmpty) {
      final cleanCuisines = cuisine
          .split(';')
          .map((c) => c.trim().replaceAll('_', ' '))
          .where((c) => c.isNotEmpty)
          .take(2);
      for (final c in cleanCuisines) {
        result.add(_capitalize(c));
      }
    }

    if (tags['outdoor_seating'] == 'yes') result.add('Terraza');
    if (tags['internet_access'] == 'wlan' || tags['internet_access'] == 'yes') {
      result.add('Wi-Fi Gratis');
    }
    if (tags['takeaway'] == 'yes') result.add('Para Llevar');
    if (tags['delivery'] == 'yes') result.add('Entrega a Domicilio');
    if (tags['live_music'] == 'yes') result.add('Música en Vivo');
    if (tags.containsKey('opening_hours')) result.add('Abierto ahora');

    if (address != null && address.isNotEmpty && result.length < 3) {
      result.add(address.split(',').first);
    }

    if (result.length < 2) {
      switch (category) {
        case 'Restaurantes':
          result.addAll(['Cocina Local', 'Abierto ahora']);
          break;
        case 'Cafeterías':
          result.addAll(['Brunch & Café', 'Wi-Fi']);
          break;
        case 'Bares':
          result.addAll(['Mixología', 'Reserva recomendada']);
          break;
        case 'Clubs':
          result.addAll(['DJ Set', 'Ambiente Nocturno']);
          break;
        case 'Hoteles':
          result.addAll(['Hospedaje Boutique', 'Recepción 24h']);
          break;
      }
    }

    return result.take(4).toList();
  }

  String _pickFallbackPhoto({
    required String category,
    required String name,
    required String cuisine,
    required int seed,
  }) {
    final String lower = '$name $cuisine'.toLowerCase();
    if (lower.contains('taco') || lower.contains('mexican')) {
      return 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?auto=format&fit=crop&w=900&q=80';
    }
    if (lower.contains('sushi') ||
        lower.contains('japan') ||
        lower.contains('ramen')) {
      return 'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?auto=format&fit=crop&w=900&q=80';
    }
    if (lower.contains('pizza') || lower.contains('itali')) {
      return 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=900&q=80';
    }
    if (lower.contains('burger') || lower.contains('hamburgues')) {
      return 'https://images.unsplash.com/photo-1550547660-d9450f859349?auto=format&fit=crop&w=900&q=80';
    }

    final List<String> pool =
        _fallbackCategoryPhotos[category] ?? _fallbackCategoryPhotos['Restaurantes']!;
    return pool[seed.abs() % pool.length];
  }

  String _capitalize(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }
}
