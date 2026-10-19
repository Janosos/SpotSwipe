import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/discover_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Configura barra de estado limpia acorde al nuevo diseño luminoso (#F9F9FF)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF9F9FF),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const SpotSwipeApp());
}

class SpotSwipeApp extends StatelessWidget {
  const SpotSwipeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color surfaceBg = Color(0xFFF9F9FF);
    const Color onSurface = Color(0xFF181C23);
    const Color primaryCrimson = Color(0xFFB52330);
    const Color primaryCoral = Color(0xFFFF5A5F);
    const Color secondaryAmber = Color(0xFFFEAE2C);
    const Color tertiaryTeal = Color(0xFF436465);

    return MaterialApp(
      title: 'SpotSwipe',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: surfaceBg,
        colorScheme: const ColorScheme.light(
          primary: primaryCrimson,
          primaryContainer: primaryCoral,
          secondary: secondaryAmber,
          tertiary: tertiaryTeal,
          surface: surfaceBg,
          onSurface: onSurface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: surfaceBg,
          foregroundColor: onSurface,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const DiscoverScreen(),
    );
  }
}
