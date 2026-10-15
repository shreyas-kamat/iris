import { Phone } from '../components/Phone';

const features = [
  { title: 'Talks only to your server', body: 'Iris connects straight to the Hermes dashboard you run. We operate no servers, so nothing passes through us.' },
  { title: 'Every conversation, searchable', body: 'Pick up any chat from any channel, search them, archive and rename. Replies stream in as they are written.' },
  { title: 'See what the agent is doing', body: 'Tool calls and thought process appear inline, so you know what ran and what it changed.' },
  { title: 'Profiles and usage at a glance', body: 'Switch between agent profiles and watch how much of your provider quota is left, right on the home screen.' },
  { title: 'Reaches your server anywhere', body: 'Same Wi-Fi, Tailscale or Cloudflare Access. Reconnects by itself when you change networks.' },
  { title: 'Free and open source', body: 'Apache-2.0, no accounts, no analytics, no ads. Read every line on GitHub.' },
];

export function Home() {
  return (
    <main>
      <section className="hero wrap">
        <div className="hero-copy">
          <p className="eyebrow">For Hermes Agent</p>
          <h1>
            A calm phone app for <em>your own</em> agent.
          </h1>
          <p className="lede">
            Iris talks directly to the Hermes dashboard on your hardware. Read, search and continue
            your conversations from anywhere. Nothing goes through anyone else.
          </p>
          <div className="cta">
            {/* Replace with the store links once the listings are live. */}
            <a className="button" href="#try">Try the demo</a>
            <a className="button ghost" href="https://github.com/shreyas-kamat/iris">View source</a>
          </div>
        </div>
        <div className="hero-shots">
          <Phone className="tilt-l" src="/shots/demo-home.png" alt="Iris home screen showing four conversations, a usage meter and a search box" priority />
          <Phone className="tilt-r" src="/shots/demo-chat-caddy.png" alt="A conversation where Iris answers when a certificate renews" priority />
        </div>
      </section>

      <section className="wrap section" aria-labelledby="features">
        <h2 id="features">What it does</h2>
        <ul className="features">
          {features.map((f) => (
            <li key={f.title}>
              <h3>{f.title}</h3>
              <p>{f.body}</p>
            </li>
          ))}
        </ul>
      </section>

      <section className="wrap section" aria-labelledby="look">
        <h2 id="look">A closer look</h2>
        <div className="gallery">
          <figure>
            <Phone src="/shots/welcome.png" alt="Connection screen offering Same Wi-Fi, Tailscale, Cloudflare and a demo" />
            <figcaption>Connect the way your server is reachable.</figcaption>
          </figure>
          <figure>
            <Phone src="/shots/demo-chat-1.png" alt="A conversation showing a tool call and the agent's reply" />
            <figcaption>Tool calls shown as they run.</figcaption>
          </figure>
          <figure>
            <Phone src="/shots/demo-profiles.png" alt="Profile picker listing default and homelab" />
            <figcaption>Separate profiles, memory and models.</figcaption>
          </figure>
          <figure>
            <Phone src="/shots/demo-settings.png" alt="Settings with skin, brightness and default model" />
            <figcaption>Skins that follow your Hermes web UI.</figcaption>
          </figure>
          <figure>
            <Phone src="/shots/demo-home-dark.png" alt="Home screen in dark mode" />
            <figcaption>Light and dark.</figcaption>
          </figure>
          <figure>
            <Phone src="/shots/demo-chat-morning.png" alt="A morning summary conversation" />
            <figcaption>Summaries from your scheduled jobs.</figcaption>
          </figure>
        </div>
      </section>

      <section className="wrap section try" id="try" aria-labelledby="demo">
        <h2 id="demo">No server yet?</h2>
        <p>
          Open Iris and choose <strong>Try the demo</strong> on the first screen. It shows sample
          conversations and needs no server, no account and no network.
        </p>
      </section>
    </main>
  );
}
