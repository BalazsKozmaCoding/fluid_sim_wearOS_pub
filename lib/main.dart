import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'simulation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // immersiveSticky hides both status & nav bars until the user swipes
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext ctx) => MaterialApp(
    title: 'Slosh O\'Clock',
    home: SimulationScreen(),
  );
}
