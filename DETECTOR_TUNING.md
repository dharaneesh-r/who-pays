# Tuning the detector against a real phone

The thresholds in `lib/core/constants/detection_config.dart` decide who pays.
Set them too low and a lorry going past the window blames someone who never
touched their phone; too high and the person who picks it up gets away with it.

They cannot honestly be chosen from a simulation. A real accelerometer on a
real table has its own noise floor, and a thump travels through a thin café
table quite differently from a heavy dining one. So the app records what the
device actually does, and the thresholds are fitted to that.

## 1. Record a trace

On the phone: **Settings → Sensor test → RECORD A TRACE → START RECORDING**.

It runs for 63 seconds and tells you what to do at each step. Do it on the
kind of table you would really play on. The screen stays awake throughout.

Each sample is labelled with the step it belongs to, which is what makes the
file usable as evidence rather than a blob of numbers:

| Step | What it proves |
|---|---|
| `still`, `still_end` | the noise floor, and whether gravity drifts over a minute |
| `thump`, `knock` | table knocks must **never** trigger a catch |
| `slide` | reported only — sliding a phone is arguably cheating anyway |
| `settle`, `settle_2`, `settle_3` | gaps that let the detector re-arm, so each lift is a clean trial |
| `lift_slow` | the hardest real case: the gentlest possible pick-up must still be caught |
| `lift_normal`, `flip` | ordinary pick-ups |

## 2. Pull it off the phone

```bash
adb pull /sdcard/Android/data/in.nearle.who_pays/files/ traces/
```

No root and no debuggable build needed — it is written to the app's own
external files directory.

## 3. Replay it through the real detector

```bash
dart run tools/analyse_trace.dart traces/trace_<timestamp>.csv
```

This feeds the trace through `PickupDetector` as one continuous stream —
exactly what the app experiences — and attributes each catch to the step it
happened in. It prints a verdict per step plus the peak acceleration and
rotation each one reached.

`INCONCLUSIVE` means the detector never armed during that step, so it could
not have caught anything; the step needs more stillness before it, not a
different threshold.

## 4. Read the peaks, then set the thresholds

A threshold has to sit **above every "no catch" peak and below every "catch"
peak**. The gap between the highest `thump` peak and the lowest `lift_slow`
peak is all the headroom there is. If they overlap, no single threshold can
separate them and the detector needs the sustained-motion window widened
instead — a thump is a spike lasting tens of milliseconds, while a pick-up
keeps moving for hundreds, which is the one property that always tells them
apart.

After changing anything in `detection_config.dart`, re-run both:

```bash
flutter test && dart run tools/analyse_trace.dart traces/trace_<timestamp>.csv
```

The unit tests guard the logic; the trace guards the numbers.
