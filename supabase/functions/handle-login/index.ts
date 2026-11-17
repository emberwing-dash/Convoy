// supabase/functions/handle-login/index.ts
//
// "Already have an account?" (MVP): log back in with an @handle and a 4-digit PIN.
//
//   1. public.handle_login_check(handle, pin) — service-role only — finds the account, sets the
//      PIN on its first login or checks it, and locks a handle after 5 wrong tries in 15 minutes.
//   2. On success the account gets a fresh random password (and an internal, never-mailed login
//      address if it has no email yet), which is returned once so the app can sign in with it.
//      Each login rotates the password, so a leaked one stops working at the next login.
//
// Public on purpose (verify_jwt off): a rider who lost their session has no token. The service
// role key is read from the function's environment and never leaves the server.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ status: "method_not_allowed" }, 405);

  let username = "", pin = "";
  try {
    const body = await req.json();
    username = String(body?.username ?? "");
    pin = String(body?.pin ?? "");
  } catch {
    return json({ status: "bad_request" }, 400);
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: check, error: checkError } = await admin.rpc("handle_login_check", {
    p_username: username,
    p_pin: pin,
  });
  if (checkError) return json({ status: "error" }, 500);
  if (check?.status !== "ok") return json(check ?? { status: "error" });

  const userId: string = check.user_id;
  const { data: found, error: getError } = await admin.auth.admin.getUserById(userId);
  if (getError || !found?.user) return json({ status: "error" }, 500);

  const email = found.user.email || `${userId}@login.convoy.invalid`;
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const password = btoa(String.fromCharCode(...bytes));

  const { error: updateError } = await admin.auth.admin.updateUserById(userId, {
    email,
    password,
    email_confirm: true,
  });
  if (updateError) return json({ status: "error" }, 500);

  return json({ status: "ok", email, password, pin_created: check.pin_created === true });
});
