import 'package:go_router/go_router.dart';

import '../../features/detector/presentation/detector_debug_screen.dart';
import '../../features/home/presentation/home_screen.dart';

final appRouter = GoRouter(
  initialLocation: HomeScreen.path,
  routes: [
    GoRoute(
      path: HomeScreen.path,
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: DetectorDebugScreen.path,
      builder: (_, __) => const DetectorDebugScreen(),
    ),
  ],
);
