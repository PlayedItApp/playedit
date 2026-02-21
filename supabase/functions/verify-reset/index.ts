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
    const { email, code, new_password } = await req.json();

    if (!email || !code || !new_password) {
      return new Response(
        JSON.stringify({ error: "Email, code, and new password are required" }),
        { status: 400, headers: corsHeaders }
      );
    }

    if (new_password.length < 6) {
      return new Response(
        JSON.stringify({ error: "Password must be at least 6 characters" }),
        { status: 400, headers: corsHeaders }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Look up the code
    const { data: resetRecord, error: lookupError } = await supabase
      .from("password_resets")
      .select("*")
      .eq("email", email.toLowerCase())
      .eq("code", code)
      .eq("used", false)
      .gte("expires_at", new Date().toISOString())
      .single();

    if (lookupError || !resetRecord) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired code. Try requesting a new one." }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Mark code as used
    await supabase
      .from("password_resets")
      .update({ used: true })
      .eq("id", resetRecord.id);

    // Find the user by email
    const { data: { users }, error: listError } = await supabase.auth.admin.listUsers({
      filter: `email.eq.${email.toLowerCase()}`,
      page: 1,
      perPage: 1,
    });

    const user = users?.[0];

    if (listError || !user) {
      return new Response(
        JSON.stringify({ error: "User not found" }),
        { status: 404, headers: corsHeaders }
      );
    }

    // Update the password using admin API
    const { error: updateError } = await supabase.auth.admin.updateUserById(
      user.id,
      { password: new_password }
    );

    if (updateError) throw updateError;

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