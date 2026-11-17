import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'ui/app_theme.dart';

void main() => runApp(const TenterApp());

class TenterApp extends StatelessWidget {
  const TenterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tenter · LOOM-8 companion',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.mint,
        brightness: Brightness.dark,
        surface: AppColors.panel,
      ),
      fontFamily: 'Roboto',
    ),
    home: const CompanionHome(),
  );
}
