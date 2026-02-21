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

    const redirectTo = email_data.email_action_type === "signup"
      ? "https://playedit.app/confirmed?auto_login=true"
      : "https://playedit.app/confirmed";
    const confirmUrl = `${supabaseUrl}/auth/v1/verify?token=${email_data.token_hash}&type=${email_data.email_action_type}&redirect_to=${redirectTo}`;

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
        html = `<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark"></head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Nunito', sans-serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
    <tr><td align="center" style="padding: 40px 20px;">
      <table role="presentation" width="480" cellspacing="0" cellpadding="0" border="0" style="max-width: 480px; width: 100%;">
        <tr><td align="center" style="padding: 0 0 24px;">
          <span style="font-size: 28px; font-weight: 700; color: #3D5A73;">played</span><span style="font-size: 28px; font-weight: 700; color: #E07B4C;">it</span>
        </td></tr>
        <tr><td align="center" style="padding: 0 0 8px;">
          <span style="font-size: 22px; font-weight: 700; color: #3D5A73;">Welcome to PlayedIt! 🎮</span>
        </td></tr>
        <tr><td align="center" style="padding: 0 0 32px;">
          <span style="font-size: 16px; color: #6B7280; line-height: 24px;">Tap the button below to confirm your account<br>and start ranking your games.</span>
        </td></tr>
        <tr><td align="center" style="padding: 0 0 32px;">
          <table role="presentation" cellspacing="0" cellpadding="0" border="0">
            <tr><td style="background-color: #E07B4C; border-radius: 12px;">
              <a href="${confirmUrl}" style="display: block; padding: 16px 48px; font-size: 17px; font-weight: 700; color: #FFFFFF; text-decoration: none; text-align: center;"><span style="color: #FFFFFF;">Confirm Account</span></a>
            </td></tr>
          </table>
        </td></tr>
        <tr><td align="center" style="padding: 0 0 24px;">
          <span style="font-size: 13px; color: #C4CDD4;">If you didn't sign up for PlayedIt, you can safely ignore this email.</span>
        </td></tr>
        <tr><td style="border-top: 1px solid #F5F6F7; padding: 24px 0 0;" align="center">
          <span style="font-size: 12px; color: #C4CDD4;">PlayedIt — A social game ranking app for friends</span>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
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
