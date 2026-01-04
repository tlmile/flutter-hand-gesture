import 'package:flutter/material.dart';
import 'christmas_tree_3d_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChristmasTreeApp());
}

class ChristmasTreeApp extends StatelessWidget {
  const ChristmasTreeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3D Christmas Tree',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const ChristmasTree3DPage(),
    );
  }
}
