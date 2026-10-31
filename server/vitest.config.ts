import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
    pool: 'forks',
    testTimeout: 20_000,
    hookTimeout: 60_000,
    // Each file starts its own PGlite (about 100 MB of WASM heap); keep a few at a time.
    maxWorkers: 4,
  },
});
