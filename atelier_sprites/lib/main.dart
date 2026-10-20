import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const AtelierSpritesApp());
}

class AtelierSpritesApp extends StatelessWidget {
  const AtelierSpritesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Atelier Sprites',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
      ),
      home: const HomeScreen(),
    );
  }
}
