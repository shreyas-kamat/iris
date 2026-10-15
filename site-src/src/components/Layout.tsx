import { Link, NavLink, Outlet } from 'react-router-dom';

export function Brand() {
  return (
    <Link className="brand" to="/" aria-label="Iris home">
      <img className="mark" src="/logo.png" alt="" width={32} height={32} />
      Iris
    </Link>
  );
}

export function Layout() {
  return (
    <>
      <header className="top">
        <Brand />
        <nav aria-label="Main">
          <NavLink to="/support">Support</NavLink>
          <NavLink to="/privacy-policy">Privacy</NavLink>
          <a href="https://github.com/shreyas-kamat/iris">GitHub</a>
        </nav>
      </header>
      <Outlet />
      <footer className="foot">
        <div className="wrap">
          <p>&copy; 2026 Shreyas Kamat.</p>
          <p>
            <Link to="/support">Support</Link> &middot; <Link to="/privacy-policy">Privacy Policy</Link>
          </p>
        </div>
      </footer>
    </>
  );
}
