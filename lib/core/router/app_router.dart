import 'package:go_router/go_router.dart';

import '../../features/bill/presentation/bill_split_screen.dart';
import '../../features/detector/presentation/detector_debug_screen.dart';
import '../../features/detector/presentation/trace_screen.dart';
import '../../features/duel/presentation/duel_screen.dart';
import '../../features/game/presentation/game_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/room/presentation/host_setup_screen.dart';
import '../../features/room/presentation/join_room_screen.dart';
import '../../features/room/presentation/room_lobby_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';
import '../../features/venue/presentation/venue_ballot_screen.dart';

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
      path: HostSetupScreen.path,
      builder: (_, _) => const HostSetupScreen(),
    ),
    GoRoute(
      path: JoinRoomScreen.path,
      builder: (_, _) => const JoinRoomScreen(),
    ),
    GoRoute(
      path: RoomLobbyScreen.path,
      builder: (_, _) => const RoomLobbyScreen(),
    ),
    GoRoute(
      path: VenueBallotScreen.path,
      builder: (_, _) => const VenueBallotScreen(),
    ),
    GoRoute(
      path: BillSplitScreen.path,
      builder: (_, _) => const BillSplitScreen(),
    ),
    GoRoute(
      path: DuelScreen.path,
      builder: (_, _) => const DuelScreen(),
    ),
    GoRoute(
      path: StatsScreen.path,
      builder: (_, _) => const StatsScreen(),
    ),
    GoRoute(
      path: SettingsScreen.path,
      builder: (_, _) => const SettingsScreen(),
    ),
    GoRoute(
      path: TraceScreen.path,
      builder: (_, _) => const TraceScreen(),
    ),
    GoRoute(
      path: DetectorDebugScreen.path,
      builder: (_, _) => const DetectorDebugScreen(),
    ),
  ],
);
