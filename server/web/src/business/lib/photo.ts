// A product photo as the server takes it: a JPEG of at most 4 MB. Whatever photo the
// owner picks (JPEG, PNG, HEIC where the browser can read it) is drawn again at a sensible
// size and saved as a JPEG in the browser, so nothing big is ever sent.

export const MAX_PHOTO_BYTES = 4 * 1024 * 1024;

export class PhotoProblem extends Error {}

function load(file: Blob): Promise<CanvasImageSource & { width: number; height: number }> {
  if (typeof createImageBitmap === 'function') return createImageBitmap(file);
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('unreadable'));
    };
    image.src = url;
  });
}

function toBlob(canvas: HTMLCanvasElement, quality: number): Promise<Blob | null> {
  return new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
}

/** The photo as a JPEG no larger than `maxSide` pixels on its longer side, and under 4 MB. */
export async function photoAsJpeg(file: Blob, maxSide = 1600): Promise<Blob> {
  if (!file.type.startsWith('image/')) throw new PhotoProblem("That file isn't a photo. Pick a photo, like a JPEG or PNG.");
  let image: CanvasImageSource & { width: number; height: number };
  try {
    image = await load(file);
  } catch {
    throw new PhotoProblem("That photo couldn't be opened in this browser. Try a JPEG or PNG photo.");
  }
  const scale = Math.min(1, maxSide / Math.max(image.width, image.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(image.width * scale));
  canvas.height = Math.max(1, Math.round(image.height * scale));
  const context = canvas.getContext('2d');
  if (!context) throw new PhotoProblem("This browser couldn't prepare the photo. Try another browser.");
  // A see-through PNG gets a white background, as a JPEG has none.
  context.fillStyle = '#ffffff';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  for (const quality of [0.86, 0.75, 0.6]) {
    const blob = await toBlob(canvas, quality);
    if (blob && blob.size <= MAX_PHOTO_BYTES) return blob;
  }
  throw new PhotoProblem('That photo is too big. Pick a smaller one.');
}
