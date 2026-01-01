import 'package:flutter/material.dart';
import 'widgets/roland_control_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Roland V-60HD Controller',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const RolandControlPage(
        panasonicIp: '10.0.1.21',
      ),
    );
  }
}