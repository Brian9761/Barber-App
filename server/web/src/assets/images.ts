// The shop's storefront photo, converted to WebP. The six photos of clients' cuts were taken off
// until the shop has each person's written permission to show them (docs/legal/OWNER-CHECKLIST.md).

import storefront640 from './images/storefront-640.webp';
import storefront1000 from './images/storefront-1000.webp';
import type { PhotoSource } from '../components/ui';

export const STOREFRONT = {
  sources: [
    { src: storefront640, width: 640 },
    { src: storefront1000, width: 1000 },
  ] as PhotoSource[],
  width: 1000,
  height: 750,
  alt: "The Izzy Clipz storefront at 1919 Mission Ave, with the shop's sign over the windows",
};
