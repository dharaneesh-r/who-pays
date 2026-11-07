# Deploying the guest site

This folder is a plain static site — no build step, no framework. Two things
depend on it being live:

1. **The privacy policy URL.** Play will not accept the listing without one.
2. **Every QR code.** The QR encodes `<host>/j/CODE`, so if the host is dead,
   scanning it goes nowhere.

Config for both Vercel (`vercel.json`) and Cloudflare Pages (`_redirects`) is
in the folder. Whichever you pick, the other file is simply ignored.

## Vercel

1. Push this project to GitHub (or use the CLI below).
2. vercel.com → **Add New → Project** → import the repo.
3. **Root Directory: `web_guest`** ← the only setting that matters.
   Framework Preset: *Other*. Build Command: leave empty. Output: leave empty.
4. Deploy. You get `https://<name>.vercel.app`.

Or without GitHub:

```bash
npx vercel --cwd web_guest --prod
```

## Cloudflare Pages

dash.cloudflare.com → Workers & Pages → Create → Pages → upload the folder,
or connect the repo with root directory `web_guest`. No build command.

## Then check these four URLs

| URL | Should show |
|---|---|
| `/` | the join screen asking for a code |
| `/j/ABCD` | the join screen with **ABCD** already filled in |
| `/privacy` | the privacy policy |
| `/app.js` | JavaScript, not a 404 |

`/j/ABCD` is the one that catches a misconfigured deploy. If it 404s, the
rewrite is not being applied — on Vercel that almost always means the Root
Directory was not set to `web_guest`.

## Then rebuild the app with the real host

Until you do this, the app still prints QR codes pointing at the old default
and links to a privacy page that does not exist.

```bash
tools/build.sh appbundle --dart-define=JOIN_HOST=https://your-domain.vercel.app
```

`tools/build.sh` warns on every build where this is missing, so you cannot
ship it by accident. Once the domain is settled it is worth changing the
`defaultValue` in `lib/features/room/domain/join_link.dart` so the flag stops
being something you have to remember.

Give the same URL + `/privacy` to Play Console as the privacy policy link.
