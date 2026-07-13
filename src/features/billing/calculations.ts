import Decimal from "decimal.js";

export interface InvoiceLine { quantity: string; unitPrice: string; discount?: string; taxRate?: string }

export function calculateInvoice(lines: InvoiceLine[], carriedBalance = "0") {
  let subtotal = new Decimal(0);
  let discount = new Decimal(0);
  let tax = new Decimal(0);
  for (const line of lines) {
    const base = new Decimal(line.quantity).times(line.unitPrice);
    const lineDiscount = new Decimal(line.discount ?? 0);
    const taxable = base.minus(lineDiscount);
    if (taxable.isNegative()) throw new Error("DISCOUNT_EXCEEDS_LINE_TOTAL");
    subtotal = subtotal.plus(base);
    discount = discount.plus(lineDiscount);
    tax = tax.plus(taxable.times(line.taxRate ?? 0).dividedBy(100));
  }
  return { subtotal: subtotal.toFixed(2), discount: discount.toFixed(2), tax: tax.toFixed(2), total: subtotal.minus(discount).plus(tax).plus(carriedBalance).toFixed(2) };
}

export function calculateLateFee(balance: string, daysLate: number, rule: { type: "fixed" | "daily" | "percent"; value: string; graceDays: number; maximum?: string }) {
  const chargeableDays = Math.max(0, daysLate - rule.graceDays);
  if (chargeableDays === 0) return "0.00";
  let fee = rule.type === "fixed" ? new Decimal(rule.value) : rule.type === "daily" ? new Decimal(rule.value).times(chargeableDays) : new Decimal(balance).times(rule.value).dividedBy(100);
  if (rule.maximum) fee = Decimal.min(fee, rule.maximum);
  return fee.toFixed(2);
}
