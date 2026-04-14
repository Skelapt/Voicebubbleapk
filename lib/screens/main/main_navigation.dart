import 'package:flutter/material.dart';
import 'library_screen.dart';

class MainNavigation extends StatelessWidget {
  const MainNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    // Single screen — Library IS the app. No tabs, no bottom nav.
    return const LibraryScreen();
  }
}
