// The app's own photos (IzzyClipz/Resources/Assets.xcassets), converted to WebP.

import gallery1At400 from './images/gallery-1-400.webp';
import gallery1At750 from './images/gallery-1-750.webp';
import gallery2At400 from './images/gallery-2-400.webp';
import gallery2At750 from './images/gallery-2-750.webp';
import gallery3At400 from './images/gallery-3-400.webp';
import gallery3At750 from './images/gallery-3-750.webp';
import gallery4At400 from './images/gallery-4-400.webp';
import gallery4At750 from './images/gallery-4-750.webp';
import gallery5At400 from './images/gallery-5-400.webp';
import gallery5At750 from './images/gallery-5-750.webp';
import gallery6At400 from './images/gallery-6-400.webp';
import gallery6At750 from './images/gallery-6-750.webp';
import logo600 from './images/logo-600.webp';
import mascotHead from './images/mascot-head-128.webp';
import storefront640 from './images/storefront-640.webp';
import storefront1000 from './images/storefront-1000.webp';
import type { PhotoSource } from '../components/ui';

export interface GalleryPhoto {
  sources: PhotoSource[];
  /** The app's caption for the cut. */
  caption: string;
  width: number;
  height: number;
}

const portrait = (small: string, large: string, caption: string): GalleryPhoto => ({
  sources: [
    { src: small, width: 400 },
    { src: large, width: 750 },
  ],
  caption,
  width: 750,
  height: 1000,
});

/** The six cuts, the textured crop first, as on the app's Home. */
export const GALLERY: GalleryPhoto[] = [
  portrait(gallery6At400, gallery6At750, 'Textured crop with a fade'),
  portrait(gallery1At400, gallery1At750, 'Curly top with a taper fade'),
  portrait(gallery2At400, gallery2At750, 'Blue color with a fade'),
  portrait(gallery3At400, gallery3At750, 'Fade with a full, shaped beard'),
  portrait(gallery4At400, gallery4At750, 'Short fade with a lined-up beard'),
  portrait(gallery5At400, gallery5At750, 'Classic cut with a groomed beard'),
];

export const STOREFRONT = {
  sources: [
    { src: storefront640, width: 640 },
    { src: storefront1000, width: 1000 },
  ] as PhotoSource[],
  width: 1000,
  height: 750,
  alt: "The Izzy Clipz storefront at 1919 Mission Ave, with the shop's sign over the windows",
};

/** The full logo (mascot and wordmark), transparent: it always sits on a white sticker. */
export const LOGO = { src: logo600, width: 600, height: 477 };

/** The mascot's head, for the round sticker in the nav. */
export const MASCOT_HEAD = mascotHead;
