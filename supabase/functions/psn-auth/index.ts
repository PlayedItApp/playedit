import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  exchangeCodeForAccessToken,
  exchangeNpssoForCode,
} from "npm:psn-api@^2.4.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // Verify user JWT
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    );

    // Verify the calling user
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { npsso } = await req.json();
    if (!npsso || typeof npsso !== "string" || npsso.length < 10) {
      return new Response(JSON.stringify({ error: "Invalid NPSSO token" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Exchange NPSSO → access code → auth tokens
    const accessCode = await exchangeNpssoForCode(npsso);
    const authorization = await exchangeCodeForAccessToken(accessCode);

    if (!authorization?.accessToken) {
      return new Response(JSON.stringify({ error: "Failed to exchange NPSSO for access token" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Fetch the user's PSN account ID
    const profileRes = await fetch(
      "https://us-prof.np.community.playstation.net/userProfile/v1/users/me/profile2?fields=accountId,onlineId",
      {
        headers: {
          Authorization: `Bearer ${authorization.accessToken}`,
        },
      }
    );

    if (!profileRes.ok) {
      return new Response(JSON.stringify({ error: "Failed to fetch PSN profile" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const profileData = await profileRes.json();
    const psnAccountId = profileData?.profile?.accountId;
    const psnOnlineId = profileData?.profile?.onlineId;

    if (!psnAccountId) {
      return new Response(JSON.stringify({ error: "Could not retrieve PSN account ID" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Store PSN ID on user record
    await supabase
      .from("users")
      .update({
        psn_id: psnAccountId,
        psn_connected_at: new Date().toISOString(),
      })
      .eq("id", user.id);

    return new Response(
      JSON.stringify({
        accessToken: authorization.accessToken,
        psnAccountId,
        psnOnlineId,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("psn-auth error:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "Unknown error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});