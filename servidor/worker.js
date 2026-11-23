/* Cloudflare Worker: ponte segura entre o app e a API do Claude.
   Variáveis (Settings > Variables and Secrets):
   ANTHROPIC_API_KEY (Secret)  SUPABASE_URL  SUPABASE_ANON_KEY  ALLOWED_EMAILS (ex.: sabrina@x.com,andrew@y.com)  ALLOWED_ORIGIN (https://andrewdiasp.github.io) */
export default {
  async fetch(req, env) {
    const cors = {
      'access-control-allow-origin': env.ALLOWED_ORIGIN || 'https://andrewdiasp.github.io',
      'access-control-allow-methods': 'POST, OPTIONS',
      'access-control-allow-headers': 'authorization, content-type',
      'access-control-max-age': '86400',
    };
    const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'content-type': 'application/json' } });
    if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
    if (req.method !== 'POST') return json({ erro: 'use POST' }, 405);

    // 1) confere o login no Supabase
    const token = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
    if (!token) return json({ erro: 'sem login' }, 401);
    const u = await fetch(env.SUPABASE_URL + '/auth/v1/user', { headers: { apikey: env.SUPABASE_ANON_KEY, authorization: 'Bearer ' + token } });
    if (!u.ok) return json({ erro: 'login inválido' }, 401);
    const user = await u.json();
    const permitidos = String(env.ALLOWED_EMAILS || '').toLowerCase().split(',').map(s => s.trim()).filter(Boolean);
    if (permitidos.length && !permitidos.includes(String(user.email || '').toLowerCase())) return json({ erro: 'usuário não autorizado' }, 403);

    // 2) chama o Claude
    let body;
    try { body = await req.json(); } catch { return json({ erro: 'corpo inválido' }, 400); }
    if (!Array.isArray(body.messages) || !body.messages.length) return json({ erro: 'sem mensagens' }, 400);
    const rapido = body.tier === 'quick';
    const r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'x-api-key': env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({ model: rapido ? 'claude-haiku-5-5' : 'claude-sonnet-5-5', max_tokens: rapido ? 800 : 4096, messages: body.messages }),
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok) return json({ erro: (d.error && d.error.message) || 'erro na IA' }, r.status === 429 ? 429 : 502);
    return json({ text: (d.content || []).filter(c => c.type === 'text').map(c => c.text).join('') });
  },
};
