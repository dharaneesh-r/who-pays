# Deploying the guest site

Everything in this folder is a plain static site — no build step, no
framework, no server. Four files do the work: `index.html`, `app.js`,
`ballot.js`,
`privacy.html`.

---

## Why this blocks the launch

It is easy to read "deploy the web page" as polish. It is not. **Two separate
things are broken until this is live**, and one of them stops Play accepting
your listing at all.

### 1. The privacy policy URL

Google Play requires a **publicly reachable** privacy policy URL before it
will accept a store listing. Not a document, not a PDF in Drive — a URL their
systems can fetch. `privacy.html` is already written and already names
`care@dharaneesh.in` as the contact.

Settings → Privacy policy in the app opens the same URL. Right now that opens
a blank page, because the host does not exist.

### 2. Every QR code

The app builds its QR codes as `<host>/j/CODE`. A guest scans it and the page
opens with the table code already filled in, so somebody who has never heard
of the app can join from their browser in about five seconds. That is the
single best thing about the sharing flow.

With a dead host, scanning a QR code leads nowhere. The host sitting at the
table sees a code on screen that cannot be used by anyone who does not
already have the app installed.

---

## What is in this folder

| File | Purpose |
|---|---|
| `index.html` | The join screen and the in-round screen |
| `app.js` | Joining, realtime, presence, and the pick-up detector ported from the Flutter app |
| `ballot.js` | The where-to-eat voting maths, ported from `VenueBallot`. Imported by `app.js` |
| `privacy.html` | The privacy policy, served at `/privacy` |
| `vercel.json` | Routing for Vercel — rewrites `/j/:code`, plus three security headers |
| `_redirects` | The same routing for Cloudflare Pages |

Both routing files can sit here together. Vercel ignores `_redirects`;
Cloudflare ignores `vercel.json`. Pick either host.

> **Why the routing file matters.** `/j/ABCD` is not a real file. Something
> has to tell the host "serve index.html for any path under /j/ and keep the
> URL", so `app.js` can read the code out of it. Without that rule the site
> looks completely fine — `/` and `/privacy` both load — and every QR code
> 404s. It is the one failure you will not notice by clicking around.

---

## Option A — Vercel (recommended)

1. **vercel.com** → sign in with GitHub
2. **Add New → Project** → import `dharaneesh-r/who-pays`
3. On the configure screen, **set Root Directory to `web_guest`**
4. Framework Preset: **Other**. Leave Build Command and Output Directory empty
5. **Deploy**

You get `https://<project-name>.vercel.app`.

> **Root Directory is the only setting that matters, and it is not the
> default.** Leave it at the repository root and Vercel will try to make sense
> of a Flutter project, then either fail or publish the wrong thing.

Without GitHub, from this machine:

```bash
npx vercel --cwd web_guest --prod
```

It opens a browser the first time to link your account.

## Option B — Cloudflare Pages

dash.cloudflare.com → **Workers & Pages → Create → Pages**. Either connect the
repository with root directory `web_guest`, or drag the folder in for a direct
upload. No build command. You get `https://<project>.pages.dev`.

---

## Verify it — four URLs

Replace `<your-domain>` and open each one.

| URL | Should show |
|---|---|
| `<your-domain>/` | the join screen asking for a 4-letter code |
| `<your-domain>/j/ABCD` | the same screen with **ABCD** already filled in |
| `<your-domain>/privacy` | the privacy policy |
| `<your-domain>/app.js` | JavaScript, not a 404 page |
| `<your-domain>/ballot.js` | JavaScript, not a 404 page — `app.js` imports it and the page is blank without it |

**`/j/ABCD` is the one that matters.** The other three work even on a broken
deploy. If it 404s, the routing rule is not being applied — on Vercel that is
almost always Root Directory not being set to `web_guest`.

---

## Then rebuild the app — this is not optional

The host is compiled into the app. Until you rebuild, the installed app still
prints QR codes pointing at the old dead domain and still links to a privacy
page that does not exist.

```bash
tools/build.sh appbundle --dart-define=JOIN_HOST=https://your-domain.vercel.app
```

`tools/build.sh` prints a warning on every build that omits this, naming the
host it is about to bake in, so you cannot ship the wrong one silently.

Once the domain is settled, change the default so the flag stops being
something to remember — in
[lib/features/room/domain/join_link.dart](../lib/features/room/domain/join_link.dart):

```dart
static const host = String.fromEnvironment(
  'JOIN_HOST',
  defaultValue: 'https://who-pays.pages.dev',   // <- your domain here
);
```

---

## Then give Play the URL

In Play Console, the privacy policy field takes `<your-domain>/privacy`.

Check it in a private browser window first. A URL that works only while you
are signed in will be rejected, and the rejection takes days to come back.

---

## If something is wrong

| Symptom | Cause |
|---|---|
| `/j/ABCD` 404s, everything else fine | Root Directory not set to `web_guest`, so `vercel.json` was never read |
| Everything 404s | Deployed the repo root instead of this folder |
| Page loads, joining fails | Open the browser console. A Supabase error means the database, not the deploy |
| Page loads but is blank | Check the console for a script error; `app.js` is a module and fails silently in very old browsers |
| QR codes still dead after deploying | The app was not rebuilt with `JOIN_HOST` |

---

## What this does not need

No server, no Node runtime, no environment variables, no secrets. The Supabase
publishable key is already in `app.js` and is designed to be public — it grants
only what row-level security allows, which is why `supabase/migration_rls.sql`
matters.

Hosting is free on both platforms at this traffic level.
