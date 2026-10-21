import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'auth_page.dart';
import 'home_page.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AttendlyApp(api: Api()..restore()));
}

class AttendlyApp extends StatelessWidget {
  final Api api;
  const AttendlyApp({required this.api, super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Attendly · Điểm danh sinh viên',
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: teal),
      scaffoldBackgroundColor: const Color(0xfff4f6f9),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff4f6f9),
        foregroundColor: navy,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xffd9e0e7)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xffe4e9ef)),
        ),
      ),
    ),
    home: ListenableBuilder(
      listenable: api,
      builder: (_, _) => !api.restored
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : api.user == null
          ? AuthPage(api: api)
          : HomePage(key: ValueKey(api.user!['id']), api: api),
    ),
  );
}
