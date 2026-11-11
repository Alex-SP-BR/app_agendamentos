# Agenda Pro

Aplicativo inicial de agenda e gestão para profissionais independentes, em Flutter para Android e Web, com Supabase como backend. A organização em `lib/features` separa autenticação, serviços, agendamentos e painel.

## Executar

1. Crie um projeto Supabase.
2. Execute [`supabase/schema.sql`](supabase/schema.sql) no SQL Editor do projeto.
3. Em instalações existentes, execute [`supabase/subscription_access_migration.sql`](supabase/subscription_access_migration.sql) no SQL Editor antes de atualizar o app. Perfis já existentes passam a `cortesia`/`gratis`; novos cadastros ficam `pendente`/`gratis`.
4. Execute [`supabase/subscription_admin_migration.sql`](supabase/subscription_admin_migration.sql) para habilitar a listagem e as ações administrativas de status.
5. Execute [`supabase/subscription_rejection_migration.sql`](supabase/subscription_rejection_migration.sql) para habilitar o status reversível `recusado`.
6. Em instalações existentes, execute [`supabase/unified_salon_schedule_migration.sql`](supabase/unified_salon_schedule_migration.sql) depois das demais migrações já aplicadas, inclusive `team_appointments_migration.sql` se usada. Ela mantém os agendamentos existentes e recarrega o cache do PostgREST; aplique a correção de conflitos por membro descrita na etapa 16.
7. Em instalações existentes, execute [`supabase/manual_salon_clients_migration.sql`](supabase/manual_salon_clients_migration.sql) após a migração de agenda unificada. Ela adiciona contatos de clientes isolados por salão para agendamentos manuais.
8. Em instalações existentes, execute [`supabase/team_member_unique_names_migration.sql`](supabase/team_member_unique_names_migration.sql) para impedir nomes duplicados na equipe. Antes, diferencie eventuais duplicatas usando sobrenomes.
9. Em instalações existentes, execute [`supabase/team_member_required_migration.sql`](supabase/team_member_required_migration.sql) após as migrações de equipe e de agendamentos. Ela cria um profissional responsável para salões sem equipe, atribui os agendamentos legados sem membro e passa a exigir a equipe em todo novo atendimento.
10. Em instalações existentes, execute [`supabase/professional_config_repair_migration.sql`](supabase/professional_config_repair_migration.sql) após as migrações de perfil/equipe. Ela recria configurações ausentes somente para perfis profissionais existentes, preservando a chave estrangeira.
11. Execute [`supabase/professional_agenda_sync_migration.sql`](supabase/professional_agenda_sync_migration.sql) nas instalações existentes para reparar configurações profissionais ausentes e habilitar a listagem do proprietário usando o mesmo fuso horário da agenda individual.
12. Em instalações existentes, execute [`supabase/team_member_pin_access_migration.sql`](supabase/team_member_pin_access_migration.sql) após as migrações de equipe. Ela adiciona o PIN com hash e o acesso individual inicial.
13. Para habilitar agendamentos, gestão de status e clientes próprios por PIN, execute [`supabase/team_member_pin_write_access_migration.sql`](supabase/team_member_pin_write_access_migration.sql) depois da migração de acesso via PIN.
14. Em instalações que já executaram a migração de escrita por PIN antes da correção de ambiguidade, execute [`supabase/team_member_pin_ambiguity_fix_migration.sql`](supabase/team_member_pin_ambiguity_fix_migration.sql) para substituir a função de autenticação.
15. Em instalações existentes, execute [`supabase/team_schedule_rpc_consolidated.sql`](supabase/team_schedule_rpc_consolidated.sql) após as migrações da equipe/PIN. Consolida as RPCs `horarios_ocupados`, `agenda_equipe_com_sessao` e `servicos_equipe_com_sessao`; `horarios_ocupados` exige um membro ativo e bloqueia apenas atendimentos pendentes/confirmados do mesmo salão e membro. Supersede `team_member_schedule_alignment_migration.sql` e `team_member_services_access_migration.sql`.
16. Em instalações existentes, execute [`supabase/team_member_booking_conflict_migration.sql`](supabase/team_member_booking_conflict_migration.sql) após as migrações de agendamento. Ela recria `validar_agendamento()` com o término calculado pela duração do serviço e limita conflitos ao mesmo membro da equipe.
17. Para corrigir as RPCs do painel PIN em instalações existentes, execute [`supabase/team_pin_rpc_schema_fix.sql`](supabase/team_pin_rpc_schema_fix.sql) por último. Ela recria `agenda_equipe_com_sessao`, `servicos_equipe_com_sessao`, `clientes_equipe_com_sessao` e `criar_agendamento_equipe_com_sessao`, aplica limites de dia calculados uma vez no fuso horário do salão, restringe os clientes ao salão e membro autenticados e recarrega o cache do PostgREST.
18. Para conceder acesso administrativo, atribua `{"role":"admin"}` ao campo `app_metadata` do usuário pelo Supabase Dashboard ou por um ambiente confiável de servidor. Não use `user_metadata` nem exponha a `service_role` no app. O usuário deve renovar a sessão para receber o claim.
19. Execute `flutter pub get`.
19. Inicie a aplicação com as credenciais públicas do projeto e a URL pública do app:

   ```sh
   flutter run -d chrome --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA --dart-define=TEAM_MEMBER_ACCESS_BASE_URL=https://SEU-DOMINIO-PUBLICO
   flutter run -d android --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA --dart-define=TEAM_MEMBER_ACCESS_BASE_URL=https://SEU-DOMINIO-PUBLICO
   ```

   A chave `anon`/publishable pode ser usada no cliente; **nunca** inclua a chave `service_role` no aplicativo.

Sem as duas variáveis de configuração, o app abre explicitamente em modo demonstração, usando exemplos locais e sem persistência. Não use esse modo para dados reais. Para projetos legados, `SUPABASE_ANON_KEY` também é aceita no lugar de `SUPABASE_PUBLISHABLE_KEY`.

## Fluxos disponíveis

- Criação de conta e login por e-mail para profissionais ou clientes (a confirmação de e-mail segue a configuração do Supabase Auth).
- Painel com agenda do dia, ganhos concluídos da semana/mês e exportação/compartilhamento de relatório PDF.
- Cada conta profissional é um estabelecimento independente: serviços, expediente, pagamentos, equipe, agendamentos e assinatura são vinculados diretamente ao perfil do dono. O painel organiza os agendamentos por funcionário, com atalho de novo agendamento já atribuído ao membro escolhido. Não há relação de matriz/filial entre estabelecimentos.
- Todo agendamento deve selecionar um profissional da equipe. Novos salões recebem um membro padrão com o nome do responsável; instalações existentes podem usar `team_member_required_migration.sql` para vincular registros antigos e exigir `team_member_id`. O painel ignora registros legados sem membro, sem exibi-los fora dos cartões.
- O menu do cartão permite copiar o link individual e definir/remover um PIN de 6 a 12 dígitos. Após validar o PIN, o profissional recebe uma sessão de 12 horas para criar agendamentos, atualizar o status dos próprios atendimentos e criar/editar somente os próprios clientes. O PIN é armazenado como hash; cinco tentativas incorretas bloqueiam novas tentativas por 15 minutos. A exclusão é impedida enquanto houver agendamentos relacionados e o salão não pode remover seu último profissional ativo.
- Os links individuais usam `TEAM_MEMBER_ACCESS_BASE_URL`, cujo padrão é `https://agenda-pro-sp.netlify.app`; um sufixo `/#/` também é aceito. É possível substituir o domínio padrão via `--dart-define=TEAM_MEMBER_ACCESS_BASE_URL=...`. Links com host local configurados para testes funcionam apenas no dispositivo que executa o app.
- O formulário de agendamento manual permite selecionar clientes já relacionados ao salão ou registrar um contato com nome e telefone; a opção **Clientes** lista os contatos do salão. Contatos criados manualmente não ganham conta de autenticação. O banco aplica RLS por proprietário e associa esses registros e seus agendamentos ao salão correspondente.
- A rota pública `https://seu-dominio/#/agendar/ID_DO_PROFISSIONAL` continua disponível para links existentes, com serviço filtrado pelo identificador do profissional e seleção de pagamento. O painel não oferece mais o botão para copiar esse link.
- Quatro temas (claro, escuro, colorido claro e colorido escuro), persistidos localmente em `shared_preferences`.

## Estrutura principal

```text
lib/
  app/                         # Rotas, composição da aplicação
  core/config/                 # Configuração por --dart-define
  core/theme/                  # Temas e preferência persistente
  features/
    auth/presentation/         # Login e cadastro
    salon/models/              # Serviços e contatos dos clientes do salão
    salon/data/                # Leitura isolada dos serviços, clientes e agendamentos
    booking/presentation/      # Fluxo de agendamento do cliente
    appointments/models/       # Agendamento e forma de pagamento
    dashboard/                 # Painel, resumo e geração de PDF
supabase/schema.sql            # Tabelas, trigger e políticas RLS
```

## Notas para integração de produção

- O banco aplica RLS por identidade autenticada e só publica serviços ativos. Um trigger recalcula o preço a partir do serviço no banco e impede que o cliente altere o valor no pedido.
- O app permite o painel profissional apenas para perfis `ativo` ou `cortesia`. O status e o plano são campos de `perfis`; altere-os somente por uma operação administrativa confiável, nunca pelo cliente. A tela de bloqueio do app é uma verificação de interface; a aplicação de cobrança como autorização contra acesso direto à API exigirá regras RLS adicionais.
- Os dados operacionais e o status/plano de assinatura permanecem associados ao `profissional_id`/perfil individual. Membros da equipe pertencem diretamente a um único perfil profissional e não criam vínculos entre estabelecimentos.
- Os agendamentos da equipe mantêm a FK composta `(team_member_id, profissional_id)`, que impede atribuir a um membro pertencente a outro salão. O relatório PDF detalha os ganhos mensais dos membros cadastrados e o total geral do salão.
- A Conta Master, identificada pelo claim confiável `app_metadata.role` igual a `admin`, usa uma visão dedicada à gestão de licenças e planos, sem métricas ou controles operacionais do salão. O banco também valida esse claim na consulta e na função RPC de alteração. “Aprovar Pix” altera o status para `ativo`; “Recusar” define `recusado`, que não é banimento definitivo e pode ser revertido pelo administrador. A aprovação é manual e não confirma pagamentos automaticamente.
- O fluxo PIX registra o tipo de pagamento, mas não processa cobrança nem confirma webhook/QR dinâmico. Integre um provedor de pagamentos por Edge Function, mantendo segredos fora do app.
- `profissionais_config` contém expediente, almoço, dias de folga, pagamento local e regras de pacotes; os controles de pagamento local e pacotes não são exibidos nas definições de expediente.
- A seleção de horários respeita expediente, almoço, folgas e duração do serviço. O trigger no banco repete as validações e serializa reservas por profissional/dia para rejeitar conflitos simultâneos.
- O PIX por chave é apresentado ao cliente após a solicitação, mas não há QR dinâmico, conciliação nem confirmação automática de pagamento. Integre um provedor por Edge Function para esses recursos.

## Validar

```sh
flutter analyze
flutter test
```
