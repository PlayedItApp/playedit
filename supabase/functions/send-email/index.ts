import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

const hookSecret = Deno.env.get("SEND_EMAIL_HOOK_SECRET")!.replace("v1,whsec_", "");

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("not allowed", { status: 400 });
  }

  try {
    const payload = await req.text();
    const headers = Object.fromEntries(req.headers);
    const wh = new Webhook(hookSecret);
    const { user, email_data } = wh.verify(payload, headers) as any;

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const resendApiKey = Deno.env.get("RESEND_API_KEY")!;

    const confirmUrl = `${supabaseUrl}/auth/v1/verify?token=${email_data.token_hash}&type=${email_data.email_action_type}&redirect_to=${email_data.redirect_to}`;

    let subject = "";
    let html = "";

    switch (email_data.email_action_type) {
      case "recovery":
        subject = "Reset your PlayedIt password";
        html = `<div style="font-family: 'Nunito', sans-serif; max-width: 480px; margin: 0 auto; padding: 32px;">
          <h2 style="color: #3D5A73;">PlayedIt</h2>
          <p style="color: #3D5A73;">Forgot your password? No worries. 🎮</p>
          <p style="color: #6B7280;">Click below to reset your password:</p>
          <div style="text-align: center; margin: 28px 0;">
            <a href="${confirmUrl}" style="background: #E07B4C; color: #FFFFFF; padding: 14px 32px; border-radius: 12px; text-decoration: none; font-weight: 600; display: inline-block;">Reset Password</a>
          </div>
          <p style="color: #6B7280; font-size: 14px;">If you didn't request this, just ignore this email.</p>
        </div>`;
        break;
      case "signup":
        subject = "Confirm your PlayedIt account";
        html = `<div style="font-family: 'Nunito', sans-serif; max-width: 480px; margin: 0 auto; padding: 32px;">
          <h2 style="color: #3D5A73;">PlayedIt</h2>
          <p style="color: #3D5A73;">Welcome to PlayedIt! 🎮</p>
          <p style="color: #6B7280;">Confirm your email to start ranking games:</p>
          <div style="text-align: center; margin: 28px 0;">
            <a href="${confirmUrl}" style="background: #E07B4C; color: #FFFFFF; padding: 14px 32px; border-radius: 12px; text-decoration: none; font-weight: 600; display: inline-block;">Confirm Email</a>
          </div>
        </div>`;
        break;
      default:
        subject = "PlayedIt";
        html = `<p>Your code: ${email_data.token}</p>`;
    }

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "PlayedIt <noreply@playedit.app>",
        to: [user.email],
        subject,
        html,
      }),
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(JSON.stringify(err));
    }
  } catch (error) {
    return new Response(
      JSON.stringify({ error: { http_code: 500, message: error.message } }),
      { status: 401, headers: { "Content-Type": "application/json" } }
    );
  }

  return new Response(JSON.stringify({}), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
