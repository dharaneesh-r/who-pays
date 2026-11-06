import 'package:go_router/go_router.dart';

import '../../features/detector/presentation/detector_debug_screen.dart';
import '../../features/game/presentation/game_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';

final appRouter = GoRouter(
  initialLocation: HomeScreen.path,
  routes: [
    GoRoute(
      path: HomeScreen.path,
      builder: (_, _) => const HomeScreen(),
    ),
    GoRoute(
      path: GameScreen.path,
      builder: (_, _) => const GameScreen(),
    ),
    GoRoute(
      path: StatsScreen.path,
      builder: (_, _) => const StatsScreen(),
    ),
    GoRoute(
      path: DetectorDebugScreen.path,
      builder: (_, _) => const DetectorDebugScreen(),
    ),
  ],
);
