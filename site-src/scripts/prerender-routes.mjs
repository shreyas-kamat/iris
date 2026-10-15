// A static host serves one file per URL. The app is a single page, so copy the built
// index.html to each route's folder: /support and /privacy-policy then work with
// `try_files $uri $uri/ =404;`, as the store listings need, with no server rewrite.
import { copyFileSync, mkdirSync } from 'node:fs';

for (const route of ['support', 'privacy-policy']) {
  mkdirSync(`dist/${route}`, { recursive: true });
  copyFileSync('dist/index.html', `dist/${route}/index.html`);
}
