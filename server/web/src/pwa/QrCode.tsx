import { useMemo } from 'react';
import { encode } from 'uqr';

/**
 * A QR code for `text`, drawn in the page (uqr makes the pattern), so it's always the address
 * the site is open at. Black on white whatever the screen's colors, with a white margin, so
 * phone cameras read it.
 */
export function QrCode({ text, label, size = 200 }: { text: string; label: string; size?: number }) {
  const { modules, path } = useMemo(() => {
    const { data } = encode(text, { ecc: 'M', border: 2 });
    let d = '';
    data.forEach((row, y) =>
      row.forEach((dark, x) => {
        if (dark) d += `M${x} ${y}h1v1h-1z`;
      }),
    );
    return { modules: data.length, path: d };
  }, [text]);
  return (
    <svg
      className="qr-code"
      viewBox={`0 0 ${modules} ${modules}`}
      width={size}
      height={size}
      role="img"
      aria-label={label}
      shapeRendering="crispEdges"
      data-qr-text={text}
    >
      <rect width={modules} height={modules} fill="#fff" />
      <path d={path} fill="#000" />
    </svg>
  );
}
