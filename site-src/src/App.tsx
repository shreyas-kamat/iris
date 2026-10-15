import { Route, Routes, useLocation } from 'react-router-dom';
import { useEffect } from 'react';
import { Layout } from './components/Layout';
import { Home } from './pages/Home';
import { Support } from './pages/Support';
import { Privacy } from './pages/Privacy';
import { NotFound } from './pages/NotFound';

const titles: Record<string, string> = {
  '/': 'Iris',
  '/support': 'Iris Support',
  '/privacy-policy': 'Iris Privacy Policy',
};

export function App() {
  const { pathname } = useLocation();
  useEffect(() => {
    document.title = titles[pathname.replace(/\/$/, '') || '/'] ?? 'Iris';
    window.scrollTo(0, 0);
  }, [pathname]);

  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Home />} />
        <Route path="support" element={<Support />} />
        <Route path="privacy-policy" element={<Privacy />} />
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  );
}
