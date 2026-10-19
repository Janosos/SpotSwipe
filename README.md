# SpotSwipe

Aplicación móvil en Flutter para descubrir restaurantes, cafés, bares y hoteles cercanos mediante tarjetas deslizables estilo Tinder y abrir navegación paso a paso en tiempo real.

## Características del MVP

- **Swipe Left / Botón X (`#EF4444`)**: Descarta el lugar actual y pasa a la siguiente tarjeta.
- **Swipe Right / Botón Navegación (`#10B981`)**: Hace match con el lugar y lanza de inmediato la ruta paso a paso en la app nativa de mapas (Google Maps en Android, Apple Maps / Google Maps en iOS, o fallback universal web).
- **Filtro por Categorías**: `Todos`, `Restaurantes`, `Cafés`, `Hoteles`, `Bares`.
- **Geolocalización Real**: Solicita permisos de GPS con `geolocator` y recalcula la distancia en kilómetros desde tu ubicación actual hacia cada lugar.
- **UI/UX Oscura Moderna**: Tema `#0F0F11` con acentos ámbar (`#F59E0B`) y verde esmeralda (`#10B981`), caché de imágenes (`cached_network_image`) y badges translúcidos con desenfoque (`BackdropFilter`).

## Ejecución

```bash
flutter pub get
flutter run
```
