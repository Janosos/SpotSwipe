import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// Resultado de la verificación de permisos de ubicación.
enum LocationPermissionStatus {
  granted,
  serviceDisabled,
  denied,
  deniedForever,
}

/// Proveedores de navegación disponibles.
/// - En Android se utiliza Google Maps por defecto.
/// - En iOS el usuario puede elegir entre Google Maps o Maps de iOS (Apple Maps).
enum MapProvider {
  googleMaps,
  appleMaps,
}

extension MapProviderExtension on MapProvider {
  String get displayName {
    switch (this) {
      case MapProvider.googleMaps:
        return 'Google Maps';
      case MapProvider.appleMaps:
        return 'Maps de iOS';
    }
  }
}

/// Modo de transporte para el cálculo de la ruta.
enum TravelMode {
  driving,
  walking,
  bicycling,
}

extension TravelModeExtension on TravelMode {
  String get label {
    switch (this) {
      case TravelMode.driving:
        return 'Auto';
      case TravelMode.walking:
        return 'Caminando';
      case TravelMode.bicycling:
        return 'Bicicleta';
    }
  }

  String get androidModeCode {
    switch (this) {
      case TravelMode.driving:
        return 'd';
      case TravelMode.walking:
        return 'w';
      case TravelMode.bicycling:
        return 'b';
    }
  }

  String get webModeName {
    switch (this) {
      case TravelMode.driving:
        return 'driving';
      case TravelMode.walking:
        return 'walking';
      case TravelMode.bicycling:
        return 'bicycling';
    }
  }
}

/// Servicio encargado de gestionar permisos de ubicación y lanzar
/// navegación paso a paso en la app nativa de mapas del dispositivo.
class NavigationService {
  const NavigationService();

  bool get isIOSDevice => !kIsWeb && Platform.isIOS;
  bool get isAndroidDevice => !kIsWeb && Platform.isAndroid;

  /// Verifica que el GPS esté activo y solicita permisos de ubicación en runtime.
  Future<LocationPermissionStatus> ensureLocationPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionStatus.serviceDisabled;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationPermissionStatus.denied;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionStatus.deniedForever;
    }

    return LocationPermissionStatus.granted;
  }

  /// Obtiene la posición actual del usuario de forma ultra-rápida:
  /// Si [preferFastKnownPosition] es true, devuelve primero la última posición conocida
  /// del GPS si existe para no bloquear la búsqueda, o solicita una lectura rápida.
  Future<Position?> getCurrentPosition({
    bool preferFastKnownPosition = false,
  }) async {
    final status = await ensureLocationPermission();
    if (status != LocationPermissionStatus.granted) {
      return null;
    }

    if (preferFastKnownPosition) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          return lastKnown;
        }
      } catch (_) {}
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  /// Abre los ajustes de ubicación del sistema operativo.
  Future<void> openSystemLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Calcula la distancia en kilómetros entre dos coordenadas.
  double calculateDistanceKm({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    final meters = Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
    return double.parse((meters / 1000).toStringAsFixed(2));
  }

  /// Abre inmediatamente la ruta paso a paso hacia [latitude], [longitude].
  ///
  /// - En **Android**: Usa **Google Maps por defecto** (`google.navigation:q=lat,lng&mode=...`).
  /// - En **iOS**: Usa el proveedor seleccionado en [preferredIosProvider]
  ///   ([MapProvider.googleMaps] o [MapProvider.appleMaps]).
  Future<bool> launchTurnByTurnNavigation({
    required double latitude,
    required double longitude,
    MapProvider preferredIosProvider = MapProvider.googleMaps,
    TravelMode travelMode = TravelMode.driving,
  }) async {
    final Uri googleMapsWebFallback = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=${travelMode.webModeName}',
    );
    final Uri appleMapsWebFallback = Uri.parse(
      'https://maps.apple.com/?daddr=$latitude,$longitude&dirflg=${travelMode.androidModeCode}',
    );

    if (!kIsWeb) {
      if (Platform.isAndroid) {
        final Uri androidGoogleNavUri = Uri.parse(
          'google.navigation:q=$latitude,$longitude&mode=${travelMode.androidModeCode}',
        );
        if (await canLaunchUrl(androidGoogleNavUri)) {
          final bool launched = await launchUrl(
            androidGoogleNavUri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return true;
        }
      } else if (Platform.isIOS) {
        final Uri iosGoogleMapsUri = Uri.parse(
          'comgooglemaps://?daddr=$latitude,$longitude&directionsmode=${travelMode.webModeName}',
        );
        final Uri iosAppleMapsUri = Uri.parse(
          'maps://?daddr=$latitude,$longitude&dirflg=${travelMode.androidModeCode}',
        );

        if (preferredIosProvider == MapProvider.googleMaps) {
          if (await canLaunchUrl(iosGoogleMapsUri)) {
            final bool launched = await launchUrl(
              iosGoogleMapsUri,
              mode: LaunchMode.externalApplication,
            );
            if (launched) return true;
          }
          if (await canLaunchUrl(googleMapsWebFallback)) {
            final bool launched = await launchUrl(
              googleMapsWebFallback,
              mode: LaunchMode.externalApplication,
            );
            if (launched) return true;
          }
        } else {
          if (await canLaunchUrl(iosAppleMapsUri)) {
            final bool launched = await launchUrl(
              iosAppleMapsUri,
              mode: LaunchMode.externalApplication,
            );
            if (launched) return true;
          }
          if (await canLaunchUrl(appleMapsWebFallback)) {
            final bool launched = await launchUrl(
              appleMapsWebFallback,
              mode: LaunchMode.externalApplication,
            );
            if (launched) return true;
          }
        }
      }
    }

    if (await canLaunchUrl(googleMapsWebFallback)) {
      return await launchUrl(
        googleMapsWebFallback,
        mode: LaunchMode.externalApplication,
      );
    }

    return false;
  }
}
