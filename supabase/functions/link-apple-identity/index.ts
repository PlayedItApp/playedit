import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {
    // Get the authorization header (user's JWT)
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No authorization header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const { idToken, nonce } = await req.json();
    if (!idToken) {
      return new Response(JSON.stringify({ error: "Missing idToken" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Create a Supabase client with the user's JWT to verify they're authenticated
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Create a client with the user's JWT to verify they're authenticated
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });

    // Verify the calling user
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Invalid user session: " + (userError?.message || "no user") }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Decode the Apple ID token to get the email
    const tokenParts = idToken.split(".");
    const payload = JSON.parse(atob(tokenParts[1]));
    const appleEmail = payload.email;
    const appleUserId = payload.sub;

    if (!appleEmail) {
      return new Response(JSON.stringify({ error: "No email in Apple token" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Use admin client to update the user's email to match Apple's email
    // This enables automatic identity linking
    const adminClient = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // Step 1: Update user email to match Apple email (if different)
    const currentEmail = user.email;
    if (currentEmail !== appleEmail) {
      const { error: updateError } = await adminClient.auth.admin.updateUserById(
        user.id,
        { email: appleEmail, email_confirm: true }
      );
      if (updateError) {
        return new Response(JSON.stringify({ error: "Failed to update email: " + updateError.message }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    // Step 2: Sign in with the Apple ID token — this triggers automatic linking
    const { data: signInData, error: signInError } =
      await adminClient.auth.signInWithIdToken({
        provider: "apple",
        token: idToken,
        nonce: nonce,
      });

    if (signInError) {
      // Revert email if sign-in failed and we changed it
      if (currentEmail && currentEmail !== appleEmail) {
        await adminClient.auth.admin.updateUserById(user.id, {
          email: currentEmail,
          email_confirm: true,
        });
      }
      return new Response(JSON.stringify({ error: "Failed to link: " + signInError.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Step 3: Restore the original email after linking
    if (currentEmail && currentEmail !== appleEmail) {
      const { error: restoreError } = await adminClient.auth.admin.updateUserById(
        user.id,
        { email: currentEmail, email_confirm: true }
      );
      if (restoreError) {
        console.error("Failed to restore email:", restoreError.message);
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});