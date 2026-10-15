# Iris website

React + Vite + TypeScript. Pages: `/` (home), `/support`, `/privacy-policy`.

```
npm install
npm run dev      # http://localhost:5173
npm run build    # writes dist/, with a copy of index.html in dist/support and dist/privacy-policy
```

Copy `dist/` to the web root. No server rewrite is needed: every route has its own folder, so
`try_files $uri $uri/ =404;` serves it.

`public/shots/` are 1080x2424 captures of the demo on a Pixel 9 emulator (the demo shows no real
server). Retake them with `adb exec-out screencap -p > name.png` after `adb shell pm clear` and
**Try the demo**. The privacy policy and support text live in `src/pages/`; keep them true to the app.
