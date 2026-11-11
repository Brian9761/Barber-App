import { useState } from 'react';
import { useUpdate } from './updates';

/**
 * "A new version is ready · Reload": a quiet bar at the bottom of the screen, never a reload
 * out of the blue. Its place is always there (empty until then), so screen readers hear it
 * when it appears.
 */
export function UpdateBar() {
  const apply = useUpdate();
  const [reloading, setReloading] = useState(false);
  return (
    <div className="update-bar" aria-live="polite" aria-atomic="true" data-testid="update-bar">
      {apply ? (
        <p className="update-bar__inner">
          A new version is ready
          <span aria-hidden="true"> · </span>
          <button
            type="button"
            className="update-bar__reload"
            disabled={reloading}
            onClick={() => {
              setReloading(true);
              apply();
            }}
          >
            {reloading ? 'Reloading…' : 'Reload'}
          </button>
        </p>
      ) : null}
    </div>
  );
}
