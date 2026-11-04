import { Route, Routes } from 'react-router-dom';

/** The site's pages. */
export function App() {
  return (
    <Routes>
      <Route path="*" element={<main><h1>Izzy Clipz Barbershop</h1></main>} />
    </Routes>
  );
}
