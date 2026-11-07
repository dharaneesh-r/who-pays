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

const db = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
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

const DEVICE = deviceId();
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

function subscribe(code) {
  channel = db.channel(`room:${code}`)
    .on('postgres_changes',
        { event: '*', schema: 'public', table: 'rooms', filter: `code=eq.${code}` },
        (p) => { room = p.new; followStatus(); })
    .on('postgres_changes',
        { event: '*', schema: 'public', table: 'room_players', filter: `room_code=eq.${code}` },
        () => refreshPlayers(code))
    .subscribe();
}

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
  if (!$('lobby').classList.contains('hidden')) playerList($('lobbyList'));
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
