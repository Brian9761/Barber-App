import { LOGO_ASPECT, LOGO_PATH, LOGO_VIEW_BOX } from '../assets/logo';

interface LogoProps {
  /** Its height in pixels (the width follows). A stylesheet may size it instead, by its height. */
  height: number;
  className?: string;
  /**
   * Its name for screen readers, only where it stands for the shop on its own: the nav's link to
   * Home ("Izzy Clipz"). Without one it's decoration, and screen readers skip it.
   */
  label?: string;
}

/**
 * The shop's logo as a vector, sharp at any size, drawn in the text color: white on the black and
 * ink bands, near-black on the white and light gray ones.
 */
export function Logo({ height, className, label }: LogoProps) {
  return (
    <svg
      className={className ? `logo ${className}` : 'logo'}
      viewBox={LOGO_VIEW_BOX}
      // Not rounded: a stylesheet that sets only the height keeps this exact shape.
      width={Number((height * LOGO_ASPECT).toFixed(2))}
      height={height}
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      <path fill="currentColor" fillRule="evenodd" d={LOGO_PATH} />
    </svg>
  );
}
