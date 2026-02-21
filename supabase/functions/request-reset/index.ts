import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Content-Type",
      },
    });
  }
  
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST",
    "Access-Control-Allow-Headers": "Content-Type",
    "Content-Type": "application/json",
  };

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: corsHeaders,
    });
  }

  try {
    const { email } = await req.json();

    if (!email) {
      return new Response(JSON.stringify({ error: "Email is required" }), {
        status: 400,
        headers: corsHeaders,
      });
    }

    // Use service role to access auth and password_resets table
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Check if user exists (don't reveal this to the client for security)
    const { data: { users } } = await supabase.auth.admin.listUsers({
      filter: `email.eq.${email.toLowerCase()}`,
      page: 1,
      perPage: 1,
    });
    const userExists = users && users.length > 0;

    // Always return success even if user doesn't exist (prevent email enumeration)
    if (!userExists) {
      return new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: corsHeaders,
      });
    }

    // Generate 6-digit code
    const array = new Uint32Array(1);
	crypto.getRandomValues(array);
	const code = String(100000 + (array[0] % 900000));

    // Delete any existing codes for this email
    await supabase
      .from("password_resets")
      .delete()
      .eq("email", email.toLowerCase());

    // Store the code (expires in 15 minutes)
    const { error: insertError } = await supabase
      .from("password_resets")
      .insert({
        email: email.toLowerCase(),
        code: code,
        expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      });

    if (insertError) throw insertError;

    // Send email via Resend
    const resendApiKey = Deno.env.get("RESEND_API_KEY")!;

    const emailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${resendApiKey}`,
      },
      body: JSON.stringify({
        from: "PlayedIt <noreply@playedit.app>",
        to: [email],
        subject: "Your PlayedIt reset code",
        html: `
          <div style="font-family: 'Nunito', 'SF Pro Rounded', sans-serif; max-width: 480px; margin: 0 auto; padding: 32px; background: #FFFFFF;">
            <h2 style="color: #3D5A73; font-size: 22px; margin: 0 0 16px 0;">PlayedIt</h2>
            <p style="color: #3D5A73; font-size: 17px; line-height: 24px;">
              Forgot your password? No worries. 🎮
            </p>
            <p style="color: #6B7280; font-size: 16px; line-height: 22px;">
              Here's your reset code:
            </p>
            <div style="text-align: center; margin: 28px 0;">
              <div style="background: #F5F6F7; display: inline-block; padding: 16px 32px; border-radius: 12px; letter-spacing: 8px; font-size: 32px; font-weight: 700; color: #3D5A73;">
                ${code}
              </div>
            </div>
            <p style="color: #6B7280; font-size: 14px; line-height: 20px;">
              This code expires in 15 minutes. If you didn't request this, just ignore this email.
            </p>
            <hr style="border: none; border-top: 1px solid #F5F6F7; margin: 24px 0;" />
            <p style="color: #C4CDD4; font-size: 12px; text-align: center;">
              PlayedIt — A social game ranking app for friends
            </p>
          </div>
        `,
      }),
    });

    if (!emailResponse.ok) {
      const errorData = await emailResponse.json();
      throw new Error(errorData.message || "Failed to send email");
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: corsHeaders,
    });
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ error: "Something went wrong. Try again?" }),
      {
        status: 500,
        headers: corsHeaders,
      }
    );
  }
});