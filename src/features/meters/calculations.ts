import Decimal from "decimal.js";

export interface RateTier { fromUnit: string; toUnit: string | null; pricePerUnit: string }

export function calculateUsage(previous: string, current: string, meterReplaced = false): string {
  const before = new Decimal(previous);
  const after = new Decimal(current);
  if (before.isNegative() || after.isNegative()) throw new Error("METER_READING_NEGATIVE");
  if (after.lessThan(before) && !meterReplaced) throw new Error("METER_READING_DECREASED");
  return (meterReplaced ? after : after.minus(before)).toFixed(3);
}

export function calculateTieredCharge(units: string, tiers: RateTier[], minimum = "0"): string {
  const usage = new Decimal(units);
  if (usage.isNegative()) throw new Error("USAGE_NEGATIVE");
  let total = new Decimal(0);
  for (const tier of tiers) {
    const start = new Decimal(tier.fromUnit);
    const end = tier.toUnit === null ? usage : Decimal.min(usage, tier.toUnit);
    const tierUnits = Decimal.max(0, end.minus(start));
    total = total.plus(tierUnits.times(tier.pricePerUnit));
  }
  return Decimal.max(total, minimum).toFixed(2);
}
