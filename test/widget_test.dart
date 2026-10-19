import 'package:flutter_test/flutter_test.dart';
import 'package:spot_swipe/main.dart';

void main() {
  testWidgets(
      'SpotSwipe muestra header con GPS y botón de Cuenta, abre el módulo de Iniciar Sesión y limpia Configuración',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SpotSwipeApp());

    // Verifica que cargue el título principal del diseño
    expect(find.text('DESCUBRE TU CIUDAD'), findsOneWidget);
    expect(find.text('¿A dónde quieres ir hoy?'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);

    // Verifica que en el header esté el botón de Cuenta (y no el de Ajustes)
    expect(find.byTooltip('Cuenta'), findsOneWidget);
    expect(find.byTooltip('Ajustes'), findsNothing);

    // Abre el módulo visual de Iniciar Sesión al tocar el icono de Cuenta
    await tester.tap(find.byTooltip('Cuenta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Iniciar Sesión'), findsWidgets);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
  });
}
