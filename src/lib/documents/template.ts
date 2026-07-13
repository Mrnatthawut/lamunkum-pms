const variablePattern = /{{\s*([a-z_]+)\s*}}/g;

function thaiDate(value: unknown) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return String(value ?? "");
  return new Intl.DateTimeFormat("th-TH", { dateStyle: "long", timeZone: "Asia/Bangkok" }).format(new Date(`${value}T00:00:00+07:00`));
}

function formatValue(key: string, value: unknown) {
  if (["contract_date", "start_date", "end_date"].includes(key)) return thaiDate(value);
  if (["monthly_rent", "deposit", "advance_rent"].includes(key)) return new Intl.NumberFormat("th-TH", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value ?? 0));
  return String(value ?? "");
}

export function renderContractTemplate(template: string, snapshot: Record<string, unknown>) {
  return template.replace(variablePattern, (_match, key: string) => formatValue(key, snapshot[key]));
}

export function extractTemplateVariables(template: string) {
  return [...new Set([...template.matchAll(variablePattern)].map((match) => match[1]))];
}
