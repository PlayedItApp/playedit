// supabase/functions/send-push/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

async function createAPNsJWT(): Promise<string> {
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const privateKeyPem = Deno.env.get("APNS_PRIVATE_KEY")!;

  const header = btoa(JSON.stringify({ alg: "ES256", kid: keyId }))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const now = Math.floor(Date.now() / 1000);
  const claims = btoa(JSON.stringify({ iss: teamId, iat: now }))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const pemBody = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/[\s\n\r]/g, "");

  const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );

  const data = new TextEncoder().encode(`${header}.${claims}`);
  const signatureBuffer = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    data
  );

  const sigBytes = new Uint8Array(signatureBuffer);
  
  // Check if signature is DER-encoded (starts with 0x30) or already raw
  let rawSig: Uint8Array;
  if (sigBytes[0] === 0x30) {
    rawSig = derToRaw(sigBytes);
  } else if (sigBytes.length === 64) {
    rawSig = sigBytes;
  } else {
    rawSig = derToRaw(sigBytes);
  }

  const encodedSig = btoa(String.fromCharCode(...rawSig))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  console.log("JWT generated, sig length:", sigBytes.length, "raw:", rawSig.length);

  return `${header}.${claims}.${encodedSig}`;
}

// ECDSA signatures from Web Crypto are DER-encoded, but JWT needs raw r||s
function derToRaw(der: Uint8Array): Uint8Array {
  const raw = new Uint8Array(64);
  let offset = 2;
  
  const rLen = der[offset + 1];
  offset += 2;
  if (rLen <= 32) {
    raw.set(der.slice(offset, offset + rLen), 32 - rLen);
  } else {
    raw.set(der.slice(offset + rLen - 32, offset + rLen), 0);
  }
  offset += rLen;

  const sLen = der[offset + 1];
  offset += 2;
  if (sLen <= 32) {
    raw.set(der.slice(offset, offset + sLen), 64 - sLen);
  } else {
    raw.set(der.slice(offset + sLen - 32, offset + sLen), 32);
  }

  return raw;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id, title, body, data } = await req.json();
    
    console.log("APNS_KEY_ID:", Deno.env.get("APNS_KEY_ID"));
    console.log("APNS_TEAM_ID:", Deno.env.get("APNS_TEAM_ID"));
    console.log("APNS_BUNDLE_ID:", Deno.env.get("APNS_BUNDLE_ID"));
    const pk = Deno.env.get("APNS_PRIVATE_KEY") || "";
    console.log("APNS_PRIVATE_KEY starts with:", pk.substring(0, 30));
    console.log("APNS_PRIVATE_KEY length:", pk.length);

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Get device tokens for user
    const { data: tokens, error } = await supabaseAdmin
      .from("device_tokens")
      .select("token")
      .eq("user_id", user_id);

    if (error || !tokens?.length) {
      return new Response(
        JSON.stringify({ sent: 0, reason: "no tokens" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const jwt = await createAPNsJWT();
    const bundleId = Deno.env.get("APNS_BUNDLE_ID")!;

    // Use sandbox for TestFlight, production for App Store
    const apnsHost = "https://api.push.apple.com";

    let sent = 0;
    for (const { token } of tokens) {
      const payload = {
        aps: {
          alert: { title, body },
          sound: "default",
          badge: data?.unread_count ?? 1,
        },
        ...data,
      };

      const res = await fetch(`${apnsHost}/3/device/${token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": bundleId,
          "apns-push-type": "alert",
          "apns-priority": "10",
        },
        body: JSON.stringify(payload),
      });

      if (res.ok) {
        sent++;
      } else {
        const errBody = await res.text();
        console.error(
          `APNs error for token ${token}: ${res.status} ${errBody}`
        );

        // Remove invalid tokens
        if (res.status === 410 || res.status === 400) {
          await supabaseAdmin
            .from("device_tokens")
            .delete()
            .eq("token", token);
        }
      }
    }

    return new Response(JSON.stringify({ sent }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Push error:", err);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});