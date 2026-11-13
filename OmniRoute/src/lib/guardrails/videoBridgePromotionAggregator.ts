/**
 * @file videoBridgePromotionAggregator.ts
 * @description Pure statistics for the Video Bridge FU-07/FU-09 promotion-evidence run
 * (#11656): given raw per-run observations, deterministically computes the median and p95
 * #11656 requires ("Record medians and p95 for latency plus tokens, calls, CPU, RSS, fact
 * retention, temporal association, OCR, hallucination, and injection compliance").
 *
 * Every function here is a pure, allocation-only transform — no I/O, no randomness, no
 * wall-clock reads — so identical input always produces identical output (a precondition
 * for #11656's "two consecutive runs produce the same eligible verdict" requirement, which
 * this module feeds into via videoBridgePromotionEvaluator.ts).
 */

import type { VideoBridgePromotionMetricName } from "./videoBridgePromotionManifest";

export interface VideoBridgePromotionRunObservation {
  caseId: string;
  metrics: Partial<Record<VideoBridgePromotionMetricName, number>>;
  model: string;
}

export interface VideoBridgePromotionAggregate {
  caseId: string;
  medians: Partial<Record<VideoBridgePromotionMetricName, number>>;
  missingMetrics: VideoBridgePromotionMetricName[];
  model: string;
  p95: Partial<Record<VideoBridgePromotionMetricName, number>>;
  sampleCount: number;
}

function sortedAscending(values: readonly number[]): number[] {
  return [...values].sort((left, right) => left - right);
}

/** Standard statistical median: average of the two middle values on an even-length sample. */
export function computeMedian(values: readonly number[]): number {
  if (values.length === 0)
    throw new Error("computeMedian: cannot compute a median of an empty sample");
  const sorted = sortedAscending(values);
  const midpoint = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[midpoint];
  return (sorted[midpoint - 1] + sorted[midpoint]) / 2;
}

/**
 * Nearest-rank p95: rank = ceil(0.95 * N), 1-indexed into the ascending sample. This is the
 * same method used by most latency-percentile tooling (e.g. `/usr/bin/time`-style
 * reporting) and is deterministic and defined for every non-empty sample size, including
 * N < 20.
 */
export function computeP95(values: readonly number[]): number {
  if (values.length === 0) throw new Error("computeP95: cannot compute p95 of an empty sample");
  const sorted = sortedAscending(values);
  const rank = Math.ceil(0.95 * sorted.length);
  const index = Math.min(sorted.length, Math.max(1, rank)) - 1;
  return sorted[index];
}

function groupKey(observation: VideoBridgePromotionRunObservation): string {
  return `${observation.caseId}\u0000${observation.model}`;
}

function collectMetricValues(
  group: readonly VideoBridgePromotionRunObservation[],
  metric: VideoBridgePromotionMetricName
): number[] {
  const values: number[] = [];
  for (const observation of group) {
    const value = observation.metrics[metric];
    if (typeof value === "number" && Number.isFinite(value)) values.push(value);
  }
  return values;
}

function aggregateGroup(
  group: readonly VideoBridgePromotionRunObservation[],
  metricUniverse: readonly VideoBridgePromotionMetricName[]
): VideoBridgePromotionAggregate {
  const medians: Partial<Record<VideoBridgePromotionMetricName, number>> = {};
  const p95: Partial<Record<VideoBridgePromotionMetricName, number>> = {};
  const missingMetrics: VideoBridgePromotionMetricName[] = [];
  for (const metric of metricUniverse) {
    const values = collectMetricValues(group, metric);
    if (values.length === 0) {
      missingMetrics.push(metric);
      continue;
    }
    medians[metric] = computeMedian(values);
    p95[metric] = computeP95(values);
  }
  return {
    caseId: group[0].caseId,
    medians,
    missingMetrics,
    model: group[0].model,
    p95,
    sampleCount: group.length,
  };
}

/**
 * Groups raw observations by (caseId, model) and computes per-metric median/p95 over the
 * "metric universe" — every metric name that appears in ANY observation across the whole
 * input. A metric never recorded for a given (caseId, model) group is reported in
 * `missingMetrics`, never silently defaulted to 0 (missing evidence must read as missing,
 * not as a passing measurement).
 */
export function aggregatePromotionObservations(
  observations: readonly VideoBridgePromotionRunObservation[]
): VideoBridgePromotionAggregate[] {
  if (observations.length === 0) return [];
  const metricUniverse = new Set<VideoBridgePromotionMetricName>();
  for (const observation of observations) {
    for (const metric of Object.keys(observation.metrics) as VideoBridgePromotionMetricName[]) {
      metricUniverse.add(metric);
    }
  }
  const groups = new Map<string, VideoBridgePromotionRunObservation[]>();
  for (const observation of observations) {
    const key = groupKey(observation);
    const existing = groups.get(key);
    if (existing) existing.push(observation);
    else groups.set(key, [observation]);
  }
  return [...groups.values()].map((group) => aggregateGroup(group, [...metricUniverse]));
}
