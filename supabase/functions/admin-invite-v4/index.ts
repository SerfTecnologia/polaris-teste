import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const allowed = (email: string) => /@(linx\.com\.br|totvs\.com\.br)$/i.test(email.trim());
const headers = (origin: string) => ({ 'Access-Control-Allow-Origin': origin || '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' });
Deno.serve(async (req) => {
  const origin = req.headers.get('origin') || '*';
  if (req.method === 'OPTIONS') return new Response('ok', { headers: headers(origin) });
  try {
    const authorization = req.headers.get('Authorization');
    if (!authorization) throw new Error('Não autenticado');
    const anon = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } } });
    const { data: { user: actor } } = await anon.auth.getUser();
    if (!actor) throw new Error('Não autenticado');
    const { data: actorProfile } = await anon.from('app_profiles').select('role,is_active').eq('id', actor.id).single();
    if (!actorProfile || actorProfile.role !== 'master' || !actorProfile.is_active) throw new Error('Apenas master pode criar acessos');
    const body = await req.json();
    const email = String(body.email ?? '').trim().toLowerCase();
    const fullName = String(body.full_name ?? '').trim();
    const password = String(body.password ?? '').trim();
    const role = body.role === 'admin' ? 'admin' : 'user';
    const redirectTo = String(body.redirect_to || `${origin}/`);
    if (!allowed(email)) throw new Error('Domínio de e-mail não permitido');
    if (!fullName) throw new Error('Nome obrigatório');
    if (password && password.length < 8) throw new Error('A senha prévia deve ter pelo menos 8 caracteres');
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    let target;
    const { data: existing } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    const found = existing.users.find((u: any) => u.email?.toLowerCase() === email);
    if (found) {
      const { data, error } = await admin.auth.admin.updateUserById(found.id, { ...(password ? { password } : {}), user_metadata: { ...(found.user_metadata || {}), full_name: fullName, app_name: 'Polaris', app_url: redirectTo } });
      if (error) throw error; target = data.user;
    } else if (password) {
      const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: fullName, app_name: 'Polaris', app_url: redirectTo } });
      if (error) throw error; target = data.user;
    } else {
      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { data: { full_name: fullName, app_name: 'Polaris', app_url: redirectTo }, redirectTo });
      if (error) throw error; target = data.user;
    }
    if (target) {
      const { error } = await admin.from('app_profiles').upsert({ id: target.id, email, full_name: fullName, role, is_active: true }, { onConflict: 'id' });
      if (error) throw error;
    }
    return new Response(JSON.stringify({ ok: true, mode: password ? 'password' : 'invite', message: password ? 'Acesso criado/atualizado com senha prévia.' : 'Convite enviado para definição de senha.' }), { headers: headers(origin) });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : 'Erro interno ao criar acesso' }), { status: 400, headers: headers(origin) });
  }
});
