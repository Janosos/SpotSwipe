import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

import '../models/place.dart';
import '../services/navigation_service.dart';
import '../services/places_service.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  // ===========================================================================
  // PALETA DE COLORES BASADA EN EL DISEÑO EDITORIAL (HTML / TAILWIND)
  // ===========================================================================
  static const Color _surface = Color(0xFFF9F9FF);
  static const Color _surfaceLowest = Color(0xFFFFFFFF);
  static const Color _surfaceLow = Color(0xFFF1F3FD);
  static const Color _surfaceContainer = Color(0xFFEBEEF7);
  static const Color _surfaceHigh = Color(0xFFE5E8F2);
  static const Color _surfaceVariant = Color(0xFFDFE2EC);

  static const Color _onSurface = Color(0xFF181C23);
  static const Color _onSurfaceVariant = Color(0xFF5A403F);

  static const Color _primary = Color(0xFFB52330);
  static const Color _primaryContainer = Color(0xFFFF5A5F);
  static const Color _primaryFixed = Color(0xFFFFDAD8);
  static const Color _onPrimaryFixed = Color(0xFF410007);

  static const Color _secondary = Color(0xFF835500);
  static const Color _secondaryContainer = Color(0xFFFEAE2C);
  static const Color _secondaryFixed = Color(0xFFFFDDB4);

  static const Color _tertiary = Color(0xFF436465);
  static const Color _outline = Color(0xFF8E706F);
  static const Color _outlineVariant = Color(0xFFE2BEBC);
  static const Color _emeraldNav = Color(0xFF10B981);

  static const List<String> _swipeCategories = [
    'Todos',
    'Restaurantes',
    'Cafeterías',
    'Bares',
    'Clubs',
    'Hoteles',
  ];

  static const List<String> _distanceLabels = [
    '< 1 km',
    '< 3 km',
    '< 5 km',
    'Todo',
  ];

  static const List<int> _distanceMetersValues = [
    1500,
    3500,
    5500,
    12000,
  ];

  final NavigationService _navigationService = const NavigationService();
  final PlacesService _placesService = PlacesService();
  final TextEditingController _searchController = TextEditingController();
  late CardSwiperController _swiperController;

  // Pestaña activa: 0 = Explorar, 1 = Swipe, 2 = Guardados, 3 = Configuración
  int _currentTabIndex = 0;

  // Estado de carga y datos
  bool _isLoadingPlaces = false;
  bool _isDeckFinished = false;
  bool _hasLocationPermission = false;

  // Ubicación actual del usuario
  double _userLatitude = 19.4194;
  double _userLongitude = -99.1626;
  String _currentAreaName = 'Buscando GPS...';

  // Filtro de distancia en el inicio (< 1 km, < 3 km, < 5 km, Todo)
  int _distanceStepIndex = 1; // Por defecto '< 3 km'

  // Parámetros de búsqueda activa
  String _activeSearchTitle = 'Cerca de ti';
  String? _activeCustomQuery;
  String _liveFilterText = '';
  double? _activeSearchLat;
  double? _activeSearchLon;

  // Preferencias
  double _farThresholdKm = Place.defaultFarThresholdKm;

  // Estado visual de sesión (solo demostrativo)
  bool _isDemoLoggedIn = false;
  String _demoUserName = ' Invitado';
  String _demoUserEmail = 'usuario@spotswipe.app';

  List<Place> _allPlaces = Place.sortByClosestAndBestReviews(Place.mockPlaces);
  List<BusyZone> _busyZones = const [];
  final Set<String> _savedPlaceIds = {};
  String _selectedCategory = 'Todos';
  int _deckSessionKey = 0;

  int get _activeRadiusMeters => _distanceMetersValues[_distanceStepIndex];

  List<Place> get _filteredPlaces {
    Iterable<Place> list = _allPlaces;

    // 1. Filtra por categoría seleccionada
    if (_selectedCategory != 'Todos') {
      list = list.where((p) => p.category == _selectedCategory);
    }

    // 2. Si el usuario está escribiendo en la barra de búsqueda de Explorar, filtra en vivo
    final String queryToFilter = _liveFilterText.trim();
    if (queryToFilter.isNotEmpty && _activeCustomQuery == null) {
      final String q = queryToFilter.toLowerCase();
      final matches = list.where((p) {
        final content =
            '${p.name} ${p.category} ${p.subcategoryLabel} ${p.tags.join(' ')} ${p.address ?? ''}'
                .toLowerCase();
        return content.contains(q);
      }).toList();
      if (matches.isNotEmpty) {
        list = matches;
      }
    }

    // 3. Si NO hay una búsqueda personalizada activa, aplica el límite del botón de distancia
    if (_activeCustomQuery == null || _activeCustomQuery!.trim().isEmpty) {
      final double maxKm = _distanceStepIndex == 0
          ? 1.5
          : _distanceStepIndex == 1
              ? 3.8
              : _distanceStepIndex == 2
                  ? 6.0
                  : 999.0;
      final withinDistance = list.where((p) => p.distanceKm <= maxKm).toList();
      if (withinDistance.isNotEmpty) {
        list = withinDistance;
      }
    }

    return Place.sortByClosestAndBestReviews(list.toList());
  }

  List<Place> get _savedPlaces =>
      _allPlaces.where((p) => _savedPlaceIds.contains(p.id)).toList();

  @override
  void initState() {
    super.initState();
    _swiperController = CardSwiperController();
    _initializeFastLocationAndPlaces();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _swiperController.dispose();
    super.dispose();
  }

  /// Inicializa GPS rápidamente y precarga lugares reales.
  Future<void> _initializeFastLocationAndPlaces({
    bool forceRefresh = false,
  }) async {
    if (!mounted) return;
    setState(() {
      _isLoadingPlaces = true;
    });

    final position = await _navigationService.getCurrentPosition(
      preferFastKnownPosition: !forceRefresh,
    );

    if (!mounted) return;

    if (position != null) {
      _hasLocationPermission = true;
      _userLatitude = position.latitude;
      _userLongitude = position.longitude;
    }

    final results = await Future.wait([
      _placesService.fetchRealPlaces(
        userLatitude: _userLatitude,
        userLongitude: _userLongitude,
        searchCenterLatitude: _activeSearchLat ?? _userLatitude,
        searchCenterLongitude: _activeSearchLon ?? _userLongitude,
        radiusMeters: _activeRadiusMeters,
        customQuery: _activeCustomQuery,
        forceRefresh: forceRefresh,
      ),
      _placesService.fetchCurrentAreaLabel(
        latitude: _userLatitude,
        longitude: _userLongitude,
      ),
      _placesService.fetchNearbyBusyZones(
        latitude: _userLatitude,
        longitude: _userLongitude,
      ),
    ]);

    if (!mounted) return;

    final fetchedPlaces = results[0] as List<Place>;
    final areaLabel = results[1] as String;
    final zones = results[2] as List<BusyZone>;

    setState(() {
      _currentAreaName = areaLabel;
      _busyZones = zones;
      if (fetchedPlaces.isNotEmpty) {
        _allPlaces = fetchedPlaces;
      } else {
        _allPlaces = Place.sortByClosestAndBestReviews(
          Place.mockPlaces.map((place) {
            final dist = _navigationService.calculateDistanceKm(
              startLatitude: _userLatitude,
              startLongitude: _userLongitude,
              endLatitude: place.latitude,
              endLongitude: place.longitude,
            );
            return place.copyWith(distanceKm: dist);
          }).toList(),
        );
      }
      _isLoadingPlaces = false;
      _isDeckFinished = false;
      _deckSessionKey++;
      _swiperController.dispose();
      _swiperController = CardSwiperController();
    });
  }

  /// Ejecuta una búsqueda real y abre la vista de Swipe con los resultados.
  Future<void> _startSearchAndOpenSwipe({
    required String title,
    String? customQuery,
    String category = 'Todos',
    double? centerLat,
    double? centerLon,
    bool forceRefresh = false,
  }) async {
    FocusScope.of(context).unfocus();
    final String? cleanCustomQuery =
        (customQuery != null && customQuery.trim().isNotEmpty)
            ? customQuery.trim()
            : null;

    setState(() {
      _currentTabIndex = 1; // Abre pestaña Swipe
      _selectedCategory = category;
      _activeSearchTitle = title;
      _activeCustomQuery = cleanCustomQuery;
      _liveFilterText = cleanCustomQuery ?? '';
      _activeSearchLat = centerLat;
      _activeSearchLon = centerLon;
      _isLoadingPlaces = true;
      _isDeckFinished = false;
    });

    final fetched = await _placesService.fetchRealPlaces(
      userLatitude: _userLatitude,
      userLongitude: _userLongitude,
      searchCenterLatitude: centerLat ?? _userLatitude,
      searchCenterLongitude: centerLon ?? _userLongitude,
      radiusMeters: cleanCustomQuery != null ? 9000 : _activeRadiusMeters,
      customQuery: cleanCustomQuery,
      forceRefresh: forceRefresh,
    );

    if (!mounted) return;

    setState(() {
      if (fetched.isNotEmpty) {
        _allPlaces = fetched;
      } else if (cleanCustomQuery != null) {
        // Si no hubo coincidencias externas en la red, filtra sobre los lugares conocidos
        final q = cleanCustomQuery.toLowerCase();
        final fallbackFiltered = _allPlaces.where((p) {
          final text =
              '${p.name} ${p.category} ${p.subcategoryLabel} ${p.tags.join(' ')} ${p.address ?? ''}'
                  .toLowerCase();
          return text.contains(q);
        }).toList();
        if (fallbackFiltered.isNotEmpty) {
          _allPlaces = Place.sortByClosestAndBestReviews(fallbackFiltered);
        }
      }
      _isLoadingPlaces = false;
      _isDeckFinished = false;
      _deckSessionKey++;
      _swiperController.dispose();
      _swiperController = CardSwiperController();
    });
  }

  /// Limpia la búsqueda personalizada activa y restaura todos los lugares cercanos.
  Future<void> _clearCustomSearch() async {
    _searchController.clear();
    setState(() {
      _activeCustomQuery = null;
      _liveFilterText = '';
      _activeSearchTitle = 'Cerca de ti';
      _selectedCategory = 'Todos';
    });
    await _initializeFastLocationAndPlaces(forceRefresh: false);
  }

  /// Reinicia la búsqueda actual desde cero (botón central de reinicio).
  Future<void> _resetCurrentSearch() async {
    await _startSearchAndOpenSwipe(
      title: _activeSearchTitle,
      customQuery: _activeCustomQuery,
      category: 'Todos',
      centerLat: _activeSearchLat,
      centerLon: _activeSearchLon,
      forceRefresh: true,
    );
  }

  /// Alterna el filtro de distancia (< 1 km, < 3 km, < 5 km, Todo).
  void _cycleDistanceFilter() {
    setState(() {
      _distanceStepIndex = (_distanceStepIndex + 1) % _distanceLabels.length;
      _isDeckFinished = false;
      _deckSessionKey++;
      _swiperController.dispose();
      _swiperController = CardSwiperController();
    });
    _initializeFastLocationAndPlaces();
  }

  /// Guarda o quita un lugar de la lista de favoritos.
  void _toggleSavedPlace(Place place) {
    setState(() {
      if (_savedPlaceIds.contains(place.id)) {
        _savedPlaceIds.remove(place.id);
      } else {
        _savedPlaceIds.add(place.id);
      }
    });
  }

  /// Callback al deslizar una tarjeta en el mazo.
  bool _handleSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    final places = _filteredPlaces;
    if (previousIndex >= 0 && previousIndex < places.length) {
      final swipedPlace = places[previousIndex];
      if (direction == CardSwiperDirection.right) {
        _savedPlaceIds.add(swipedPlace.id);
        _triggerNavigationForPlace(swipedPlace);
      }
    }
    return true;
  }

  /// Lanza la ruta paso a paso en la app nativa de mapas.
  Future<void> _triggerNavigationForPlace(Place place) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _onSurface,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _emeraldNav.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.navigation_rounded,
                color: _emeraldNav,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¡Ruta hacia ${place.name}!',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const Text(
                    'Abriendo navegación paso a paso...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final launched = await _navigationService.launchTurnByTurnNavigation(
      latitude: place.latitude,
      longitude: place.longitude,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _primary,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'No fue posible abrir la aplicación de mapas para ${place.name}.',
          ),
        ),
      );
    }
  }

  // ===========================================================================
  // MÓDULO DE INICIAR SESIÓN GENÉRICO (SOLO VISUAL)
  // ===========================================================================
  void _openAccountLoginModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return _GenericLoginModalSheet(
          isLoggedIn: _isDemoLoggedIn,
          userName: _demoUserName,
          userEmail: _demoUserEmail,
          onLoginSuccess: (name, email) {
            setState(() {
              _isDemoLoggedIn = true;
              _demoUserName = name;
              _demoUserEmail = email;
            });
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: _onSurface,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                content: Text('Bienvenido, $name'),
              ),
            );
          },
          onLogout: () {
            setState(() {
              _isDemoLoggedIn = false;
            });
            Navigator.pop(context);
          },
        );
      },
    );
  }

  /// Selector rápido de Zonas Concurridas al tocar la píldora de GPS en el Header.
  void _showZonesBottomSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surfaceLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: _primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Ubicación y Zonas Concurridas',
                        style: TextStyle(
                          color: _onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _clearCustomSearch();
                        _initializeFastLocationAndPlaces(forceRefresh: true);
                      },
                      icon: const Icon(Icons.my_location_rounded, size: 16),
                      label: const Text('Mi GPS'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_busyZones.isEmpty)
                  ListTile(
                    leading: const Icon(Icons.near_me_rounded, color: _primary),
                    title: Text(_currentAreaName),
                    subtitle: const Text('Usar mi ubicación actual'),
                    onTap: () {
                      Navigator.pop(context);
                      _initializeFastLocationAndPlaces(forceRefresh: true);
                    },
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _busyZones.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final zone = _busyZones[index];
                        return InkWell(
                          onTap: () {
                            Navigator.pop(context);
                            setState(() {
                              _currentAreaName = zone.name;
                            });
                            _startSearchAndOpenSwipe(
                              title: zone.name,
                              centerLat: zone.latitude,
                              centerLon: zone.longitude,
                              forceRefresh: true,
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: _surfaceLow,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.place_rounded,
                                  color: _primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        zone.name,
                                        style: const TextStyle(
                                          color: _onSurface,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        zone.subtitle,
                                        style: const TextStyle(
                                          color: _onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: _outline,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopHeader(),
                Expanded(
                  child: IndexedStack(
                    index: _currentTabIndex,
                    children: [
                      _buildExploreHomeTab(),
                      _buildSwipeTab(),
                      _buildSavedTab(),
                      _buildSettingsTab(),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildFloatingBottomNav(),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // HEADER SUPERIOR: SOLO GPS (IZQUIERDA) + ICONO DE CUENTA (DERECHA)
  // ===========================================================================
  Widget _buildTopHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.94),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Izquierda: Únicamente Píldora de Ubicación GPS (sin icono de mapas extra)
          Flexible(
            child: InkWell(
              onTap: _showZonesBottomSheet,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _surfaceLow,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _hasLocationPermission
                          ? Icons.location_on_rounded
                          : Icons.location_searching_rounded,
                      color: _primary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _currentAreaName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.expand_more_rounded,
                      color: _onSurfaceVariant,
                      size: 17,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Derecha: Icono de Cuenta (abre el módulo de Iniciar Sesión genérico visual)
          IconButton(
            onPressed: _openAccountLoginModal,
            tooltip: 'Cuenta',
            style: IconButton.styleFrom(
              backgroundColor: _isDemoLoggedIn ? _primaryFixed : _surfaceLow,
              minimumSize: const Size(42, 42),
              padding: const EdgeInsets.all(8),
              shape: const CircleBorder(),
            ),
            icon: Icon(
              _isDemoLoggedIn
                  ? Icons.person_rounded
                  : Icons.account_circle_outlined,
              color: _isDemoLoggedIn ? _primary : _onSurface,
              size: 23,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PESTAÑA 0: INTERFAZ INICIAL DE EXPLORACIÓN
  // ===========================================================================
  Widget _buildExploreHomeTab() {
    final trendingPlaces = _filteredPlaces.take(10).toList();
    final Place previewPlace =
        trendingPlaces.isNotEmpty ? trendingPlaces.first : Place.mockPlaces.first;

    return RefreshIndicator(
      color: _primary,
      onRefresh: () => _initializeFastLocationAndPlaces(forceRefresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          // 1. Header Query & Search Pill
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DESCUBRE TU CIUDAD',
                      style: TextStyle(
                        color: _tertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '¿A dónde quieres ir hoy?',
                      style: TextStyle(
                        color: _onSurface,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: const BoxDecoration(
                  color: _primaryContainer,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Barra de búsqueda funcional + Botón de distancia (< 3 km)
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.only(left: 14, right: 6),
                  decoration: BoxDecoration(
                    color: _surfaceLowest,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: _onSurface.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _submitCustomQuery,
                        child: const Icon(
                          Icons.search_rounded,
                          color: _outline,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) {
                            setState(() {
                              _liveFilterText = value;
                            });
                          },
                          onSubmitted: (_) => _submitCustomQuery(),
                          style: const TextStyle(
                            color: _onSurface,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            hintText:
                                'Cafeterías brunch, tacos, bares, hoteles...',
                            hintStyle: TextStyle(
                              color: _outline,
                              fontSize: 13.5,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          onPressed: _clearCustomSearch,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: _outline,
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                        ),
                      // Botón directo para ejecutar la búsqueda
                      InkWell(
                        onTap: _submitCustomQuery,
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Buscar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Distance Chip Toggle (< 1 km, < 3 km, < 5 km, Todo)
              InkWell(
                onTap: _cycleDistanceFilter,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _surfaceLowest,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: _onSurface.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.near_me_rounded,
                        color: _primary,
                        size: 17,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _distanceLabels[_distanceStepIndex],
                        style: const TextStyle(
                          color: _onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 2. Interactive Swipe Mode Feature Banner ("Modo Swipe")
          _buildSwipeFeatureBanner(previewPlace),
          const SizedBox(height: 22),

          // 3. Categories Grid ("Explora por vibes" - 6 categorías)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Explora por vibes',
                style: TextStyle(
                  color: _onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                '6 categorías',
                style: TextStyle(
                  color: _tertiary.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildVibesCategoriesGrid(),

          // Zonas concurridas cercanas
          if (_busyZones.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text(
              'Zonas concurridas cerca',
              style: TextStyle(
                color: _onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _busyZones.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final zone = _busyZones[index];
                  return ActionChip(
                    avatar: const Icon(
                      Icons.place_rounded,
                      color: _primary,
                      size: 16,
                    ),
                    label: Text(zone.name),
                    backgroundColor: _surfaceLowest,
                    side: const BorderSide(color: _surfaceVariant),
                    labelStyle: const TextStyle(
                      color: _onSurface,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    onPressed: () {
                      setState(() {
                        _currentAreaName = zone.name;
                      });
                      _startSearchAndOpenSwipe(
                        title: zone.name,
                        centerLat: zone.latitude,
                        centerLon: zone.longitude,
                        forceRefresh: true,
                      );
                    },
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 22),

          // 4. Trending Today Section ("Tendencia hoy")
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Tendencia hoy',
                    style: TextStyle(
                      color: _onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: _primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _currentTabIndex = 1;
                  });
                },
                child: const Text(
                  'Ver todo',
                  style: TextStyle(
                    color: _primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (_isLoadingPlaces)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(
                      color: _primaryContainer,
                      strokeWidth: 2.8,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Buscando lugares reales en $_currentAreaName...',
                      style: const TextStyle(
                        color: _onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...trendingPlaces.map(
              (place) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildTrendingVenueCard(place),
              ),
            ),
        ],
      ),
    );
  }

  void _submitCustomQuery() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _clearCustomSearch();
      setState(() {
        _currentTabIndex = 1;
      });
      return;
    }
    _startSearchAndOpenSwipe(
      title: 'Búsqueda: "$query"',
      customQuery: query,
      forceRefresh: true,
    );
  }

  /// Banner destacado "Modo Swipe" con miniatura de cartas apiladas.
  Widget _buildSwipeFeatureBanner(Place previewPlace) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _onSurface.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              bottom: -30,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _primaryFixed.withValues(alpha: 0.65),
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: -15,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _secondaryFixed.withValues(alpha: 0.45),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _primaryFixed.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.local_fire_department_rounded,
                                    color: _primary,
                                    size: 14,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'MODO SWIPE',
                                    style: TextStyle(
                                      color: _onPrimaryFixed,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Descubre lugares deslizando cartas',
                              style: TextStyle(
                                color: _onSurface,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Sin rodeos. Desliza a la derecha para abrir la ruta paso a paso o guardar tu próxima salida al instante.',
                              style: TextStyle(
                                color: _onSurfaceVariant,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 92,
                        height: 110,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.rotate(
                              angle: 0.2,
                              child: Container(
                                width: 74,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: _surfaceHigh,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            Transform.rotate(
                              angle: -0.1,
                              child: Container(
                                width: 76,
                                height: 92,
                                decoration: BoxDecoration(
                                  color: _surfaceVariant,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            Transform.rotate(
                              angle: 0.04,
                              child: Container(
                                width: 78,
                                height: 94,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CachedNetworkImage(
                                        imageUrl: previewPlace.imageUrl,
                                        fit: BoxFit.cover,
                                      ),
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black
                                                  .withValues(alpha: 0.6),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const Positioned(
                                        left: 8,
                                        bottom: 8,
                                        child: Icon(
                                          Icons.favorite_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _currentTabIndex = 1;
                      });
                    },
                    icon: const Icon(Icons.style_rounded, size: 20),
                    label: const Text(
                      'Empezar a deslizar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryContainer,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      elevation: 6,
                      shadowColor: _primaryContainer.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Grid 3x2 de "Explora por vibes".
  Widget _buildVibesCategoriesGrid() {
    final List<Map<String, dynamic>> vibes = [
      {
        'emoji': '⭐',
        'label': 'Top rated',
        'category': 'Todos',
        'bg': _secondaryFixed.withValues(alpha: 0.55),
      },
      {
        'emoji': '🍽️',
        'label': 'Restaurantes',
        'category': 'Restaurantes',
        'bg': _surfaceHigh,
      },
      {
        'emoji': '☕',
        'label': 'Cafeterías',
        'category': 'Cafeterías',
        'bg': _surfaceHigh,
      },
      {
        'emoji': '🍸',
        'label': 'Bares',
        'category': 'Bares',
        'bg': _surfaceHigh,
      },
      {
        'emoji': '🪩',
        'label': 'Clubs',
        'category': 'Clubs',
        'bg': _surfaceHigh,
      },
      {
        'emoji': '🏨',
        'label': 'Hoteles',
        'category': 'Hoteles',
        'bg': _surfaceHigh,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: vibes.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.08,
      ),
      itemBuilder: (context, index) {
        final item = vibes[index];
        return InkWell(
          onTap: () {
            _startSearchAndOpenSwipe(
              title: item['label'] as String,
              category: item['category'] as String,
              customQuery: null,
            );
          },
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceLowest,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: _onSurface.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: item['bg'] as Color,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    item['emoji'] as String,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item['label'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Tarjeta compacta de lugar en "Tendencia hoy".
  Widget _buildTrendingVenueCard(Place place) {
    final bool isSaved = _savedPlaceIds.contains(place.id);
    final bool isFar = place.isFarWithThreshold(_farThresholdKm);

    return GestureDetector(
      onTap: () => _triggerNavigationForPlace(place),
      child: Container(
        decoration: BoxDecoration(
          color: _surfaceLowest,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: _onSurface.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            children: [
              SizedBox(
                height: 192,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: place.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: _surfaceContainer,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: _primary,
                            strokeWidth: 2.2,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: _surfaceContainer,
                        child: const Icon(
                          Icons.photo_rounded,
                          color: _outline,
                          size: 40,
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.2),
                            Colors.black.withValues(alpha: 0.75),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 56,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _surfaceLowest.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              place.subcategoryLabel,
                              style: const TextStyle(
                                color: _onSurface,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isFar)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Lejos',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: InkWell(
                        onTap: () => _toggleSavedPlace(place),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _surfaceLowest.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSaved
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isSaved ? _primary : _onSurface,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  place.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      color: _surfaceVariant,
                                      size: 15,
                                    ),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(
                                        place.address ?? _currentAreaName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _surfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _surfaceLowest.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: _secondaryContainer,
                                  size: 16,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  place.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: _onSurface,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        children: [
                          Icon(
                            place.distanceKm <= 1.2
                                ? Icons.directions_walk_rounded
                                : Icons.directions_car_rounded,
                            color: _tertiary,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            place.formattedDistance,
                            style: const TextStyle(
                              color: _onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '(${place.estimatedTimeLabel})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: _outlineVariant,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isFar ? 'Lejos' : 'Abierto ahora',
                            style: TextStyle(
                              color: isFar ? _primary : _tertiary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${place.priceLevel} · ${place.category}',
                      style: const TextStyle(
                        color: _primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PESTAÑA 1: SWIPE DE TARJETAS CON FILTROS Y BÚSQUEDA ACTIVA
  // ===========================================================================
  Widget _buildSwipeTab() {
    final places = _filteredPlaces;
    final bool showEmptyState =
        !_isLoadingPlaces && (places.isEmpty || _isDeckFinished);

    return Padding(
      padding: const EdgeInsets.only(bottom: 84),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_activeCustomQuery != null && _activeCustomQuery!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryFixed,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          color: _primary,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Búsqueda: "$_activeCustomQuery"',
                          style: const TextStyle(
                            color: _onPrimaryFixed,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _clearCustomSearch,
                          child: const Icon(
                            Icons.close_rounded,
                            color: _primary,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          _buildSwipeCategoryFilterBar(),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _isLoadingPlaces
                  ? _buildSwipeLoadingState()
                  : showEmptyState
                      ? _buildSwipeEmptyState()
                      : _buildSwiperDeck(places),
            ),
          ),
          if (!_isLoadingPlaces && !showEmptyState) _buildBottomActionControls(),
        ],
      ),
    );
  }

  Widget _buildSwipeCategoryFilterBar() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _swipeCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _swipeCategories[index];
          final bool isSelected = _selectedCategory == category;

          return ChoiceChip(
            label: Text(category),
            selected: isSelected,
            onSelected: (_) {
              setState(() {
                _selectedCategory = category;
                _isDeckFinished = false;
                _deckSessionKey++;
                _swiperController.dispose();
                _swiperController = CardSwiperController();
              });
            },
            showCheckmark: false,
            backgroundColor: _surfaceLowest,
            selectedColor: _primaryContainer,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : _onSurface,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12.5,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: BorderSide(
                color: isSelected ? _primaryContainer : _surfaceVariant,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSwipeLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: _primaryContainer,
            strokeWidth: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Buscando lugares en $_activeSearchTitle...',
            style: const TextStyle(
              color: _onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ordenados del más cercano y con mejores reseñas al más lejano',
            style: TextStyle(
              color: _onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwiperDeck(List<Place> places) {
    final int displayedCards = places.length.clamp(1, 3);

    return KeyedSubtree(
      key: ValueKey('deck_${_selectedCategory}_$_deckSessionKey'),
      child: CardSwiper(
        controller: _swiperController,
        cardsCount: places.length,
        numberOfCardsDisplayed: displayedCards,
        isLoop: false,
        backCardOffset: const Offset(0, 22),
        scale: 0.93,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        allowedSwipeDirection: const AllowedSwipeDirection.only(
          left: true,
          right: true,
        ),
        onSwipe: _handleSwipe,
        onEnd: () {
          if (mounted) {
            setState(() {
              _isDeckFinished = true;
            });
          }
        },
        cardBuilder: (
          context,
          index,
          horizontalOffsetPercentage,
          verticalOffsetPercentage,
        ) {
          final place = places[index];
          return _PlaceSwipeCard(
            place: place,
            farThresholdKm: _farThresholdKm,
            isSaved: _savedPlaceIds.contains(place.id),
            onToggleSave: () => _toggleSavedPlace(place),
            horizontalThresholdPercentage: horizontalOffsetPercentage,
          );
        },
      ),
    );
  }

  /// Controles circulares sin ningún cuadro alrededor y con botón de reinicio de búsqueda.
  Widget _buildBottomActionControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 24, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ActionCircleButton(
            icon: Icons.close_rounded,
            iconColor: _primaryContainer,
            backgroundColor: _surfaceLowest,
            borderColor: _primaryFixed,
            glowColor: _primaryContainer.withValues(alpha: 0.18),
            size: 60,
            iconSize: 28,
            tooltip: 'Descartar lugar',
            onTap: () => _swiperController.swipe(CardSwiperDirection.left),
          ),
          const SizedBox(width: 20),
          _ActionCircleButton(
            icon: Icons.refresh_rounded,
            iconColor: _secondary,
            backgroundColor: _surfaceLowest,
            borderColor: _secondaryFixed,
            glowColor: _secondaryContainer.withValues(alpha: 0.2),
            size: 48,
            iconSize: 22,
            tooltip: 'Reiniciar búsqueda',
            onTap: _resetCurrentSearch,
          ),
          const SizedBox(width: 20),
          _ActionCircleButton(
            icon: Icons.navigation_rounded,
            iconColor: Colors.white,
            backgroundColor: _emeraldNav,
            borderColor: _emeraldNav,
            glowColor: _emeraldNav.withValues(alpha: 0.38),
            size: 64,
            iconSize: 28,
            tooltip: 'Ir ahora (Abrir ruta)',
            onTap: () => _swiperController.swipe(CardSwiperDirection.right),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _surfaceLowest,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: _onSurface.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: _primaryFixed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.travel_explore_rounded,
                  color: _primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '¡Recorriste todos los lugares!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _onSurface,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Reinicia la búsqueda para volver a empezar desde el lugar más cercano o explora otra categoría.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _resetCurrentSearch,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text(
                    'Reiniciar búsqueda',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryContainer,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // PESTAÑA 2: LUGARES GUARDADOS
  // ===========================================================================
  Widget _buildSavedTab() {
    final saved = _savedPlaces;
    if (saved.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 80),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: _primaryFixed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_border_rounded,
                  color: _primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Aún no tienes lugares guardados',
                style: TextStyle(
                  color: _onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Toca el corazón en cualquier lugar o desliza a la derecha en el Modo Swipe para guardarlos aquí.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      itemCount: saved.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) => _buildTrendingVenueCard(saved[index]),
    );
  }

  // ===========================================================================
  // PESTAÑA 3: CONFIGURACIÓN LIMPIA (SIN "MÓDULO DE AJUSTES", SIN SELECCIÓN DE
  // PROVEEDOR DE MAPAS Y SIN CUADRO DE API KEY DE GOOGLE MAPS)
  // ===========================================================================
  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      children: [
        const Text(
          'PREFERENCIAS',
          style: TextStyle(
            color: _tertiary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Configuración',
          style: TextStyle(
            color: _onSurface,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 18),

        // 1. Acceso rápido a Cuenta / Iniciar Sesión
        _buildSettingsCard(
          title: 'Mi Cuenta',
          icon: Icons.person_outline_rounded,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _primaryFixed,
                  child: Icon(
                    _isDemoLoggedIn
                        ? Icons.person_rounded
                        : Icons.person_outline_rounded,
                    color: _primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isDemoLoggedIn ? _demoUserName : 'Sesión no iniciada',
                        style: const TextStyle(
                          color: _onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      Text(
                        _isDemoLoggedIn
                            ? _demoUserEmail
                            : 'Inicia sesión para sincronizar tus lugares guardados',
                        style: const TextStyle(
                          color: _onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openAccountLoginModal,
                icon: Icon(
                  _isDemoLoggedIn ? Icons.manage_accounts_rounded : Icons.login_rounded,
                  size: 18,
                ),
                label: Text(
                  _isDemoLoggedIn ? 'Ver perfil de cuenta' : 'Iniciar sesión',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryContainer,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. Distancia y Aviso "Lejos"
        _buildSettingsCard(
          title: 'Distancia y Etiqueta "Lejos"',
          icon: Icons.straighten_rounded,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Mostrar aviso "Lejos" a partir de:',
                  style: TextStyle(
                    color: _onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryFixed,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_farThresholdKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: _farThresholdKm,
              min: 1.0,
              max: 10.0,
              divisions: 18,
              activeColor: _primaryContainer,
              inactiveColor: _surfaceVariant,
              label: '${_farThresholdKm.toStringAsFixed(1)} km',
              onChanged: (value) {
                setState(() {
                  _farThresholdKm = value;
                });
              },
            ),
            const Text(
              'Los lugares siempre se ordenan empezando por el más cercano y con mejores reseñas. Al superar esta distancia verás la etiqueta "Lejos" en la tarjeta.',
              style: TextStyle(color: _onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 3. Estado del GPS y Datos
        _buildSettingsCard(
          title: 'Ubicación GPS y Datos',
          icon: Icons.my_location_rounded,
          children: [
            Row(
              children: [
                Icon(
                  _hasLocationPermission
                      ? Icons.verified_rounded
                      : Icons.warning_amber_rounded,
                  color: _hasLocationPermission ? _emeraldNav : _secondary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _hasLocationPermission
                        ? 'GPS activo en $_currentAreaName (${_userLatitude.toStringAsFixed(4)}, ${_userLongitude.toStringAsFixed(4)})'
                        : 'Permiso de GPS pendiente o inactivo',
                    style: const TextStyle(
                      color: _onSurface,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _placesService.clearCache();
                      _initializeFastLocationAndPlaces(forceRefresh: true);
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Actualizar GPS'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: const BorderSide(color: _primaryFixed),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _navigationService.openSystemLocationSettings,
                    icon: const Icon(Icons.settings_suggest_rounded, size: 18),
                    label: const Text('Permisos OS'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _tertiary,
                      side: const BorderSide(color: _surfaceVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _onSurface.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primaryFixed.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: _primary, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _onSurface,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  // ===========================================================================
  // BARRA DE NAVEGACIÓN INFERIOR FLOTANTE
  // ===========================================================================
  Widget _buildFloatingBottomNav() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _surfaceLowest.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _surfaceVariant.withValues(alpha: 0.7),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _onSurface.withValues(alpha: 0.12),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildBottomNavItem(
                    index: 0,
                    icon: Icons.explore_outlined,
                    activeIcon: Icons.explore_rounded,
                    label: 'Explorar',
                  ),
                  _buildBottomNavItem(
                    index: 1,
                    icon: Icons.local_fire_department_outlined,
                    activeIcon: Icons.local_fire_department_rounded,
                    label: 'Swipe',
                    showBadgeDot: true,
                  ),
                  _buildBottomNavItem(
                    index: 2,
                    icon: Icons.favorite_border_rounded,
                    activeIcon: Icons.favorite_rounded,
                    label: 'Guardados',
                  ),
                  _buildBottomNavItem(
                    index: 3,
                    icon: Icons.tune_rounded,
                    activeIcon: Icons.tune_rounded,
                    label: 'Preferencias',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    bool showBadgeDot = false,
  }) {
    final bool isActive = _currentTabIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _currentTabIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  color: isActive ? _primary : _onSurfaceVariant,
                  size: 24,
                ),
                if (showBadgeDot)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _primaryContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: _surfaceLowest, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? _primary : _onSurfaceVariant,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Módulo de Iniciar Sesión genérico (solo visual) que se abre al tocar el icono de Cuenta.
class _GenericLoginModalSheet extends StatefulWidget {
  final bool isLoggedIn;
  final String userName;
  final String userEmail;
  final void Function(String name, String email) onLoginSuccess;
  final VoidCallback onLogout;

  const _GenericLoginModalSheet({
    required this.isLoggedIn,
    required this.userName,
    required this.userEmail,
    required this.onLoginSuccess,
    required this.onLogout,
  });

  @override
  State<_GenericLoginModalSheet> createState() =>
      _GenericLoginModalSheetState();
}

class _GenericLoginModalSheetState extends State<_GenericLoginModalSheet> {
  static const Color _surfaceLowest = Color(0xFFFFFFFF);
  static const Color _surfaceLow = Color(0xFFF1F3FD);
  static const Color _surfaceVariant = Color(0xFFDFE2EC);
  static const Color _onSurface = Color(0xFF181C23);
  static const Color _onSurfaceVariant = Color(0xFF5A403F);
  static const Color _primary = Color(0xFFB52330);
  static const Color _primaryContainer = Color(0xFFFF5A5F);
  static const Color _primaryFixed = Color(0xFFFFDAD8);
  static const Color _outline = Color(0xFF8E706F);

  bool _isRegisterMode = false;
  bool _obscurePassword = true;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
        child: widget.isLoggedIn ? _buildLoggedInProfile() : _buildAuthForm(),
      ),
    );
  }

  Widget _buildLoggedInProfile() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            color: _surfaceVariant,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 20),
        const CircleAvatar(
          radius: 38,
          backgroundColor: _primaryFixed,
          child: Icon(Icons.person_rounded, color: _primary, size: 40),
        ),
        const SizedBox(height: 14),
        Text(
          widget.userName,
          style: const TextStyle(
            color: _onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.userEmail,
          style: const TextStyle(
            color: _onSurfaceVariant,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text(
              'Cerrar sesión',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _primary,
              side: const BorderSide(color: _primaryFixed),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: _surfaceVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _primaryFixed,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: _primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isRegisterMode ? 'Crear Cuenta' : 'Iniciar Sesión',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'Guarda tus lugares favoritos en SpotSwipe',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: _outline),
            ),
          ],
        ),
        const SizedBox(height: 22),

        if (_isRegisterMode) ...[
          _buildInputField(
            controller: _nameController,
            label: 'Nombre completo',
            hint: 'Ej. Alex Rivera',
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 14),
        ],

        _buildInputField(
          controller: _emailController,
          label: 'Correo electrónico',
          hint: 'tu@correo.com',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),

        _buildInputField(
          controller: _passwordController,
          label: 'Contraseña',
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: _outline,
              size: 20,
            ),
          ),
        ),

        if (!_isRegisterMode)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              child: const Text(
                '¿Olvidaste tu contraseña?',
                style: TextStyle(
                  color: _primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 18),

        // Botón principal de Iniciar Sesión / Crear Cuenta
        ElevatedButton(
          onPressed: () {
            final email = _emailController.text.trim().isEmpty
                ? 'usuario@spotswipe.app'
                : _emailController.text.trim();
            final name = _nameController.text.trim().isEmpty
                ? email.split('@').first
                : _nameController.text.trim();
            widget.onLoginSuccess(name, email);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryContainer,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            elevation: 6,
            shadowColor: _primaryContainer.withValues(alpha: 0.4),
          ),
          child: Text(
            _isRegisterMode ? 'Registrarme' : 'Iniciar Sesión',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(height: 18),

        Row(
          children: [
            const Expanded(child: Divider(color: _surfaceVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'o continúa con',
                style: TextStyle(
                  color: _onSurfaceVariant.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ),
            const Expanded(child: Divider(color: _surfaceVariant)),
          ],
        ),
        const SizedBox(height: 14),

        // Botones sociales visuales
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    widget.onLoginSuccess('Usuario Google', 'google@spotswipe.app'),
                icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                label: const Text(
                  'Google',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _onSurface,
                  backgroundColor: _surfaceLowest,
                  side: const BorderSide(color: _surfaceVariant),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    widget.onLoginSuccess('Usuario Apple', 'apple@spotswipe.app'),
                icon: const Icon(Icons.apple_rounded, size: 22),
                label: const Text(
                  'Apple',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _onSurface,
                  backgroundColor: _surfaceLowest,
                  side: const BorderSide(color: _surfaceVariant),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isRegisterMode
                  ? '¿Ya tienes una cuenta?'
                  : '¿Aún no tienes cuenta?',
              style: const TextStyle(color: _onSurfaceVariant, fontSize: 13),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _isRegisterMode = !_isRegisterMode;
                });
              },
              child: Text(
                _isRegisterMode ? 'Inicia sesión' : 'Regístrate',
                style: const TextStyle(
                  color: _primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _onSurface,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(color: _onSurface, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _outline, fontSize: 13.5),
            prefixIcon: Icon(icon, color: _outline, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: _surfaceLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _primaryContainer, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta deslizable en Modo Swipe actualizada a la nueva línea estética.
class _PlaceSwipeCard extends StatelessWidget {
  final Place place;
  final double farThresholdKm;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final int horizontalThresholdPercentage;

  const _PlaceSwipeCard({
    required this.place,
    required this.farThresholdKm,
    required this.isSaved,
    required this.onToggleSave,
    required this.horizontalThresholdPercentage,
  });

  static const Color _surfaceLowest = Color(0xFFFFFFFF);
  static const Color _onSurface = Color(0xFF181C23);
  static const Color _primary = Color(0xFFB52330);
  static const Color _primaryContainer = Color(0xFFFF5A5F);
  static const Color _secondaryContainer = Color(0xFFFEAE2C);
  static const Color _emeraldNav = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final double swipeProgress =
        (horizontalThresholdPercentage / 100).clamp(-1.0, 1.0);
    final bool isFar = place.isFarWithThreshold(farThresholdKm);

    return Container(
      decoration: BoxDecoration(
        color: _surfaceLowest,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _onSurface.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: place.imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: const Color(0xFFEBEEF7),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: _primaryContainer,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFFEBEEF7),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_not_supported_outlined,
                      color: Color(0xFF8E706F),
                      size: 46,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Foto no disponible',
                      style: TextStyle(color: Color(0xFF8E706F), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.42, 0.72, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.2),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.78),
                      Colors.black.withValues(alpha: 0.94),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _surfaceLowest.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.near_me_rounded,
                                color: _primary,
                                size: 15,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                place.formattedDistance,
                                style: const TextStyle(
                                  color: _onSurface,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isFar)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Lejos',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _surfaceLowest.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          place.category,
                          style: const TextStyle(
                            color: _onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onToggleSave,
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _surfaceLowest.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSaved
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isSaved ? _primary : _onSurface,
                            size: 19,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (swipeProgress.abs() > 0.12)
              Positioned(
                top: 74,
                left: swipeProgress > 0 ? 20 : null,
                right: swipeProgress < 0 ? 20 : null,
                child: Opacity(
                  opacity: swipeProgress.abs().clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: swipeProgress > 0 ? -0.16 : 0.16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (swipeProgress > 0
                                ? _emeraldNav
                                : _primaryContainer)
                            .withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            swipeProgress > 0
                                ? Icons.navigation_rounded
                                : Icons.close_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            swipeProgress > 0 ? 'IR AHORA' : 'DESCARTAR',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isFar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _primaryContainer.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _primaryContainer.withValues(alpha: 0.6),
                          ),
                        ),
                        child: const Text(
                          'Lejos • Este lugar está retirado de tu ubicación actual',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          place.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _surfaceLowest.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: _secondaryContainer,
                              size: 16,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              place.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: _onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: Colors.white70,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${place.address ?? place.subcategoryLabel} · ${place.priceLevel} · (${place.reviewsCount} reseñas)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: place.tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón de acción circular flotante sin ningún recuadro o artefacto cuadrado.
class _ActionCircleButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final Color glowColor;
  final double size;
  final double iconSize;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionCircleButton({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.glowColor,
    required this.size,
    required this.iconSize,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: glowColor,
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipOval(
          child: Material(
            color: backgroundColor,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Icon(
                  icon,
                  color: iconColor,
                  size: iconSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
