import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const { email } = await req.json();
    
    if (!email) {
      return new Response(JSON.stringify({ error: "Email required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Generate a new signup confirmation link
    const { data, error } = await supabaseAdmin.auth.admin.generateLink({
      type: "signup",
      email: email,
      options: {
        redirectTo: "https://playedit.app/confirmed",
      },
    });

    if (error) throw error;

    const confirmUrl = `${Deno.env.get("SUPABASE_URL")}/auth/v1/verify?token=${data.properties.hashed_token}&type=signup&redirect_to=https://playedit.app/confirmed`;

    // Send via Resend
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "PlayedIt <noreply@playedit.app>",
        to: [email],
        subject: "Confirm your PlayedIt account",
        html: `<!DOCTYPE html>
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
</html>`,
      }),
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(JSON.stringify(err));
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});