// supabase/functions/moderate-text/index.ts
// Server-side text moderation Edge Function
// Deploy: supabase functions deploy moderate-text --project-ref jpxunrunsklooaypkouh

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// ============================================
// BLOCKLIST & NORMALIZATION
// ============================================

const LEET_MAP: Record<string, string> = {
  "@": "a", "4": "a", "^": "a",
  "8": "b",
  "(": "c", "<": "c",
  "|)": "d",
  "3": "e",
  "ph": "f",
  "6": "g", "9": "g",
  "#": "h",
  "1": "i", "!": "i", "|": "i",
  "7": "t",
  "0": "o",
  "5": "s", "$": "s",
  "+": "t",
  "v": "v",
  "2": "z",
};

// Slurs and hate speech — always blocked in ALL contexts
const ALWAYS_BLOCKED: string[] = [
  "nigger", "nigga", "niggers", "niggas", "chink", "chinks", "spic", "spics",
  "wetback", "wetbacks", "kike", "kikes", "gook", "gooks", "beaner", "beaners",
  "coon", "coons", "darkie", "darkies", "jigaboo", "raghead", "ragheads",
  "towelhead", "towelheads", "zipperhead",
  "faggot", "faggots", "fag", "fags", "dyke", "dykes", "tranny", "trannies",
  "retard", "retards", "retarded",
  "nazi", "nazis", "hitler",
  // Non-English slurs
  "marica", "maricon", "nègre", "enculé",
];

// Profanity — blocked in usernames only
const PROFANITY: string[] = [
  "fuck", "fucker", "fuckers", "fucking", "fucked", "motherfucker", "motherfuckers",
  "shit", "shits", "shitty", "bullshit",
  "bitch", "bitches",
  "ass", "asshole", "assholes",
  "dick", "dicks",
  "cock", "cocks",
  "pussy", "pussies",
  "cunt", "cunts",
  "whore", "whores", "slut", "sluts",
  // Non-English profanity
  "puta", "putas", "pendejo", "pendejos", "cabron", "cabrones",
  "joder", "mierda", "coño",
  "putain", "merde", "salaud", "salope", "connard", "connasse", "enculé",
  "nique",
  "scheiße", "scheisse", "arschloch", "hurensohn", "fotze", "wichser",
  "caralho", "porra", "viado", "buceta",
  "cazzo", "stronzo", "puttana", "vaffanculo", "minchia",
];

// Targeted insults — profanity aimed at people, blocked in ALL contexts
const TARGETED_INSULTS: string[] = [
  "shithead", "shitheads",
  "dickhead", "dickheads",
  "asshead",
  "dumbass", "dumbasses",
  "jackass", "jackasses",
  "fatass",
  "douchebag", "douchebags",
  "dipshit", "dipshits",
  "fuckface",
  "fuckhead", "fuckheads",
  "cockhead",
  "bitchass",
  "asswipe", "asswipes",
  "shitbag", "shitbags",
  "scumbag", "scumbags",
  "pisshead",
  "dick", "bitch", "cock", "asshole",
];

// All blocked words combined (for username context)
const ALL_BLOCKED = [...ALWAYS_BLOCKED, ...PROFANITY, ...TARGETED_INSULTS];

// Whitelist for Scunthorpe problem
const WHITELIST: string[] = [
  "scunthorpe", "cockburn", "cocktail", "cockatoo", "cockatiel",
  "peacock", "hancock", "dickens", "dickson", "assassin", "assassins",
  "classic", "classics", "bassist", "therapist", "psychotherapist",
  "shitake", "shiitake", "pushit", "buttress", "butterscotch",
  "sextant", "essex", "sussex", "middlesex", "bisexual",
  "titular", "constitution", "prostitute", "restitution",
  "grape", "drape", "scrape", "trapeze",
  "nigeria", "nigerian", "nigerians", "niger",
  "blackcock", "woodcock", "stopcock", "gamecock",
  "coonhound", "raccoon", "cocoon",
  "analytic", "analytics", "analysis", "analog", "analogy",
  "peniston", "dickerson", "hitchcock",
  "pass", "mass", "grass", "brass", "class", "glass", "lass",
  "assume", "assault",
];

// Reserved usernames
const RESERVED_USERNAMES: string[] = [
  "admin", "administrator", "playedit", "played_it", "played-it",
  "support", "help", "info", "contact", "team", "staff", "mod", "moderator",
  "system", "official", "root", "superuser", "null", "undefined",
  "api", "bot", "test", "demo", "example", "guest",
  "noreply", "no-reply", "no_reply", "postmaster", "webmaster",
  "abuse", "security", "privacy", "legal", "copyright",
  "everyone", "all", "here", "channel",
];

// ============================================
// NORMALIZATION
// ============================================

function normalizeText(text: string): string {
  let normalized = text.toLowerCase();

  // Remove zero-width characters
  normalized = normalized.replace(/[\u200B-\u200D\u2060\uFEFF]/g, "");

  // Multi-char replacements first
  normalized = normalized.replace(/ph/g, "f");
  normalized = normalized.replace(/\|\\)/g, "d");

  // Single char replacements
  for (const [leet, letter] of Object.entries(LEET_MAP)) {
    if (leet.length === 1) {
      normalized = normalized.split(leet).join(letter);
    }
  }

  // Collapse repeated characters (3+ -> 2)
  normalized = normalized.replace(/(.)\\1{2,}/g, "$1$1");

  // Remove separators between letters (f.u.c.k, f-u-c-k)
  normalized = normalized.replace(/(?<=\b\w)[.\-_\s](?=\w\b)/g, "");

  return normalized;
}

// ============================================
// MATCHING
// ============================================

interface ModerationResult {
  allowed: boolean;
  reason?: string;
  flaggedWord?: string;
}

function isWhitelisted(word: string, normalizedText: string): boolean {
  return WHITELIST.some(
    (whiteWord) => whiteWord.includes(word) && normalizedText.includes(whiteWord)
  );
}

// Leading word boundary only — catches "shitplayer" but not "lass" matching "ass"
function checkWithLeadingBoundary(
  text: string,
  blockedWords: string[],
  errorMessage: string
): ModerationResult {
  const normalized = normalizeText(text);

  for (const blocked of blockedWords) {
    const regex = new RegExp(`\\b${escapeRegex(blocked)}`, "i");
    const match = normalized.match(regex);

    if (match && !isWhitelisted(blocked, normalized)) {
      return {
        allowed: false,
        reason: errorMessage,
        flaggedWord: blocked,
      };
    }
  }

  return { allowed: true };
}

function checkText(
  text: string,
  context: "username" | "comment" | "note"
): ModerationResult {
  if (!text || text.trim().length === 0) {
    return { allowed: true };
  }

  // For usernames: block all profanity + slurs + insults with leading boundary
  // For comments/notes: block slurs + targeted insults with leading boundary
  const blockedList = context === "username" ? ALL_BLOCKED : [...ALWAYS_BLOCKED, ...TARGETED_INSULTS];
  const errorMessage = context === "username"
    ? "This username contains inappropriate language. Please choose a different one."
    : "Your message contains language that isn't allowed. Please revise and try again.";

  return checkWithLeadingBoundary(text, blockedList, errorMessage);
}

function checkUsername(username: string): ModerationResult {
  const lower = username.toLowerCase().trim();

  // Check reserved usernames
  if (RESERVED_USERNAMES.includes(lower)) {
    return {
      allowed: false,
      reason: "This username is reserved. Please choose a different one.",
    };
  }

  // Check if username contains a reserved name as substring
  for (const reserved of RESERVED_USERNAMES) {
    if (lower.includes(reserved)) {
      return {
        allowed: false,
        reason: "This username is reserved. Please choose a different one.",
      };
    }
  }

  return checkText(username, "username");
}

function escapeRegex(str: string): string {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// ============================================
// HTTP HANDLER
// ============================================

serve(async (req: Request) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Content-Type": "application/json",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: corsHeaders }
    );
  }

  try {
    const body = await req.json();
    const { text, context } = body;

    if (!text || typeof text !== "string") {
      return new Response(
        JSON.stringify({ error: "Missing 'text' field" }),
        { status: 400, headers: corsHeaders }
      );
    }

    if (!context || !["username", "comment", "note"].includes(context)) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid 'context' field" }),
        { status: 400, headers: corsHeaders }
      );
    }

    let result: ModerationResult;

    if (context === "username") {
      result = checkUsername(text);
    } else {
      result = checkText(text, context);
    }

    return new Response(
      JSON.stringify({
        allowed: result.allowed,
        reason: result.reason || null,
      }),
      { status: 200, headers: corsHeaders }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Invalid request body" }),
      { status: 400, headers: corsHeaders }
    );
  }
});
