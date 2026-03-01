import 'package:flutter/material.dart';
import 'ui/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GravityGolfApp());
}

class GravityGolfApp extends StatelessWidget {
  const GravityGolfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gravity Golf',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F94FF)),
      ),
      home: const GameScreen(),
    );
  }
}