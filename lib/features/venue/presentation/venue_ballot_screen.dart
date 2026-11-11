import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/local/device_identity.dart';
import '../../room/application/room_session.dart';
import '../application/venue_session.dart';
import '../domain/venue_models.dart';

/// Where the table is eating.
///
/// Spec: VENUES.md §12–§13. Approval voting, one round: everyone taps every
/// place they are willing to go, and the most-approved place wins. Not ranked,
/// not multi-round — a hungry table will not sit through six rounds of voting.
class VenueBallotScreen extends ConsumerWidget {
  const VenueBallotScreen({super.key});

  static const path = '/where';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(venueSessionProvider);
    final session = ref.read(venueSessionProvider.notifier);
    final room = ref.watch(roomSessionProvider);
    final deviceId = ref.watch(deviceIdProvider).value;

    // Alone, you are your own host: there is nobody to wait for.
    final canDecide = !room.inRoom || room.isHost;
    final ballot = state.ballot;
    final decided = state.decided;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WHERE TO EAT'),
        actions: [
          if (state.hasCandidates && canDecide)
            IconButton(
              tooltip: 'Search again',
              onPressed: state.searching ? null : session.startOver,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.error != null)
              _ErrorBanner(
                message: state.error!,
                onDismiss: session.dismissError,
              ),
            if (decided != null)
              _DecidedCard(
                venue: decided,
                canReopen: canDecide,
                onReopen: session.reopen,
              ),
            Expanded(
              child: !state.hasCandidates
                  ? _Empty(
                      searching: state.searching,
                      canSearch: canDecide,
                      onSearch: session.search,
                    )
                  : _Ballot(
                      ballot: ballot,
                      deviceId: deviceId,
                      locked: decided != null,
                      onTap: session.toggle,
                    ),
            ),
            // A licence requirement, not polish: Google place data shown
            // without a Google map has to carry visible credit.
            if (state.hasCandidates)
              _Attribution(
                text: ref.watch(placeProviderProvider).attribution,
              ),
            if (state.hasCandidates && decided == null)
              _Footer(
                ballot: ballot,
                canDecide: canDecide,
                onLockIn: session.lockIn,
              ),
          ],
        ),
      ),
    );
  }
}

/// Nothing on the ballot yet.
class _Empty extends StatelessWidget {
  const _Empty({
    required this.searching,
    required this.canSearch,
    required this.onSearch,
  });

  final bool searching;
  final bool canSearch;
  final Future<void> Function() onSearch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            searching ? 'LOOKING…' : 'NOBODY\nHAS DECIDED',
            textAlign: TextAlign.center,
            style: text.displayMedium?.copyWith(fontSize: 44),
          ),
          const SizedBox(height: 14),
          Text(
            canSearch
                ? 'Find what is open nearby, then everyone votes for every '
                    'place they are happy with.'
                : 'Waiting for the host to find places nearby…',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: Colors.white60),
          ),
          const SizedBox(height: 28),
          if (searching)
            const Center(child: CircularProgressIndicator())
          else if (canSearch)
            FilledButton.icon(
              onPressed: onSearch,
              icon: const Icon(Icons.explore_outlined),
              label: const Text('FIND PLACES NEARBY'),
            ),
        ],
      ),
    );
  }
}

/// The candidate list, best-first.
class _Ballot extends StatelessWidget {
  const _Ballot({
    required this.ballot,
    required this.deviceId,
    required this.locked,
    required this.onTap,
  });

  final VenueBallot ballot;
  final String? deviceId;
  final bool locked;
  final Future<void> Function(String venueId) onTap;

  @override
  Widget build(BuildContext context) {
    final ranked = ballot.ranked;
    final trailing = ballot.trailing;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: ranked.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final venue = ranked[i];
        return _VenueTile(
          venue: venue,
          approvals: ballot.approvalsFor(venue.id),
          mine: deviceId != null && ballot.isApprovedBy(venue.id, deviceId!),
          // "The least selected will be removed" — dimmed and sunk to the
          // bottom rather than deleted, so a table can change its mind.
          isTrailing: trailing.contains(venue.id),
          leading: i == 0 && ballot.hasAnyVote,
          enabled: !locked && deviceId != null,
          onTap: () => onTap(venue.id),
        );
      },
    );
  }
}

class _VenueTile extends StatelessWidget {
  const _VenueTile({
    required this.venue,
    required this.approvals,
    required this.mine,
    required this.isTrailing,
    required this.leading,
    required this.enabled,
    required this.onTap,
  });

  final VenueCandidate venue;
  final int approvals;
  final bool mine;
  final bool isTrailing;
  final bool leading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final border = mine
        ? AppTheme.accent.withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.10);

    return Opacity(
      // Dimmed, not hidden. A greyed-out restaurant still has to be tappable:
      // one more vote is exactly how a table rescues it.
      opacity: isTrailing ? 0.45 : 1,
      child: Material(
        color: mine
            ? AppTheme.accent.withValues(alpha: 0.12)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (leading)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.local_fire_department,
                                size: 17,
                                color: AppTheme.accent,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              venue.name,
                              style: text.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitle(venue),
                        style: text.bodyMedium?.copyWith(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Count(approvals: approvals, mine: mine),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Distance, rating and address, skipping whatever the provider did not
  /// give us — real place data is full of holes, and an empty " · · " is
  /// worse than a short line.
  static String _subtitle(VenueCandidate v) {
    final parts = <String>[
      if (v.distanceM != null) distanceLabel(v.distanceM!),
      if (v.rating != null) '★ ${v.rating!.toStringAsFixed(1)}',
      if (v.address != null && v.address!.trim().isNotEmpty) v.address!.trim(),
    ];
    return parts.isEmpty ? 'No details' : parts.join('  ·  ');
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.approvals, required this.mine});

  final int approvals;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: approvals > 0
                ? AppTheme.accent.withValues(alpha: 0.18)
                : AppTheme.surfaceHigh,
            shape: BoxShape.circle,
            border: Border.all(
              color: mine
                  ? AppTheme.accent
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            '$approvals',
            style: TextStyle(
              fontFamily: AppTheme.body,
              fontSize: 17,
              fontVariations: AppTheme.weight(700),
              color: approvals > 0 ? AppTheme.accent : Colors.white38,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          mine ? 'you’re in' : 'tap',
          style: TextStyle(
            fontSize: 10.5,
            color: mine ? AppTheme.accent : Colors.white30,
          ),
        ),
      ],
    );
  }
}

/// The running state of the vote, and the host's way to end it.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.ballot,
    required this.canDecide,
    required this.onLockIn,
  });

  final VenueBallot ballot;
  final bool canDecide;
  final Future<void> Function(String venueId) onLockIn;

  @override
  Widget build(BuildContext context) {
    final winner = ballot.winner;
    final voters = ballot.votersCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            winner == null
                ? 'No votes yet — tap everywhere you would happily go'
                : '${winner.name} is leading · '
                    '$voters ${voters == 1 ? 'person has' : 'people have'} voted',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 10),
          if (canDecide)
            FilledButton(
              // Disabled until somebody votes. The winner is deliberately
              // null until then rather than defaulting to the first
              // restaurant in the list, so there is nothing to lock in.
              onPressed: winner == null ? null : () => onLockIn(winner.id),
              child: Text(
                winner == null ? 'WAITING FOR VOTES' : 'LOCK IT IN',
              ),
            )
          else
            const Text(
              'The host closes the vote',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

/// Decided. Shown above the list on every phone at the table.
class _DecidedCard extends StatelessWidget {
  const _DecidedCard({
    required this.venue,
    required this.canReopen,
    required this.onReopen,
  });

  final VenueCandidate venue;
  final bool canReopen;
  final Future<void> Function() onReopen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasPoint = venue.lat != null && venue.lng != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.safe.withValues(alpha: 0.12),
        border: Border.all(color: AppTheme.safe.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'WE’RE GOING TO',
            textAlign: TextAlign.center,
            style: text.labelLarge?.copyWith(
              color: AppTheme.safe,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            venue.name,
            textAlign: TextAlign.center,
            style: text.headlineMedium,
          ),
          if (venue.distanceM != null) ...[
            const SizedBox(height: 4),
            Text(
              distanceLabel(venue.distanceM!),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (hasPoint)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    onPressed: () => _openMaps(venue),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('MAPS'),
                  ),
                ),
              if (hasPoint && canReopen) const SizedBox(width: 10),
              if (canReopen)
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    onPressed: onReopen,
                    child: const Text('VOTE AGAIN'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Hands the coordinates to whatever maps app the phone has. Silently does
  /// nothing if there is none — a dead button is better than a crash at a
  /// restaurant table.
  static Future<void> _openMaps(VenueCandidate v) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${v.lat},${v.lng}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Credit for the place data, when the provider in use requires it.
class _Attribution extends StatelessWidget {
  const _Attribution({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final label = text;
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white30, fontSize: 11),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.14),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
            color: Colors.white54,
          ),
        ],
      ),
    );
  }
}

/// Metres for anything under a kilometre, then one decimal place. "1.2 km" is
/// what a person says; "1183 m" is what a sensor says.
String distanceLabel(int metres) {
  if (metres < 1000) return '$metres m';
  return '${(metres / 1000).toStringAsFixed(1)} km';
}
