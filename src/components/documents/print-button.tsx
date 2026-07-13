"use client";

import { Printer } from "lucide-react";

export function PrintButton() { return <button onClick={() => window.print()} className="print-hidden flex items-center gap-2 rounded-lg bg-teal-700 px-4 py-2 text-sm font-semibold text-white"><Printer size={17}/>พิมพ์สัญญา</button>; }
