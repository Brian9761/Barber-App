import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { LOGO_PATH, LOGO_VIEW_BOX } from '../assets/logo';
import { Logo } from './Logo';

describe('Logo', () => {
  it('draws the shop’s logo as one path in the text color, its width following its height', () => {
    const { container } = render(<Logo height={48} className="footer-logo" />);
    const svg = container.querySelector('svg')!;
    expect(svg.getAttribute('class')).toBe('logo footer-logo');
    expect(svg.getAttribute('viewBox')).toBe(LOGO_VIEW_BOX);
    expect(svg.getAttribute('height')).toBe('48');
    // 1512 × 1650 in the tracing: 48 × 1512 / 1650 = 43.985…
    expect(svg.getAttribute('width')).toBe('43.99');
    const paths = svg.querySelectorAll('path');
    expect(paths).toHaveLength(1);
    expect(paths[0]!.getAttribute('fill')).toBe('currentColor');
    expect(paths[0]!.getAttribute('fill-rule')).toBe('evenodd');
    expect(paths[0]!.getAttribute('d')).toBe(LOGO_PATH);
  });

  it('is decoration that screen readers skip unless it has a name', () => {
    const { container } = render(<Logo height={120} />);
    const svg = container.querySelector('svg')!;
    expect(svg.getAttribute('aria-hidden')).toBe('true');
    expect(svg.hasAttribute('role')).toBe(false);
    expect(svg.hasAttribute('aria-label')).toBe(false);
    expect(screen.queryByRole('img')).toBeNull();
  });

  it('is an image named “Izzy Clipz” where it stands for the shop', () => {
    render(<Logo height={38} label="Izzy Clipz" />);
    const logo = screen.getByRole('img', { name: 'Izzy Clipz' });
    expect(logo.hasAttribute('aria-hidden')).toBe(false);
  });

  it('is the whole tracing: every shape closed, nothing but path data', () => {
    expect(LOGO_VIEW_BOX).toBe('42 42 1512 1650');
    expect(LOGO_PATH.startsWith('M')).toBe(true);
    expect(LOGO_PATH.match(/M/g)).toHaveLength(LOGO_PATH.match(/Z/g)!.length);
    expect(LOGO_PATH).toMatch(/^[MCLZ0-9., -]+$/);
  });
});
