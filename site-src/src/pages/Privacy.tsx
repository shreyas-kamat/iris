export function Privacy() {
  return (
    <main className="wrap prose">
<h1>Privacy Policy</h1>
  <p className="meta">Effective 15 October 2026</p>

  <p className="lede">Iris is an app for talking to your own Hermes agent. It connects only to the server
  you point it at. We run no servers for Iris, so we never receive your conversations, your login or
  anything else you do in the app.</p>

  <h2>Who we are</h2>
  <p>Iris is published by <strong>Ashish Kamat (iFloTech)</strong> and developed by <strong>Shreyas Kamat</strong>.
  On the Apple App Store the app is offered under <strong>Daturo Solutions Pvt Ltd</strong>. For any question
  about this policy, write to <a href="mailto:shreyaskamat13@gmail.com">shreyaskamat13@gmail.com</a>.</p>

  <h2>The short version</h2>
  <ul>
    <li>Iris sends your messages to <strong>your</strong> Hermes server, and nowhere else.</li>
    <li>We collect <strong>no data</strong>. There is no account with us, no analytics, no advertising and no crash reporting in the app.</li>
    <li>Your passwords and access tokens stay in your phone’s secure keystore.</li>
    <li>We do not sell or share data, because we do not have any.</li>
  </ul>

  <h2>What the app stores on your device</h2>
  <dl>
    <dt>Server address and name</dt>
    <dd>The web address of your Hermes dashboard and the label you give it, so Iris can reconnect.</dd>
    <dt>Sign-in secrets</dt>
    <dd>Your dashboard username and password and, if your server sits behind Cloudflare Access, the service
    token you enter. These are kept in the secure storage of your phone (Android Keystore, or the iOS Keychain)
    and are read only at the moment a request needs them. They are not written to the app’s database or its logs.</dd>
    <dt>Settings</dt>
    <dd>Your choices in the app: appearance, the profile you last used, and which usage meters to show.</dd>
  </dl>
  <p>Conversations are loaded from your server while you read them and held in memory. Iris does not keep a
  copy of them in its own storage.</p>

  <h2>What the app sends, and to whom</h2>
  <p>When you use Iris it opens a connection to the server address you entered. Over that connection it
  sends your sign-in details, your messages and your commands, and it receives your conversations, the
  agent’s replies, and information such as the list of profiles and provider usage.</p>
  <p>That server is run by you or by someone you chose. What it does with the data, including which AI
  providers it forwards your messages to, is decided by that server’s own setup and by those providers’
  terms. Iris has no control over it and we have no access to it.</p>
  <p>If your server is published through Cloudflare, your traffic passes through Cloudflare under your own
  Cloudflare account and its terms. Iris sends the service token only over encrypted (HTTPS) connections.</p>
  <p>Files, photos and voice recordings you choose to send go only to your own Hermes server. Iris doesn’t keep the
  recordings. An image linked in a reply is fetched from its website only when you tap it.</p>
  <p>If you choose to trust a server that uses a self-signed certificate, Iris accepts that certificate for
  that one server only.</p>

  <h2>Permissions</h2>
  <p>Iris uses the internet to reach your server. On an iPhone, iOS also asks permission to connect to devices on
  your local network, which Iris uses only to reach the server address you entered. Iris asks for the microphone only when you
  tap the mic to dictate a message, and it reads a photo or file only when you pick one. Iris does not use your
  camera, location or contacts.</p>

  <h2>Links</h2>
  <p>A link in a conversation opens in your phone’s browser when you tap it. Those sites have their own
  privacy policies.</p>

  <h2>Backups</h2>
  <p>On Android, Iris switches backup and device-to-device transfer off, so your saved server addresses and settings
  are not copied to Google’s cloud backup or to a new phone. On an iPhone, a backup of your device (to iCloud or a
  computer) may include the app’s saved server address and settings, as it does for other apps; that is handled by
  Apple and is outside Iris. Sign-in secrets are stored so that they stay on the device they were entered on, and are
  not restored onto a different one, so you will be asked to sign in again.</p>

  <h2>Children</h2>
  <p>Iris is a tool for people who run their own server and is not directed at children. We do not
  knowingly collect information from anyone, including children.</p>

  <h2>Deleting your data</h2>
  <p>Because the data is on your phone and your own server, you are in control of it. Uninstalling Iris
  removes its saved server addresses and settings from your phone. On an iPhone, items in the Keychain can
  outlast an app’s deletion, so if you want a saved login to be unusable, change that password or revoke
  that service token on your server. Conversations live on your Hermes server and are deleted there.</p>

  <h2>Changes to this policy</h2>
  <p>If the way Iris handles data changes, we will update this page and its effective date before the new
  version is released.</p>

  <h2>Contact</h2>
  <p>Questions or requests: <a href="mailto:shreyaskamat13@gmail.com">shreyaskamat13@gmail.com</a>.</p>
    </main>
  );
}
