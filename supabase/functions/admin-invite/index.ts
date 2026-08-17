import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': Deno.env.get('APP_ORIGIN') ?? '',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const allowed = (email: string) => /@(linx\.com\.br|totvs\.com\.br)$/i.test(email.trim());

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) throw new Error('Não autenticado');
    const anon = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authHeader } } });
    const { data: { user } } = await anon.auth.getUser();
    if (!user) throw new Error('Não autenticado');
    const { data: profile } = await anon.from('app_profiles').select('role,is_active').eq('id', user.id).single();
    if (!profile || profile.role !== 'master' || !profile.is_active) throw new Error('Apenas master pode convidar usuários');

    const body = await req.json();
    const email = String(body.email ?? '').trim().toLowerCase();
    const fullName = String(body.full_name ?? '').trim();
    const role = body.role === 'admin' ? 'admin' : 'user';
    if (!allowed(email)) throw new Error('Domínio de e-mail não permitido');
    if (!fullName) throw new Error('Nome obrigatório');

    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { data: { full_name: fullName } });
    if (error) throw error;
    if (data.user) {
      await admin.from('app_profiles').update({ full_name: fullName, role }).eq('id', data.user.id);
    }
    return new Response(JSON.stringify({ ok: true }), { headers: { ...cors, 'Content-Type': 'application/json' } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Erro interno' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } });
  }
});
