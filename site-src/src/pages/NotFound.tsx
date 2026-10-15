import { Link } from 'react-router-dom';

export function NotFound() {
  return (
    <main className="wrap prose">
      <h1>Page not found</h1>
      <p>
        <Link to="/">Back to Iris</Link>
      </p>
    </main>
  );
}
