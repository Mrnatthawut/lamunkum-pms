import Decimal from "decimal.js";

export type Money = Readonly<{ amount: string; currency: "THB" }>;
export const money = (amount: Decimal.Value): Money => ({ amount: new Decimal(amount).toFixed(2), currency: "THB" });
export const addMoney = (...values: Money[]): Money => money(values.reduce((sum, item) => sum.plus(item.amount), new Decimal(0)));
export const subtractMoney = (left: Money, right: Money): Money => money(new Decimal(left.amount).minus(right.amount));
export const formatTHB = (value: Money) => new Intl.NumberFormat("th-TH", { style: "currency", currency: value.currency }).format(new Decimal(value.amount).toNumber());
