import Decimal from "decimal.js";

export function validateAllocations(paymentAmount: string, allocations: ReadonlyArray<{ invoiceBalance: string; amount: string }>) {
  let allocated = new Decimal(0);
  for (const allocation of allocations) {
    if (new Decimal(allocation.amount).greaterThan(allocation.invoiceBalance)) throw new Error("ALLOCATION_EXCEEDS_INVOICE_BALANCE");
    allocated = allocated.plus(allocation.amount);
  }
  if (allocated.greaterThan(paymentAmount)) throw new Error("ALLOCATION_EXCEEDS_PAYMENT");
  return { allocated: allocated.toFixed(2), credit: new Decimal(paymentAmount).minus(allocated).toFixed(2) };
}
