// Who Pays? — guest join page.
//
// Why this exists: forcing six people to install an app at a restaurant table
// with bad wifi kills the game. The host has the app; everyone else scans the
// QR and lands here. Same room, same rules, no install.
//
// Detection is necessarily weaker than the native app — a browser cannot see
// the screen unlock — so this leans on DeviceMotion plus the Page Visibility
// API, which catches the most common tell: switching away to another app.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.4';
// Absolute, like the script tag in index.html: this page is also served
// at /j/CODE, where a relative path would resolve to /j/ballot.js and 404.
import {
  approvalsFor,
  isApprovedBy,
  ranked,
  trailing,
  venueSubtitle,
  votersCount,
} from '/ballot.js';

const SUPABASE_URL = 'https://uhslpvssmpmhtmlmncxo.supabase.co';
const SUPABASE_KEY = 'sb_publishable_3oYIMsneJAbIFvDUP7N_Bw_xqxo-UIn';

// Mirrors DetectionConfig in the Flutter app. Kept in sync by hand; if these
// drift apart, app players and web players are playing different games.
const CFG = {
  gravitySmoothing: 0.97,
  gravitySmoothingSettling: 0.90,
  gravityUpdateGate: 0.5,
  stillnessTolerance: 0.35,
  stillnessWindowMs: 1200,
  pickUpAccelThreshold: 1.6,
  pickUpGyroThreshold: 1.1,
  sustainedMotionWindowMs: 180,
  armingGraceMs: 3000,
};

// Declared before the client, because every request has to carry it.
// `deviceId` is a function declaration, so it is hoisted and safe to call
// here even though its body appears further down.
const DEVICE = deviceId();

const db = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
  // Says which device this is. The security policies only permit changes to
  // rows carrying this id, which is what stops anyone holding this key —
  // and it is public, right there above — from deleting other people's
  // tables. Table codes are four guessable letters; device ids are not.
  global: { headers: { 'x-device-id': DEVICE } },
});

const $ = (id) => document.getElementById(id);
const show = (id) => $(id).classList.remove('hidden');
const hide = (id) => $(id).classList.add('hidden');

// ---------------------------------------------------------------------------
// Identity — same idea as the app: a random local id, no account.
// ---------------------------------------------------------------------------
function deviceId() {
  let id = localStorage.getItem('who_pays_device');
  if (!id) {
    id = crypto.randomUUID();
    try { localStorage.setItem('who_pays_device', id); } catch { /* private mode */ }
  }
  return id;
}

let room = null;
let players = [];
let channel = null;

// ---------------------------------------------------------------------------
// Pick-up detector — a direct port of PickupDetector.
// ---------------------------------------------------------------------------
const detector = {
  state: 'idle',           // idle | settling | armed | caught
  g: null,                 // gravity estimate
  linear: 0,
  rotation: 0,
  stillSince: null,
  motionSince: null,
  armedAt: null,
  roundStart: 0,
  reason: null,

  start(now) {
    this.state = 'settling';
    this.roundStart = now;
    this.g = null;
    this.stillSince = this.motionSince = this.armedAt = null;
    this.reason = null;
  },

  reset() {
    this.state = 'idle';
    this.stillSince = this.motionSince = this.armedAt = null;
    this.linear = this.rotation = 0;
    this.reason = null;
  },

  trigger(reason, now) {
    if (this.state !== 'settling' && this.state !== 'armed') return;
    this.caught(reason, now);
  },

  caught(reason, now) {
    this.state = 'caught';
    this.reason = reason;
    this.lastedMs = Math.max(0, now - this.roundStart);
    onCaught();
  },

  accel(x, y, z, now) {
    if (!this.g) {
      this.g = { x, y, z };
      this.linear = 0;
      return this.evaluate(now);
    }

    const candidate = mag(x - this.g.x, y - this.g.y, z - this.g.z);

    // Freeze the gravity estimate during movement while armed, or repeated
    // table bumps drag it off true and an untouched phone reads as moving.
    const update =
      this.state !== 'armed' || candidate < CFG.gravityUpdateGate;

    if (update) {
      const a = this.state === 'armed'
        ? CFG.gravitySmoothing
        : CFG.gravitySmoothingSettling;
      this.g.x = a * this.g.x + (1 - a) * x;
      this.g.y = a * this.g.y + (1 - a) * y;
      this.g.z = a * this.g.z + (1 - a) * z;
      this.linear = mag(x - this.g.x, y - this.g.y, z - this.g.z);
    } else {
      this.linear = candidate;
    }

    return this.evaluate(now);
  },

  gyro(x, y, z, now) {
    this.rotation = mag(x, y, z);
    return this.evaluate(now);
  },

  evaluate(now) {
    if (this.state === 'settling') {
      const still = this.linear < CFG.stillnessTolerance &&
                    this.rotation < CFG.stillnessTolerance;
      if (!still) {
        this.stillSince = null;
      } else {
        if (this.stillSince === null) this.stillSince = now;
        if (now - this.stillSince >= CFG.stillnessWindowMs) {
          this.state = 'armed';
          this.armedAt = now;
          this.motionSince = null;
        }
      }
    } else if (this.state === 'armed') {
      if (now - this.armedAt < CFG.armingGraceMs) {
        this.motionSince = null;
        return;
      }
      const moved = this.linear > CFG.pickUpAccelThreshold;
      const spun = this.rotation > CFG.pickUpGyroThreshold;
      if (!moved && !spun) {
        this.motionSince = null;
      } else {
        if (this.motionSince === null) this.motionSince = now;
        if (now - this.motionSince >= CFG.sustainedMotionWindowMs) {
          this.caught(moved ? 'motion' : 'rotation', now);
        }
      }
    }
  },
};

const mag = (x, y, z) => Math.sqrt(x * x + y * y + z * z);

// ---------------------------------------------------------------------------
// Sensors
// ---------------------------------------------------------------------------
let sensorsOn = false;

async function startSensors() {
  if (sensorsOn) return;

  // iOS 13+ requires a user gesture before motion events are delivered. The
  // join tap is that gesture, which is why sensors start there and not later.
  try {
    if (typeof DeviceMotionEvent?.requestPermission === 'function') {
      const granted = await DeviceMotionEvent.requestPermission();
      if (granted !== 'granted') return;
    }
  } catch { /* older browsers just work */ }

  window.addEventListener('devicemotion', (e) => {
    const now = performance.now();
    const a = e.accelerationIncludingGravity;
    if (a && a.x !== null) detector.accel(a.x, a.y, a.z, now);

    const r = e.rotationRate;
    if (r && r.alpha !== null) {
      // DeviceMotion reports deg/s; the thresholds are in rad/s.
      const d2r = Math.PI / 180;
      detector.gyro(r.alpha * d2r, r.beta * d2r, r.gamma * d2r, now);
    }
    render();
  });

  // The big one for a browser: they unlocked the phone and switched away.
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) detector.trigger('leftApp', performance.now());
  });
  window.addEventListener('blur', () => {
    detector.trigger('leftApp', performance.now());
  });

  sensorsOn = true;
}

// ---------------------------------------------------------------------------
// Where to eat
//
// Spec: VENUES.md §12-§13. Approval voting, one round: tap every place you are
// willing to go, most approvals wins.
//
// The tally and the tie-break live in ballot.js, which has no DOM and no
// network so it can be run against the same cases as the Dart tests. Keeping
// them there rather than inline is deliberate: those rules have to agree with
// VenueBallot on the host's phone exactly, and an untested copy is how two
// screens at one table end up showing different winners.
// ---------------------------------------------------------------------------
let venues = [];
let votes = [];

// Turned off for good the first time the database answers "no such table" or
// "no such column", so a page newer than its database quietly drops the
// feature instead of showing errors at a dinner table.
let votingSupported = true;

// 42P01 no such table, 42703 no such column, PGRST20x schema cache miss.
// All of them mean the same thing here: migration_venues.sql has not been run.
const unsupported = (error) =>
  !!error && ['42P01', '42703', 'PGRST204', 'PGRST205'].includes(error.code);

async function refreshBallot(code) {
  if (!votingSupported) return;

  const v = await db.from('room_venues').select('*').eq('room_code', code);
  if (unsupported(v.error)) { votingSupported = false; return; }
  const t = await db.from('venue_votes').select('*').eq('room_code', code);
  if (unsupported(t.error)) { votingSupported = false; return; }

  // Any other error (a dropped connection) leaves the last known ballot on
  // screen. An empty list would read as "the host found nowhere", which is a
  // different and wrong message.
  if (!v.error) venues = v.data || [];
  if (!t.error) votes = t.data || [];
  render();
}

async function toggleVenue(id) {
  if (!room || !votingSupported) return;
  const mine = isApprovedBy(votes, id, DEVICE);

  // Optimistic: on cafe wifi a vote that waits for a round-trip feels broken,
  // and the realtime update will replace this with the truth shortly.
  votes = mine
    ? votes.filter((v) => !(v.venue_id === id && v.device_id === DEVICE))
    : [...votes, { venue_id: id, device_id: DEVICE }];
  render();

  const { error } = mine
    ? await db.from('venue_votes').delete()
        .eq('venue_id', id).eq('device_id', DEVICE)
    : await db.from('venue_votes').upsert(
        { room_code: room.code, venue_id: id, device_id: DEVICE },
        { onConflict: 'venue_id,device_id' },
      );

  if (unsupported(error)) { votingSupported = false; render(); return; }
  // Put the server's version back if the write did not land.
  if (error) refreshBallot(room.code);
}

// A channel of its own, deliberately: if these tables are missing from the
// realtime publication, a failure here must not take the room and player
// subscriptions down with it.
let ballotChannel = null;

function subscribeBallot(code) {
  if (!votingSupported) return;
  try {
    ballotChannel = db.channel(`ballot:${code}`)
      .on('postgres_changes',
          { event: '*', schema: 'public', table: 'room_venues', filter: `room_code=eq.${code}` },
          () => refreshBallot(code))
      .on('postgres_changes',
          { event: '*', schema: 'public', table: 'venue_votes', filter: `room_code=eq.${code}` },
          () => refreshBallot(code))
      .subscribe();
  } catch {
    ballotChannel = null;
  }
}

function leaveBallot() {
  if (!ballotChannel) return;
  try { db.removeChannel(ballotChannel); } catch { /* already gone */ }
  ballotChannel = null;
}

function renderBallot() {
  if (!votingSupported || !venues.length) { hide('ballot'); return; }
  show('ballot');

  // The host's decision arrives on the room row, not on the ballot. It is a
  // decision somebody committed to, which is a different thing from the
  // computed leader — the host may settle against the vote.
  const decidedId = room ? room.decided_venue_id : null;
  const decided = decidedId ? venues.find((v) => v.id === decidedId) : null;

  if (decided) {
    hide('venueList');
    hide('ballotHint');
    show('decided');
    $('decidedName').textContent = decided.name;
    return;
  }

  hide('decided');
  show('venueList');
  show('ballotHint');

  const voters = votersCount(votes);
  $('ballotHint').textContent = voters === 0
    ? 'Tap everywhere you would happily go.'
    : `${voters} ${voters === 1 ? 'person has' : 'people have'} voted · ` +
      'the host closes it';

  const dimmed = trailing(venues, votes);
  const list = $('venueList');
  list.innerHTML = '';

  for (const v of ranked(venues, votes)) {
    const mine = isApprovedBy(votes, v.id, DEVICE);
    const row = document.createElement('button');
    row.className = 'venue' +
      (mine ? ' mine voted' : '') +
      (dimmed.has(v.id) ? ' trailing' : '');

    const body = document.createElement('span');
    body.className = 'n';
    const title = document.createElement('span');
    // textContent throughout: place names come from a provider by way of the
    // database, and none of that is trusted markup.
    title.textContent = v.name || 'Unnamed';
    const sub = document.createElement('span');
    sub.className = 'sub';
    sub.textContent = venueSubtitle(v);
    body.append(title, sub);

    const count = document.createElement('span');
    count.className = 'count';
    count.textContent = String(approvalsFor(votes, v.id));

    row.append(body, count);
    row.addEventListener('click', () => toggleVenue(v.id));
    list.appendChild(row);
  }
}

// ---------------------------------------------------------------------------
// Room
// ---------------------------------------------------------------------------
function codeFromUrl() {
  const m = location.pathname.match(/\/j\/([A-Za-z]{4})\/?$/);
  if (m) return m[1].toUpperCase();
  const q = new URLSearchParams(location.search).get('code');
  return q ? q.toUpperCase() : null;
}

async function join() {
  const code = $('code').value.trim().toUpperCase();
  const name = $('name').value.trim();
  const err = $('joinErr');
  err.textContent = '';

  if (!/^[A-HJ-NP-Z]{4}$/.test(code)) {
    err.textContent = 'A table code is four letters.';
    return;
  }
  if (!name) {
    err.textContent = 'Add your name so the table knows who cracked.';
    return;
  }

  $('joinBtn').disabled = true;
  try {
    const { data, error } = await db
      .from('rooms').select('*').eq('code', code).limit(1);
    if (error) throw error;
    if (!data.length) throw new Error('No table with that code.');
    room = data[0];

    const up = await db.from('room_players')
      .upsert({ room_code: code, device_id: DEVICE, name },
              { onConflict: 'room_code,device_id' });
    if (up.error) throw up.error;

    await startSensors();
    startHeartbeat(code);
    // Before subscribe(), so votingSupported is known and the ballot channel
    // is only opened on a database that actually has those tables.
    await refreshBallot(code);
    subscribe(code);
    hide('join');
    show('lobby');
    await refreshPlayers(code);

    // Act on the status the room is ALREADY in. Without this, someone who
    // scans the QR after the host has started sits in the lobby forever,
    // because followStatus otherwise only runs on a realtime change.
    followStatus();
  } catch (e) {
    err.textContent = e.message || 'Could not join.';
  } finally {
    $('joinBtn').disabled = false;
  }
}

// "I am still here."
//
// The phone app sends this every 15 seconds; this page did not, which was
// harmless only while the database had no last_seen column to compare
// against. Once it does, a guest who never reports stops counting as being
// at the table after 45 seconds and is deleted after two minutes — so a web
// guest would be dropped from the game mid-round, while still looking fine
// on their own screen.
let heartbeat = null;
let presenceSupported = true;

function startHeartbeat(code) {
  stopHeartbeat();
  const beat = async () => {
    if (!presenceSupported) return;
    const { error } = await db.from('room_players')
      .update({ last_seen: new Date().toISOString() })
      .eq('room_code', code)
      .eq('device_id', DEVICE);
    // PGRST204 (write path) and 42703 (read path) both mean the migration
    // has not been applied here yet. Stop asking rather than retry forever.
    if (error && (error.code === 'PGRST204' || error.code === '42703')) {
      presenceSupported = false;
    }
  };
  beat();
  // Comfortably inside the 45-second window, so one missed beat on a bad
  // cafe connection does not look like someone walking out.
  heartbeat = setInterval(beat, 15000);
}

function stopHeartbeat() {
  if (heartbeat) clearInterval(heartbeat);
  heartbeat = null;
}

function subscribe(code) {
  channel = db.channel(`room:${code}`)
    .on('postgres_changes',
        { event: '*', schema: 'public', table: 'rooms', filter: `code=eq.${code}` },
        (p) => { room = p.new; followStatus(); })
    .on('postgres_changes',
        { event: '*', schema: 'public', table: 'room_players', filter: `room_code=eq.${code}` },
        () => refreshPlayers(code))
    .subscribe();

  joinPresence(code);
  subscribeBallot(code);
}

// Announce this browser on the room's presence channel.
//
// Closing this page drops the socket, and everyone else learns about it at
// once. Without it a web guest who wanders off leaves the table unable to
// finish on any database that has not had the presence migration applied —
// the heartbeat above cannot help, because there is no column to write to.
let presenceChannel = null;

function joinPresence(code) {
  leavePresence();
  try {
    presenceChannel = db.channel(`presence:room:${code}`, {
      config: { presence: { key: DEVICE } },
    });
    presenceChannel.subscribe(async (status) => {
      if (status !== 'SUBSCRIBED') return;
      try {
        await presenceChannel.track({ device_id: DEVICE });
      } catch { /* presence is a bonus, never a requirement */ }
    });
  } catch {
    presenceChannel = null;
  }
}

function leavePresence() {
  if (!presenceChannel) return;
  try { db.removeChannel(presenceChannel); } catch { /* already gone */ }
  presenceChannel = null;
}

// Leaving the page should look like leaving the table immediately, rather
// than waiting for the socket to time out.
window.addEventListener('pagehide', () => {
  leavePresence();
  leaveBallot();
});

async function refreshPlayers(code) {
  const { data } = await db.from('room_players')
    .select('*').eq('room_code', code);
  players = data || [];
  render();
}

let roundStartedAt = 0;
let ticker = null;

function followStatus() {
  if (!room) return;

  if (room.status === 'settling' || room.status === 'running') {
    if (detector.state === 'idle' || detector.state === 'caught') {
      detector.start(performance.now());
      roundStartedAt = 0;
      hide('lobby'); hide('join'); show('round');
      clearInterval(ticker);
      ticker = setInterval(render, 250);
    }
  } else if (room.status === 'lobby') {
    detector.reset();
    clearInterval(ticker);
    ticker = null;
    hide('round'); show('lobby');
  }
  render();
}

let reported = false;

async function onCaught() {
  if (reported || !room) return;
  reported = true;
  try {
    await db.from('room_players').update({
      caught_at: new Date().toISOString(),
      lasted_ms: Math.round(detector.lastedMs || 0),
      catch_reason: detector.reason,
    }).eq('room_code', room.code).eq('device_id', DEVICE).is('caught_at', null);
  } catch {
    reported = false; // let a retry happen on the next event
  }
  render();
}

// ---------------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------------
function clock(ms) {
  const total = Math.max(0, Math.floor(ms / 1000));
  const m = String(Math.floor(total / 60)).padStart(2, '0');
  const s = String(total % 60).padStart(2, '0');
  return `${m}:${s}`;
}

function playerList(el) {
  el.innerHTML = '';
  const sorted = [...players].sort((a, b) => {
    if (!!a.caught_at !== !!b.caught_at) return a.caught_at ? 1 : -1;
    if (a.caught_at && b.caught_at) return a.caught_at.localeCompare(b.caught_at);
    return a.name.localeCompare(b.name);
  });
  for (const p of sorted) {
    const li = document.createElement('li');
    if (p.caught_at) li.className = 'out';
    li.innerHTML =
      `<span class="dot"></span><span class="grow"></span>` +
      `<span class="t"></span>`;
    li.querySelector('.grow').textContent =
      p.device_id === DEVICE ? `${p.name}  (you)` : p.name;
    li.querySelector('.t').textContent =
      p.caught_at && p.lasted_ms != null ? clock(p.lasted_ms) : '';
    el.appendChild(li);
  }
}

function render() {
  if (!$('lobby').classList.contains('hidden')) {
    playerList($('lobbyList'));
    renderBallot();
  }
  if ($('round').classList.contains('hidden')) return;

  playerList($('roundList'));

  const stateEl = $('state');
  const hint = $('hint');

  if (detector.state === 'settling') {
    stateEl.className = 'state settling';
    stateEl.textContent = 'PUT IT DOWN';
    hint.textContent = 'Hold still — the round starts when your phone settles';
    $('clock').textContent = '00:00';
    return;
  }

  if (detector.state === 'armed') {
    if (!roundStartedAt) roundStartedAt = performance.now();
    stateEl.className = 'state armed';
    stateEl.textContent = "DON'T TOUCH IT";
    hint.textContent = room ? `Loser ${stakeText(room)}` : '';
    $('clock').textContent = clock(performance.now() - roundStartedAt);
    return;
  }

  if (detector.state === 'caught') {
    stateEl.className = 'state caught';
    stateEl.textContent = 'CAUGHT';
    hint.textContent = reasonText(detector.reason);
    $('clock').textContent = clock(detector.lastedMs || 0);
  }
}

function stakeText(r) {
  if (r.stake === 'custom') return (r.custom_stake || 'loses').trim();
  return {
    bill: 'pays the bill',
    nextRound: 'buys the next round',
    dishes: 'does the dishes',
    chores: 'does the chores',
  }[r.stake] || 'loses';
}

function reasonText(reason) {
  return {
    motion: 'You picked the phone up',
    rotation: 'You turned the phone over',
    leftApp: 'You left the page',
    conceded: 'You gave up',
  }[reason] || 'You cracked';
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
const preset = codeFromUrl();
if (preset) $('code').value = preset;
$('joinBtn').addEventListener('click', join);
$('giveUp').addEventListener('click', () => {
  detector.trigger('conceded', performance.now());
  render();
});
$('code').addEventListener('keydown', (e) => { if (e.key === 'Enter') join(); });
$('name').addEventListener('keydown', (e) => { if (e.key === 'Enter') join(); });
