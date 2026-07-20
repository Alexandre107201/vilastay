// ============================================================
// VILA STAY — Edge Function: ical-sync
// Sincroniza os calendários iCal do Airbnb de TODOS os imóveis.
// - Importa reservas novas (deduplica pelo UID do evento)
// - Remove reservas futuras importadas que sumiram do feed (cancelamentos)
// - Nunca mexe em reservas criadas manualmente
// Instalação: Supabase → Edge Functions → Deploy new function
//             → nome: ical-sync → cole este código → Deploy
// ============================================================

import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const today = new Date().toISOString().slice(0, 10);
  const report: Record<string, unknown>[] = [];

  const { data: props } = await supabase
    .from("properties")
    .select("id, name, ical_url")
    .not("ical_url", "is", null)
    .neq("ical_url", "");

  for (const p of props ?? []) {
    try {
      const res = await fetch(p.ical_url, {
        headers: { "User-Agent": "VilaStay/1.0 (calendar sync)" },
      });
      if (!res.ok) throw new Error("HTTP " + res.status);
      const text = await res.text();

      // Parse dos eventos do iCal
      const events: { uid: string; check_in: string; check_out: string }[] = [];
      for (const b of text.split("BEGIN:VEVENT").slice(1)) {
        const g = (re: RegExp) => {
          const m = b.match(re);
          return m ? m[1].trim() : null;
        };
        const uid = g(/UID:(.+)/);
        const sum = g(/SUMMARY:(.+)/) ?? "";
        const ds = g(/DTSTART(?:;VALUE=DATE)?:(\d{8})/);
        const de = g(/DTEND(?:;VALUE=DATE)?:(\d{8})/);
        if (!uid || !ds || !de) continue;
        if (/not available|blocked|unavailable/i.test(sum)) continue;
        const f = (s: string) => `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`;
        events.push({ uid, check_in: f(ds), check_out: f(de) });
      }
      const feedUids = new Set(events.map((e) => e.uid));

      const { data: existing } = await supabase
        .from("reservations")
        .select("id, ical_uid, check_in")
        .eq("property_id", p.id)
        .eq("source", "ical");

      const have = new Set((existing ?? []).map((x) => x.ical_uid));

      // Novas reservas (ignora as já encerradas)
      const news = events.filter((e) => !have.has(e.uid) && e.check_out >= today);
      if (news.length) {
        await supabase.from("reservations").insert(
          news.map((e) => ({
            property_id: p.id,
            guest_name: "Hóspede Airbnb",
            check_in: e.check_in,
            check_out: e.check_out,
            source: "ical",
            ical_uid: e.uid,
          })),
        );
      }

      // Cancelamentos: reservas futuras importadas que sumiram do feed
      const gone = (existing ?? [])
        .filter((x) => x.check_in > today && x.ical_uid && !feedUids.has(x.ical_uid))
        .map((x) => x.id);
      if (gone.length) {
        await supabase.from("reservations").delete().in("id", gone);
      }

      report.push({ imovel: p.name, novas: news.length, canceladas: gone.length });
    } catch (e) {
      report.push({ imovel: p.name, erro: String(e) });
    }
  }

  return new Response(JSON.stringify({ ok: true, report }), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
});
