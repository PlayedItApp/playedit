import { getUserPlayedGames } from "npm:psn-api@^2.4.1";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Maps PSN platform strings to clean display names
function normalizePlatform(raw: string): string {
  const map: Record<string, string> = {
    "PS5":  "PS5",
    "PS4":  "PS4",
    "PS3":  "PS3",
    "PS2":  "PS2",
    "PSP":  "PSP",
    "PSVITA": "PS Vita",
    "ps5_native_game": "PS5",
    "ps4_game": "PS4",
  };
  return map[raw] ?? raw;
}

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

    const { accessToken, psnAccountId } = await req.json();
    if (!accessToken || !psnAccountId) {
      return new Response(JSON.stringify({ error: "Missing accessToken or psnAccountId" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const authorization = { accessToken };
    // Fetch all played games with playtime — paginate until done
    const allGames: any[] = [];
    let offset = 0;
    const limit = 200;
    while (true) {
      const response = await getUserPlayedGames(
        { accessToken: authorization.accessToken },
        "me",
        { limit, offset }
      );
      console.log("psn-games: getUserPlayedGames response keys:", Object.keys(response ?? {}));
      console.log("psn-games: totalItemCount:", response?.totalItemCount);
      const titles = response?.titles ?? [];
      allGames.push(...titles);
      if (allGames.length >= (response?.totalItemCount ?? 0) || titles.length < limit) {
        break;
      }
      offset += limit;
    }
    console.log("psn-games: allGames count:", allGames.length);
    const categoryCounts: Record<string, number> = {};
	allGames.forEach(t => { const c = t.category ?? "null"; categoryCounts[c] = (categoryCounts[c] ?? 0) + 1; });
	console.log("psn-games: categories:", JSON.stringify(categoryCounts));
    if (allGames.length > 0) {
      console.log("psn-games: first game sample:", JSON.stringify(allGames[0]));
    }
    // Shape into the format PSNService.swift expects
    const excludedCategories = [
  		"ps5_native_media_app", "ps4_native_media_app",
  		"ps5_web_based_media_app", "ps4_videoservice_web_app",
  		"ps4_nongame_mini_app", "not_found", "web"
	];
    const excludedNames = ["sharefactory", "sharefactory™"];
    const games = allGames
      .filter((t) => t?.name && !excludedCategories.includes(t.category ?? "") && !excludedNames.includes(t.name.toLowerCase()))
      .map((t) => ({
        titleId: t.titleId ?? t.npTitleId ?? String(Math.random()),
        name: t.name,
        playtimeMinutes: parseDuration(t.playDuration ?? "PT0S"),
        platform: normalizePlatform(t.category ?? t.concept?.platformCategory ?? t.platform ?? "PlayStation"),
        iconUrl: t.imageUrl ?? null,
        lastPlayedAt: t.lastPlayedDateTime ?? null,
      }));

    return new Response(
      JSON.stringify({ games, totalCount: games.length }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("psn-games error:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "Unknown error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// Parse ISO 8601 duration (PT2H30M15S) → total minutes
function parseDuration(duration: string): number {
  const match = duration.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!match) return 0;
  const hours = parseInt(match[1] ?? "0");
  const minutes = parseInt(match[2] ?? "0");
  return hours * 60 + minutes;
}