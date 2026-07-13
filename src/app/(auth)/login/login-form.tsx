"use client";

import { useActionState } from "react";
import { LoaderCircle, LogIn } from "lucide-react";
import { loginAction } from "./actions";
import type { AuthActionState } from "@/features/auth/schemas";

const initialState: AuthActionState = {};
export function LoginForm() {
  const [state, action, pending] = useActionState(loginAction, initialState);
  return <form action={action} className="space-y-5" noValidate>
    <div><label htmlFor="email" className="mb-1.5 block text-sm font-medium">อีเมล</label><input id="email" name="email" type="email" autoComplete="email" required className="w-full rounded-lg border border-slate-300 bg-transparent px-3 py-2.5 outline-none focus:border-teal-600 focus:ring-2 focus:ring-teal-100" placeholder="owner@example.com"/><p className="mt-1 text-sm text-red-600">{state.fieldErrors?.email?.[0]}</p></div>
    <div><label htmlFor="password" className="mb-1.5 block text-sm font-medium">รหัสผ่าน</label><input id="password" name="password" type="password" autoComplete="current-password" required className="w-full rounded-lg border border-slate-300 bg-transparent px-3 py-2.5 outline-none focus:border-teal-600 focus:ring-2 focus:ring-teal-100"/><p className="mt-1 text-sm text-red-600">{state.fieldErrors?.password?.[0]}</p></div>
    {state.error && <div role="alert" className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{state.error}</div>}
    <button disabled={pending} className="flex w-full items-center justify-center gap-2 rounded-lg bg-teal-700 px-4 py-2.5 font-semibold text-white hover:bg-teal-800 disabled:opacity-60">{pending?<LoaderCircle className="animate-spin" size={18}/>:<LogIn size={18}/>}เข้าสู่ระบบ</button>
  </form>;
}
