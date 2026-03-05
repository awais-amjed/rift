import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/home/home_screen.dart';

class AppRoutes {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext get context => navigatorKey.currentContext!;

  static const String home = '/';

  static final router = GoRouter(
    initialLocation: home,
    navigatorKey: navigatorKey,
    routes: [
      GoRoute(path: home, builder: (context, state) => const HomeScreen()),
    ],
  );
}
