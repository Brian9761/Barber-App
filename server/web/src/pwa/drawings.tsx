// Small drawings of what to tap at each step of putting Izzy Clipz on the Home Screen: simple
// shapes in the site's own style, not pictures of anyone's screens. The step's words always
// say the same thing, so the drawings are decoration for screen readers.

import type { ReactNode } from 'react';

const BLUE = '#1f4fd8';
const LINE = '#d2d2d7';
const TEXT = '#1d1d1f';
const MUTED = '#6e6e73';

function Drawing({ children, label }: { children: ReactNode; label: string }) {
  return (
    <svg className="drawing" viewBox="0 0 280 120" width="280" height="120" aria-hidden="true" focusable="false" data-drawing={label}>
      {children}
    </svg>
  );
}

/** The ring around what to tap. */
function Ring({ x, y, width, height, radius }: { x: number; y: number; width: number; height: number; radius: number }) {
  return <rect x={x} y={y} width={width} height={height} rx={radius} fill="none" stroke={BLUE} strokeWidth="3" />;
}

/** A square with an arrow out of its top: the Share button. */
function ShareGlyph({ x, y, color = BLUE }: { x: number; y: number; color?: string }) {
  return (
    <g transform={`translate(${x} ${y})`} fill="none" stroke={color} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M-4 -3H-8V11H8V-3H4" />
      <path d="M0 5V-12M-4.5 -7.5L0 -12L4.5 -7.5" />
    </g>
  );
}

/** A screen with an arrow down into it: install. */
function InstallGlyph({ x, y, color = TEXT, phone = false }: { x: number; y: number; color?: string; phone?: boolean }) {
  return (
    <g transform={`translate(${x} ${y})`} fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      {phone ? <rect x="-7" y="-11" width="14" height="22" rx="3" /> : <path d="M-11 -9H11V7H-11Z M-5 11H5" />}
      <path d={phone ? 'M0 -5V4M-3.5 0.5L0 4L3.5 0.5' : 'M0 -5V3M-3.5 -0.5L0 3L3.5 -0.5'} />
    </g>
  );
}

function host(): string {
  return typeof window === 'undefined' ? 'izzy-clipz' : window.location.host;
}

function AddressText({ x, y, width }: { x: number; y: number; width: number }) {
  return (
    <text x={x} y={y} fontSize="14" fill={MUTED} textLength={Math.min(width, host().length * 7.2)} lengthAdjust="spacingAndGlyphs">
      {host()}
    </text>
  );
}

/** iPhone: the Share button in Safari's bar. */
export function ShareButtonDrawing() {
  return (
    <Drawing label="share">
      <rect x="12" y="34" width="256" height="56" rx="18" fill="#fff" stroke={LINE} />
      <path d="M38 52l-8 10 8 10" fill="none" stroke={MUTED} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
      <rect x="58" y="47" width="150" height="30" rx="15" fill="#f5f5f7" />
      <AddressText x={72} y={67} width={124} />
      <ShareGlyph x={238} y={62} />
      <Ring x={218} y={40} width={40} height={44} radius={14} />
    </Drawing>
  );
}

/** iPhone: "Add to Home Screen" in the list of things to do with the page. */
export function AddToHomeScreenDrawing() {
  return (
    <Drawing label="add-to-home-screen">
      <rect x="12" y="6" width="256" height="34" rx="10" fill="#fff" opacity="0.55" />
      <text x="28" y="28" fontSize="15" fill={MUTED} opacity="0.7">
        Add Bookmark
      </text>
      <rect x="12" y="44" width="256" height="44" rx="12" fill="#fff" />
      <text x="28" y="71" fontSize="16" fill={TEXT}>
        Add to Home Screen
      </text>
      <g transform="translate(238 66)" fill="none" stroke={TEXT} strokeWidth="2" strokeLinecap="round">
        <rect x="-10" y="-10" width="20" height="20" rx="5" />
        <path d="M0 -5V5M-5 0H5" />
      </g>
      <Ring x={9} y={41} width={262} height={50} radius={14} />
      <rect x="12" y="94" width="256" height="24" rx="8" fill="#fff" opacity="0.55" />
    </Drawing>
  );
}

/** iPhone: "Add", at the top right, with the app's icon and name under it. */
export function AddButtonDrawing() {
  return (
    <Drawing label="add">
      <rect x="12" y="10" width="256" height="100" rx="16" fill="#fff" />
      <text x="28" y="38" fontSize="15" fill={BLUE}>
        Cancel
      </text>
      <text x="252" y="38" fontSize="15" fontWeight="600" fill={BLUE} textAnchor="end">
        Add
      </text>
      {/* Round "Add" with room on both sides: the word is about 31 wide, ending at 252. */}
      <Ring x={211} y={18} width={52} height={30} radius={10} />
      <path d="M12 54H268" stroke={LINE} />
      <image href="/icon-192.png" x="28" y="64" width="36" height="36" />
      <text x="76" y="88" fontSize="16" fill={TEXT}>
        Izzy Clipz
      </text>
    </Drawing>
  );
}

/** Android: the menu, three dots at the right of Chrome's address bar. */
export function AndroidMenuDrawing() {
  return (
    <Drawing label="menu">
      <rect x="12" y="34" width="256" height="56" rx="18" fill="#fff" stroke={LINE} />
      <rect x="26" y="46" width="186" height="32" rx="16" fill="#f5f5f7" />
      <AddressText x={42} y={67} width={156} />
      <g fill={TEXT}>
        <circle cx="240" cy="53" r="2.6" />
        <circle cx="240" cy="62" r="2.6" />
        <circle cx="240" cy="71" r="2.6" />
      </g>
      <Ring x={222} y={40} width={36} height={44} radius={14} />
    </Drawing>
  );
}

/** Android: "Install app" in Chrome's menu. */
export function InstallAppDrawing() {
  return (
    <Drawing label="install-app">
      <rect x="40" y="4" width="200" height="112" rx="14" fill="#fff" />
      <text x="62" y="32" fontSize="15" fill={MUTED} opacity="0.75">
        New tab
      </text>
      <InstallGlyph x={70} y={64} phone />
      <text x="90" y="70" fontSize="16" fill={TEXT}>
        Install app
      </text>
      <Ring x={46} y={44} width={188} height={40} radius={12} />
      <text x="62" y="106" fontSize="15" fill={MUTED} opacity="0.75">
        Settings
      </text>
    </Drawing>
  );
}

/** Android and computers: the browser asks "Install app?", and Install says yes. */
export function InstallDialogDrawing() {
  return (
    <Drawing label="install">
      <rect x="22" y="6" width="236" height="108" rx="16" fill="#fff" />
      <text x="40" y="34" fontSize="16" fontWeight="600" fill={TEXT}>
        Install app?
      </text>
      <image href="/icon-192.png" x="40" y="46" width="28" height="28" />
      <text x="78" y="65" fontSize="15" fill={TEXT}>
        Izzy Clipz
      </text>
      <text x="132" y="100" fontSize="15" fill={BLUE} textAnchor="middle">
        Cancel
      </text>
      <rect x="182" y="82" width="62" height="28" rx="14" fill={BLUE} />
      <text x="213" y="101" fontSize="15" fontWeight="600" fill="#fff" textAnchor="middle">
        Install
      </text>
      <Ring x={177} y={77} width={72} height={38} radius={19} />
    </Drawing>
  );
}

/** Computers: the install button at the right end of Chrome's or Edge's address bar. */
export function AddressBarInstallDrawing() {
  return (
    <Drawing label="address-bar">
      <rect x="6" y="36" width="268" height="48" rx="24" fill="#fff" stroke={LINE} />
      <AddressText x={28} y={65} width={170} />
      <InstallGlyph x={246} y={60} />
      <Ring x={226} y={42} width={40} height={36} radius={18} />
    </Drawing>
  );
}
