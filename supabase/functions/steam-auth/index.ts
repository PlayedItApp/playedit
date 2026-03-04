import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const url = new URL(req.url);

  // HANDLE GET — this is the Steam OpenID callback redirect
  if (req.method === "GET") {
    const params = Object.fromEntries(url.searchParams.entries());
    const state = params["state"];
    if (!state) {
      return Response.redirect("playedit://steam-callback?error=missing_state");
    }
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    );
    const { data: stateRow } = await supabase
      .from("steam_auth_state")
      .select("user_id, expires_at")
      .eq("state", state)
      .single();
    if (!stateRow || new Date(stateRow.expires_at) < new Date()) {
      return Response.redirect("playedit://steam-callback?error=invalid_state");
    }
    await supabase.from("steam_auth_state").delete().eq("state", state);
    const userId = stateRow.user_id;

    // Validate with Steam
    const validationParams = new URLSearchParams();
    for (const [key, value] of Object.entries(params)) {
      if (key === "userId") continue;
      if (key === "openid.mode") {
        validationParams.set(key, "check_authentication");
      } else {
        validationParams.set(key, value);
      }
    }

    try {
      const steamResponse = await fetch("https://steamcommunity.com/openid/login", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: validationParams.toString(),
      });

      const steamResult = await steamResponse.text();

      if (!steamResult.includes("is_valid:true")) {
        return Response.redirect("playedit://steam-callback?error=validation_failed");
      }

      // Extract Steam ID
      const claimedId = params["openid.claimed_id"];
      const steamIdMatch = claimedId?.match(/\/id\/(\d+)$/);
      if (!steamIdMatch) {
        return Response.redirect("playedit://steam-callback?error=no_steam_id");
      }

      const steamId = steamIdMatch[1];

      // Save to user profile
      await supabase
        .from("users")
        .update({ steam_id: steamId, steam_connected_at: new Date().toISOString() })
        .eq("id", userId);

      // Redirect back to app with success
      return Response.redirect(`playedit://steam-callback?steam_id=${steamId}`);

    } catch (err) {
      return Response.redirect(`playedit://steam-callback?error=${encodeURIComponent(err.message)}`);
    }
  }

  // HANDLE POST — generate login URL
  try {
    const { action, userId } = await req.json();

    if (action === "get_login_url") {
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        { auth: { autoRefreshToken: false, persistSession: false } }
      );
      const state = crypto.randomUUID();
      await supabase.from("steam_auth_state").insert({
        state,
        user_id: userId,
        expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(), // 10 min
      });
      const returnTo = "https://api.playedit.app";
      const openIdParams = new URLSearchParams({
        "openid.ns": "http://specs.openid.net/auth/2.0",
        "openid.mode": "checkid_setup",
        "openid.return_to": returnTo + "?state=" + state,
        "openid.realm": returnTo,
        "openid.identity": "http://specs.openid.net/auth/2.0/identifier_select",
        "openid.claimed_id": "http://specs.openid.net/auth/2.0/identifier_select",
      });

      const loginUrl = `https://steamcommunity.com/openid/login?${openIdParams.toString()}`;

      return new Response(JSON.stringify({ url: loginUrl }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ error: "Invalid action" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});