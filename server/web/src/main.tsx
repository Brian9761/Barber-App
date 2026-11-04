import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
// Inter, self-hosted: only downloaded where the system font (SF Pro) isn't there.
import '@fontsource-variable/inter/index.css';
import './styles/tokens.css';
import './styles/base.css';
import './styles/components.css';
import './styles/pages.css';
import { App, ROUTER_FUTURE } from './App';
import { CatalogProvider } from './data/catalog';

const root = document.getElementById('root');
if (!root) throw new Error('The page has no #root element');

createRoot(root).render(
  <StrictMode>
    <BrowserRouter future={ROUTER_FUTURE}>
      <CatalogProvider>
        <App />
      </CatalogProvider>
    </BrowserRouter>
  </StrictMode>,
);
