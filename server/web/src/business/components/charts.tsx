// Analytics' charts, small and hand-written in SVG (no chart library): daily sales as
// stacked columns, a one-whole-in-parts bar for the sales split, and horizontal bars for
// rankings. Each says what it shows to screen readers, every column can be reached with
// the keyboard and shows its numbers when picked, and each has a table alternative
// ("Show as table"). Colors (validated for color-blind readers, in a fixed order):
// services blue, products orange, other aqua, fees yellow; identity never rests on color
// alone (a legend, and the numbers).

import { useCallback, useId, useState, type ReactNode } from 'react';
import { money } from '../../lib/format';
import { compactMoney, moneyWithCommas } from '../lib/money';
import { seriesLabel, seriesTick } from '../lib/periods';
import type { SeriesEntry } from '../types';

export const SERIES = {
  services: { label: 'Services', color: '#1f4fd8' },
  products: { label: 'Products', color: '#eb6834' },
  other: { label: 'Other', color: '#1baf7a' },
  fees: { label: 'No-show & late fees', color: '#eda100' },
  otherAndFees: { label: 'Other & fees', color: '#1baf7a' },
} as const;

/** "Show as table" / "Show as chart": every chart's table alternative. */
export function ChartFrame({ title, table, children, testId }: { title: string; table: ReactNode; children: ReactNode; testId?: string }) {
  const [asTable, setAsTable] = useState(false);
  return (
    <div className="biz-chart" data-testid={testId}>
      {asTable ? table : children}
      <button type="button" className="text-button biz-chart__toggle" aria-pressed={asTable} onClick={() => setAsTable(!asTable)}>
        {asTable ? `Show ${title} as a chart` : `Show ${title} as a table`}
      </button>
    </div>
  );
}

export function Legend({ items }: { items: { label: string; color: string; value?: string }[] }) {
  return (
    <ul className="biz-legend" aria-label="Legend">
      {items.map((item) => (
        <li key={item.label} className="biz-legend__item">
          <span className="biz-legend__swatch" style={{ background: item.color }} aria-hidden="true" />
          <span>{item.label}</span>
          {item.value ? <span className="biz-legend__value">{item.value}</span> : null}
        </li>
      ))}
    </ul>
  );
}

/** Round numbers for the axis: 0, then steps of 1, 2 or 5 × a power of ten, reaching past `max`. */
export function niceTicks(max: number, count = 4): number[] {
  if (max <= 0) return [0];
  const raw = max / count;
  const power = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 5, 10].map((m) => m * power).find((s) => s >= raw) ?? raw;
  const ticks: number[] = [];
  for (let value = 0; value < max + step * 0.999; value += step) ticks.push(Math.round(value));
  return ticks;
}

/** A column's top segment: rounded 4px corners at the top, square at the base. */
function topRounded(x: number, y: number, width: number, height: number, radius: number): string {
  const r = Math.min(radius, width / 2, height);
  return `M${x},${y + height} V${y + r} Q${x},${y} ${x + r},${y} H${x + width - r} Q${x + width},${y} ${x + width},${y + r} V${y + height} Z`;
}

interface Stack {
  services: number;
  products: number;
  otherAndFees: number;
}

function stackOf(entry: SeriesEntry): Stack {
  return { services: entry.servicesCents, products: entry.productsCents, otherAndFees: entry.otherCents + entry.feesCents };
}

/** What a column says when picked, and to screen readers. */
export function columnDescription(entry: SeriesEntry): string {
  const s = stackOf(entry);
  return `${seriesLabel(entry.date)}: ${moneyWithCommas(entry.salesCents)}. Services ${money(s.services)}, products ${money(s.products)}, other and fees ${money(s.otherAndFees)}.`;
}

const HEIGHT = 240;
const PAD = { top: 12, right: 8, bottom: 28, left: 52 };

/** The width an element has on screen, so a chart draws at its real size (its text never shrinks). */
function useWidth(fallback: number): [(element: HTMLElement | null) => void, number] {
  const [width, setWidth] = useState(fallback);
  const [observer] = useState(() =>
    typeof ResizeObserver === 'undefined'
      ? null
      : new ResizeObserver((entries) => {
          const box = entries[0]?.contentRect.width;
          if (box && box > 0) setWidth(Math.round(box));
        }),
  );
  const ref = useCallback(
    (element: HTMLElement | null) => {
      observer?.disconnect();
      if (element) {
        observer?.observe(element);
        const box = element.getBoundingClientRect().width;
        if (box > 0) setWidth(Math.round(box));
      }
    },
    [observer],
  );
  return [ref, width];
}

/**
 * Daily sales (by month for a year): stacked columns, services at the base, then products,
 * then other and fees, with a 2px gap between segments. Picking a column (click, tap, Enter
 * or Space) shows its numbers above the chart.
 */
export function DailyChart({ series }: { series: SeriesEntry[] }) {
  const [picked, setPicked] = useState<number | null>(null);
  const titleId = useId();
  const [measure, width] = useWidth(720);
  const plotW = Math.max(120, width - PAD.left - PAD.right);
  const plotH = HEIGHT - PAD.top - PAD.bottom;
  const max = Math.max(...series.map((e) => e.salesCents), 0);
  const ticks = niceTicks(max);
  const top = ticks[ticks.length - 1] || 1;
  const band = plotW / Math.max(series.length, 1);
  const barW = Math.max(3, Math.min(24, band * 0.62));
  const y = (cents: number) => PAD.top + plotH - (cents / top) * plotH;
  // Labels that fit: about one every 40 pixels.
  const every = Math.max(1, Math.ceil(40 / band));
  const total = series.reduce((sum, e) => sum + e.salesCents, 0);
  const pickedEntry = picked !== null ? series[picked] : undefined;
  const best = series.reduce<SeriesEntry | null>((b, e) => (b === null || e.salesCents > b.salesCents ? e : b), null);

  return (
    <div className="biz-daily" ref={measure}>
      <p className="biz-daily__picked" aria-live="polite" data-testid="daily-picked">
        {pickedEntry
          ? columnDescription(pickedEntry)
          : best && best.salesCents > 0
            ? `Best: ${seriesLabel(best.date)}, ${moneyWithCommas(best.salesCents)}. Pick a column to see its numbers.`
            : 'Pick a column to see its numbers.'}
      </p>
      <svg
        className="biz-daily__svg"
        width="100%"
        height={HEIGHT}
        viewBox={`0 0 ${PAD.left + plotW + PAD.right} ${HEIGHT}`}
        role="group"
        aria-labelledby={titleId}
      >
        <title id={titleId}>{`Sales by ${series[0]?.date.length === 7 ? 'month' : 'day'}: ${moneyWithCommas(total)} in all`}</title>
        {ticks.map((tick) => (
          <g key={tick} aria-hidden="true">
            <line x1={PAD.left} x2={PAD.left + plotW} y1={y(tick)} y2={y(tick)} className="biz-grid" />
            <text x={PAD.left - 8} y={y(tick) + 4} textAnchor="end" className="biz-axis">
              {compactMoney(tick)}
            </text>
          </g>
        ))}
        {series.map((entry, i) => {
          const s = stackOf(entry);
          const x = PAD.left + band * i + (band - barW) / 2;
          const parts = [
            { key: 'services', value: s.services, color: SERIES.services.color },
            { key: 'products', value: s.products, color: SERIES.products.color },
            { key: 'other', value: s.otherAndFees, color: SERIES.otherAndFees.color },
          ].filter((p) => p.value > 0);
          let base = 0;
          const dim = picked !== null && picked !== i;
          return (
            <g
              key={entry.date}
              role="button"
              tabIndex={0}
              aria-label={columnDescription(entry)}
              aria-pressed={picked === i}
              className={`biz-col${dim ? ' is-dim' : ''}`}
              onClick={() => setPicked(picked === i ? null : i)}
              onKeyDown={(event) => {
                if (event.key === 'Enter' || event.key === ' ') {
                  event.preventDefault();
                  setPicked(picked === i ? null : i);
                }
              }}
              onMouseEnter={() => setPicked(i)}
            >
              <rect x={PAD.left + band * i} y={PAD.top} width={band} height={plotH} className="biz-col__hit" />
              {parts.map((part, index) => {
                const y0 = y(base);
                base += part.value;
                const y1 = y(base);
                // A 2px gap in the surface color between segments.
                const gap = index > 0 ? 2 : 0;
                const height = Math.max(0, y0 - y1 - gap);
                if (height <= 0) return null;
                return index === parts.length - 1 ? (
                  <path key={part.key} d={topRounded(x, y1, barW, height, 4)} fill={part.color} />
                ) : (
                  <rect key={part.key} x={x} y={y1} width={barW} height={height} fill={part.color} />
                );
              })}
              {i % every === 0 ? (
                <text x={PAD.left + band * i + band / 2} y={HEIGHT - 8} textAnchor="middle" className="biz-axis" aria-hidden="true">
                  {seriesTick(entry.date)}
                </text>
              ) : null}
            </g>
          );
        })}
        <line x1={PAD.left} x2={PAD.left + plotW} y1={y(0)} y2={y(0)} className="biz-baseline" aria-hidden="true" />
      </svg>
      <Legend items={[SERIES.services, SERIES.products, SERIES.otherAndFees]} />
    </div>
  );
}

export function DailyTable({ series }: { series: SeriesEntry[] }) {
  return (
    <div className="biz-table-wrap" tabIndex={0} role="region" aria-label="Table">
      <table className="biz-table">
        <caption className="visually-hidden">Sales by {series[0]?.date.length === 7 ? 'month' : 'day'}</caption>
        <thead>
          <tr>
            <th scope="col">{series[0]?.date.length === 7 ? 'Month' : 'Day'}</th>
            <th scope="col">Services</th>
            <th scope="col">Products</th>
            <th scope="col">Other & fees</th>
            <th scope="col">Sales</th>
          </tr>
        </thead>
        <tbody>
          {series.map((entry) => (
            <tr key={entry.date}>
              <th scope="row">{seriesLabel(entry.date)}</th>
              <td>{money(entry.servicesCents)}</td>
              <td>{money(entry.productsCents)}</td>
              <td>{money(entry.otherCents + entry.feesCents)}</td>
              <td>{moneyWithCommas(entry.salesCents)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** One whole split into its parts (the sales split): widths by share, a 2px gap between parts, nothing for a part at zero. */
export function SplitBar({ parts, label }: { parts: { label: string; value: number; color: string }[]; label: string }) {
  const total = parts.reduce((sum, p) => sum + p.value, 0);
  if (total <= 0) return <div className="biz-split biz-split--empty" aria-hidden="true" />;
  let x = 0;
  const shown = parts.filter((p) => p.value > 0);
  return (
    <svg className="biz-split" viewBox="0 0 100 10" preserveAspectRatio="none" role="img" aria-label={label}>
      {shown.map((part, index) => {
        const width = (part.value / total) * 100;
        const rect = (
          <rect
            key={part.label}
            x={x + (index > 0 ? 0.4 : 0)}
            y={0}
            width={Math.max(0, width - (index > 0 ? 0.4 : 0))}
            height={10}
            rx={1.2}
            fill={part.color}
          />
        );
        x += width;
        return rect;
      })}
    </svg>
  );
}

/** A horizontal bar for one row of a ranking: its share of the largest value. */
export function RowBar({ value, max, highlight = false }: { value: number; max: number; highlight?: boolean }) {
  const share = max > 0 ? Math.max(0, Math.min(1, value / max)) : 0;
  return (
    <svg className={`biz-rowbar${highlight ? ' is-highlight' : ''}`} viewBox="0 0 100 8" preserveAspectRatio="none" aria-hidden="true">
      <rect x={0} y={0} width={100} height={8} rx={4} className="biz-rowbar__track" />
      {share > 0 ? <rect x={0} y={0} width={Math.max(2, share * 100)} height={8} rx={4} className="biz-rowbar__fill" /> : null}
    </svg>
  );
}

/** A small medal for the top three: gold, silver and bronze, with the place for screen readers. */
export function Medal({ place }: { place: 1 | 2 | 3 }) {
  const colors = { 1: '#c99a06', 2: '#8e9399', 3: '#a8652e' } as const;
  const words = { 1: 'First place', 2: 'Second place', 3: 'Third place' } as const;
  return (
    <svg className="biz-medal" viewBox="0 0 24 24" width="30" height="30" role="img" aria-label={words[place]}>
      <path d="M7 2h4l2 6H9zM13 2h4l-2 6h-4z" fill={colors[place]} opacity="0.65" />
      <circle cx="12" cy="15" r="7" fill={colors[place]} />
      <text x="12" y="18.6" textAnchor="middle" fontSize="9.5" fontWeight="700" fill="#fff">
        {place}
      </text>
    </svg>
  );
}

/** The top barber's crown. */
export function Crown() {
  return (
    <svg className="biz-crown" viewBox="0 0 24 24" width="28" height="28" aria-hidden="true">
      <path d="M3 8l4.5 4L12 5l4.5 7L21 8l-2 11H5z" fill="#c99a06" />
      <rect x="5" y="19.5" width="14" height="2" rx="1" fill="#c99a06" />
    </svg>
  );
}
