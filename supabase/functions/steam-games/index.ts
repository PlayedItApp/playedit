import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const STEAM_API_KEY = Deno.env.get("STEAM_API_KEY")!;
const RAWG_API_KEY = Deno.env.get("RAWG_API_KEY")!;

interface SteamGame {
  appid: number;
  name: string;
  playtime_forever: number;
  img_icon_url: string;
}

interface MatchedGame {
  steamAppId: number;
  steamName: string;
  playtimeMinutes: number;
  rawgId: number | null;
  rawgTitle: string | null;
  rawgCoverUrl: string | null;
  rawgGenres: string[];
  rawgPlatforms: string[];
  rawgReleaseDate: string | null;
  rawgMetacriticScore: number | null;
  matchConfidence: number; // 0-100
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { action, steamId, appIds } = await req.json();

    if (action === "fetch_library") {
      // Fetch owned games from Steam
      const steamUrl = `https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=${STEAM_API_KEY}&steamid=${steamId}&include_appinfo=1&include_played_free_games=1&skip_unvetted_apps=false&format=json`;

      const steamResponse = await fetch(steamUrl);
      const steamData = await steamResponse.json();

      if (!steamData.response || !steamData.response.games) {
        return new Response(JSON.stringify({ 
          error: "empty_library",
          message: "No games found. Your Steam game details may be set to private."
        }), {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Sort by playtime descending
      const games: SteamGame[] = steamData.response.games.sort(
        (a: SteamGame, b: SteamGame) => b.playtime_forever - a.playtime_forever
      );

      return new Response(JSON.stringify({
        gameCount: steamData.response.game_count,
        games: games.map((g: SteamGame) => ({
          appid: g.appid,
          name: g.name,
          playtimeMinutes: g.playtime_forever,
          iconUrl: g.img_icon_url 
            ? `https://media.steampowered.com/steamcommunity/public/images/apps/${g.appid}/${g.img_icon_url}.jpg`
            : null,
        })),
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (action === "match_rawg") {
      // Batch match Steam games against RAWG
      // appIds is an array of { appid, name }
      const results: MatchedGame[] = [];

      for (const game of appIds) {
        try {
          // Search RAWG
          const searchUrl = `https://api.rawg.io/api/games?search=${encodeURIComponent(game.name)}&key=${RAWG_API_KEY}&page_size=3`;
          const rawgResponse = await fetch(searchUrl);
          const rawgData = await rawgResponse.json();

          let bestMatch = null;
          let confidence = 0;

          if (rawgData.results && rawgData.results.length > 0) {
            // Check for exact or close match
            for (const result of rawgData.results) {
              const similarity = calculateSimilarity(
                game.name.toLowerCase(),
                result.name.toLowerCase()
              );

              if (similarity > confidence) {
                confidence = similarity;
                bestMatch = result;
              }
            }

            // If no good match, take top result if above threshold
            if (confidence < 60 && rawgData.results[0]) {
              bestMatch = rawgData.results[0];
              confidence = 50; // Low confidence flag
            }
          }

          results.push({
            steamAppId: game.appid,
            steamName: game.name,
            playtimeMinutes: game.playtimeMinutes,
            rawgId: bestMatch?.id ?? null,
            rawgTitle: bestMatch?.name ?? null,
            rawgCoverUrl: bestMatch?.background_image ?? null,
            rawgGenres: bestMatch?.genres?.map((g: any) => g.name) ?? [],
            rawgPlatforms: bestMatch?.platforms?.map((p: any) => p.platform.name) ?? [],
            rawgReleaseDate: bestMatch?.released ?? null,
            rawgMetacriticScore: bestMatch?.metacritic ?? null,
            matchConfidence: Math.round(confidence),
          });

          // Small delay to respect RAWG rate limits
          await new Promise((resolve) => setTimeout(resolve, 250));
        } catch (err) {
          // If one match fails, continue with others
          results.push({
            steamAppId: game.appid,
            steamName: game.name,
            playtimeMinutes: game.playtimeMinutes,
            rawgId: null,
            rawgTitle: null,
            rawgCoverUrl: null,
            rawgGenres: [],
            rawgPlatforms: [],
            rawgReleaseDate: null,
            rawgMetacriticScore: null,
            matchConfidence: 0,
          });
        }
      }

      return new Response(JSON.stringify({ matches: results }), {
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

// Levenshtein-based similarity (0-100)
function calculateSimilarity(a: string, b: string): number {
  // Normalize: strip special chars, extra spaces
  const normalize = (s: string) =>
    s.replace(/[^a-z0-9\s]/g, "").replace(/\s+/g, " ").trim();

  const na = normalize(a);
  const nb = normalize(b);

  if (na === nb) return 100;

  // Check if one contains the other
  if (na.includes(nb) || nb.includes(na)) return 90;

  // Levenshtein distance
  const matrix: number[][] = [];
  for (let i = 0; i <= na.length; i++) {
    matrix[i] = [i];
    for (let j = 1; j <= nb.length; j++) {
      if (i === 0) {
        matrix[i][j] = j;
      } else {
        const cost = na[i - 1] === nb[j - 1] ? 0 : 1;
        matrix[i][j] = Math.min(
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost
        );
      }
    }
  }

  const maxLen = Math.max(na.length, nb.length);
  if (maxLen === 0) return 100;
  return Math.round((1 - matrix[na.length][nb.length] / maxLen) * 100);
}