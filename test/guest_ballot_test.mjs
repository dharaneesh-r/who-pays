// The guest page's voting maths, run against the same cases as
// test/venue_models_test.dart.
//
//   node --test test/guest_ballot_test.mjs
//
// This is not part of `flutter test` — it is JavaScript, and the project has
// no node test runner wired up. Run it by hand when either side changes.
// web_guest/README.md says so too.
//
// Why it exists: ballot.js and VenueBallot must agree about who won. The
// pick-up detector is already a hand-synced copy between the two languages,
// and web_guest/README.md calls that out as a hazard. One hazard is enough.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  approvalsFor,
  isApprovedBy,
  ranked,
  trailing,
  venueSubtitle,
  votersCount,
  winner,
  distanceLabel,
} from '../web_guest/ballot.js';

const v = (id, { distance = null, name = null } = {}) => ({
  id,
  name: name ?? `Venue ${id}`,
  distance_m: distance,
});

const vote = (venue_id, device_id) => ({ venue_id, device_id });

test('counts one approval per device', () => {
  const votes = [vote('a', 'phone1'), vote('a', 'phone2'), vote('b', 'phone1')];
  assert.equal(approvalsFor(votes, 'a'), 2);
  assert.equal(approvalsFor(votes, 'b'), 1);
});

test('one device cannot stuff the ballot for its favourite', () => {
  const votes = [vote('a', 'p1'), vote('a', 'p1'), vote('a', 'p1')];
  assert.equal(approvalsFor(votes, 'a'), 1);
});

test('a device may approve several places — that is the point', () => {
  const votes = [vote('a', 'p1'), vote('b', 'p1')];
  assert.equal(isApprovedBy(votes, 'a', 'p1'), true);
  assert.equal(isApprovedBy(votes, 'c', 'p1'), false);
  // One person voting for two places is still one voter.
  assert.equal(votersCount(votes), 1);
});

test('counts voters, not votes', () => {
  const votes = [vote('a', 'p1'), vote('b', 'p1'), vote('a', 'p2')];
  assert.equal(votersCount(votes), 2);
});

test('the winner is the most approved', () => {
  const venues = [v('a'), v('b')];
  const votes = [vote('b', 'p1'), vote('b', 'p2'), vote('a', 'p1')];
  assert.equal(winner(venues, votes).id, 'b');
});

test('the winner is null while nobody has voted — never a silent default', () => {
  assert.equal(winner([v('a'), v('b')], []), null);
});

test('the winner is null with no candidates', () => {
  assert.equal(winner([], []), null);
});

test('a tie breaks by distance, so the table walks less', () => {
  const venues = [v('far', { distance: 4000 }), v('near', { distance: 300 })];
  const votes = [vote('far', 'p1'), vote('near', 'p2')];
  assert.equal(winner(venues, votes).id, 'near');
});

test('an unknown distance loses a tie to a known one', () => {
  const venues = [v('unknown'), v('known', { distance: 4500 })];
  const votes = [vote('unknown', 'p1'), vote('known', 'p2')];
  assert.equal(winner(venues, votes).id, 'known');
});

test('the order is identical regardless of row order', () => {
  // Equal approvals, equal distance, equal name: the id decides, and the app
  // and the browser must agree. Two screens at one table showing different
  // restaurants is the failure this guards against.
  const a = v('a', { distance: 100, name: 'Same' });
  const b = v('b', { distance: 100, name: 'Same' });

  const one = ranked([a, b], [vote('a', 'p1'), vote('b', 'p2')]);
  const two = ranked([b, a], [vote('b', 'p2'), vote('a', 'p1')]);

  assert.deepEqual(one.map((x) => x.id), two.map((x) => x.id));
  assert.equal(one[0].id, 'a');
});

test('trailing is empty before anyone votes', () => {
  assert.equal(trailing([v('a'), v('b')], []).size, 0);
});

test('trailing is empty while every candidate is level', () => {
  const votes = [vote('a', 'p1'), vote('b', 'p1')];
  assert.equal(trailing([v('a'), v('b')], votes).size, 0);
});

test('trailing marks the joint-lowest once there is a spread', () => {
  const venues = [v('a'), v('b'), v('c')];
  const votes = [vote('a', 'p1'), vote('a', 'p2'), vote('b', 'p1')];
  assert.deepEqual([...trailing(venues, votes)], ['c']);
});

test('trailing marks several when they are jointly last', () => {
  const venues = [v('a'), v('b'), v('c')];
  const got = [...trailing(venues, [vote('a', 'p1')])].sort();
  assert.deepEqual(got, ['b', 'c']);
});

test('trailing never marks the only candidate', () => {
  assert.equal(trailing([v('a')], [vote('a', 'p1')]).size, 0);
});

test('distanceLabel reads the way a person speaks', () => {
  assert.equal(distanceLabel(450), '450 m');
  assert.equal(distanceLabel(1200), '1.2 km');
});

test('the subtitle survives the holes real place data has', () => {
  assert.equal(
    venueSubtitle({ distance_m: 450, rating: 4.3, address: 'T. Nagar' }),
    '450 m  ·  ★ 4.3  ·  T. Nagar',
  );
  assert.equal(venueSubtitle({ distance_m: 1200 }), '1.2 km');
  assert.equal(venueSubtitle({}), 'No details');
  // Postgres numeric can arrive as a string.
  assert.equal(venueSubtitle({ rating: '4.5' }), '★ 4.5');
});
