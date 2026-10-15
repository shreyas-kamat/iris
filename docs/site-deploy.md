# Privacy policy and support pages

Static files in `site/`, to be served at `https://iris.shreyaskamat.in/`:

| URL | File |
|---|---|
| `/` | `site/index.html` |
| `/privacy-policy` | `site/privacy-policy/index.html` |
| `/support` | `site/support/index.html` |

Copy the contents of `site/` to the web root on the VM. With nginx, the directory form works with
`try_files $uri $uri/ =404;` (a request for `/support` redirects to `/support/`). Give those two URLs
to Play Console (Privacy policy, and the support contact) and to App Store Connect (Privacy Policy
URL, Support URL).

The pages must stay true to the app. Update `privacy-policy/index.html` and its effective date
whenever the app starts to store something new, adds analytics or crash reporting, or talks to any
server other than the one the user enters.
