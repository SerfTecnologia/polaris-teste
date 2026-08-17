# Polaris Secure

Esta pasta contém uma **cópia isolada** do arquivo HTML enviado para o Polaris. O arquivo original em `/home/ubuntu/upload/polaris-index(11).html` não foi alterado, e nenhuma tabela, função ou política foi executada no projeto Supabase `RC_FOOD`.

## Resposta sobre o banco

Sim. Para o requisito solicitado, o banco é necessário. Login, confirmação de e-mail, usuários ativos/inativos, perfis, permissões por tela e auditoria não devem ser controlados apenas em `localStorage` ou em JavaScript no navegador. A cópia foi preparada para um **novo projeto Supabase**, separado do `RC_FOOD`, usando o arquivo `supabase-schema.sql`.

O fluxo recomendado é criar um novo projeto Supabase para o Polaris, habilitar a confirmação de e-mail, executar o schema nessa cópia e configurar a URL e a chave pública no `config.js`. O schema cria as tabelas `app_profiles`, `app_roles`, `app_screens`, `app_role_screens` e `app_user_roles`, além de políticas RLS e um trigger que restringe os domínios e promove os dois e-mails master informados.

## Segurança e DevTools

Não é tecnicamente possível impedir que uma pessoa com acesso à página veja ou baixe o HTML, CSS e JavaScript enviados ao navegador. Ofuscação, bloqueio do botão direito ou detecção de DevTools não constituem proteção real.

A proteção correta é não enviar ao navegador segredos nem decisões críticas. A cópia remove a chave pública fixa do projeto original, exige sessão antes de iniciar as consultas, anexa o token autenticado às chamadas e usa RLS no banco. O convite de usuários usa a Edge Function `admin-invite`, que deve manter a `SUPABASE_SERVICE_ROLE_KEY` exclusivamente no ambiente servidor. A service role nunca pode ser colocada no `config.js` ou no HTML.

Mesmo que alguém leia o código, as operações devem continuar bloqueadas pelo Supabase quando não houver sessão válida ou quando o usuário não tiver a role correspondente. As regras de negócio que não puderem ser expostas também devem ser movidas para Edge Functions ou outro backend protegido.

## Arquivos

| Arquivo | Finalidade |
|---|---|
| `index.html` | Cópia do Polaris com tela de login, cadastro restrito, recuperação de senha e área master inicial. |
| `config.template.js` | Modelo de configuração pública do novo projeto Supabase. |
| `config.js` | Placeholder local; deve ser preenchido com os dados públicos da cópia antes da publicação. |
| `supabase-schema.sql` | Schema, trigger, funções auxiliares e políticas RLS da cópia. |
| `supabase/functions/admin-invite/index.ts` | Edge Function para convite de usuários usando service role apenas no servidor. |

## Ordem de implantação

Primeiro, crie um novo projeto Supabase, sem reutilizar `RC_FOOD`. Em seguida, execute `supabase-schema.sql` no SQL Editor da cópia. Depois, configure as variáveis da Edge Function `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` e `APP_ORIGIN`, faça o deploy de `admin-invite` e preencha `config.js` somente com a URL e a publishable key do projeto novo.

Por fim, valide com os dois e-mails master, um usuário permitido comum e um e-mail de domínio externo. Também deve ser testado que um usuário comum não consegue consultar ou alterar as tabelas administrativas pelo REST e que um usuário desativado perde o acesso no próximo carregamento ou evento de sessão.

## Observação de escopo

A tela de administração incluída é uma base funcional para o controle de usuários, perfis e telas. A operação de convite depende do deploy da Edge Function no projeto Supabase separado. Nenhuma alteração no banco original foi realizada nesta entrega.
