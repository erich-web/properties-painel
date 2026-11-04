-- =====================================================================
-- Teste 0001: quem lê e quem escreve
--
-- Cenários: e-mail fora de pessoas; leitura; operacional; admin; anon.
-- Tudo roda dentro de uma transação desfeita no fim.
-- =====================================================================
begin;

-- Cadastro de teste (como dono do banco, sem RLS)
insert into pessoas (email, nome, papel) values
  ('admin@teste.rpe', 'Admin', 'admin'),
  ('ops@teste.rpe',   'Operacional', 'operacional'),
  ('le@teste.rpe',    'Leitura', 'leitura');
insert into imoveis (id, nome, valor_base, participacao, situacao, meta_yield)
  values ('TST1', 'Imóvel de teste', 1000000, 1, 'disponivel', 0.08);

create or replace function _como(p_email text) returns void language sql as $$
  select set_config('teste.jwt', case when p_email is null then '{}' else json_build_object('email', p_email)::text end, true)
$$;

do $$
declare n int;
begin
  -- 1. e-mail desconhecido entra e não lê nada
  set role authenticated;
  perform _como('intruso@fora.com');
  select count(*) into n from imoveis;
  if n <> 0 then raise exception 'FALHA: e-mail fora de pessoas leu % imóveis', n; end if;
  select count(*) into n from pessoas;
  if n <> 0 then raise exception 'FALHA: e-mail fora de pessoas leu pessoas'; end if;
  raise notice 'ok: e-mail fora de pessoas não lê imóveis nem pessoas';

  -- 2. leitura lê, não escreve
  perform _como('le@teste.rpe');
  select count(*) into n from v_imoveis_kpi where id = 'TST1';
  if n <> 1 then raise exception 'FALHA: leitura deveria ver o imóvel de teste, viu %', n; end if;
  begin
    insert into tarefas (titulo) values ('não deveria');
    raise exception 'FALHA: leitura criou tarefa';
  exception when insufficient_privilege then raise notice 'ok: leitura não cria tarefa'; end;
  begin
    update imoveis set valor_base = 1 where id = 'TST1';
    get diagnostics n = row_count;
    if n > 0 then raise exception 'FALHA: leitura editou imóvel'; end if;
    raise notice 'ok: leitura não edita imóvel (0 linhas)';
  end;

  -- 3. operacional edita contratos/tarefas/checklist/imóvel, não pessoas
  perform _como('ops@teste.rpe');
  insert into contratos (imovel_id, locatario, aluguel_mensal, status) values ('TST1', 'Inquilino', 10000, 'vigente');
  insert into tarefas (titulo, imovel_id, status) values ('Renovar seguro', 'TST1', 'semana');
  update checklist set status = 'ok' where imovel_id = 'TST1' and item = 'matricula';
  update imoveis set situacao = 'locado' where id = 'TST1';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALHA: operacional não editou o imóvel'; end if;
  raise notice 'ok: operacional cria contrato e tarefa, edita checklist e imóvel';
  begin
    insert into pessoas (email, nome, papel) values ('novo@teste.rpe', 'Novo', 'leitura');
    raise exception 'FALHA: operacional cadastrou pessoa';
  exception when insufficient_privilege then raise notice 'ok: operacional não cadastra pessoa'; end;
  begin
    delete from contratos where imovel_id = 'TST1';
    get diagnostics n = row_count;
    if n > 0 then raise exception 'FALHA: operacional apagou contrato'; end if;
    raise notice 'ok: operacional não apaga contrato';
  end;
  select count(*) into n from auditoria;
  if n <> 0 then raise exception 'FALHA: operacional leu auditoria'; end if;

  -- 4. KPI reflete o contrato: 10.000 × 12 / 1.000.000 = 12% > meta 8%
  perform _como('le@teste.rpe');
  if (select status_meta from v_imoveis_kpi where id = 'TST1') <> 'acima' then
    raise exception 'FALHA: status_meta deveria ser acima';
  end if;
  if (select yield_contratado from v_imoveis_kpi where id = 'TST1') <> 0.12 then
    raise exception 'FALHA: yield_contratado errado';
  end if;
  raise notice 'ok: yield contratado 12%% → acima da meta de 8%%';

  -- 5. admin cadastra pessoa, apaga contrato, lê auditoria
  perform _como('admin@teste.rpe');
  insert into pessoas (email, nome, papel) values ('novo@teste.rpe', 'Novo', 'leitura');
  delete from contratos where imovel_id = 'TST1';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FALHA: admin não apagou contrato'; end if;
  select count(*) into n from auditoria;
  if n < 5 then raise exception 'FALHA: auditoria vazia (%)', n; end if;
  raise notice 'ok: admin cadastra pessoa, apaga contrato e lê auditoria (% linhas)', n;

  -- 5b. regras da auditoria (0007)
  if (select count(*) from checklist where imovel_id = 'TST1') <> 8 then
    raise exception 'FALHA: imóvel novo deveria nascer com 8 itens de checklist';
  end if;
  raise notice 'ok: imóvel novo nasce com o checklist em falta';
  perform _como('ops@teste.rpe');
  begin
    update imoveis set ativo = false where id = 'TST1';
    raise exception 'FALHA: operacional desativou imóvel';
  exception when raise_exception then
    if sqlerrm not like 'só admin%' then raise; end if;
    raise notice 'ok: operacional não desativa imóvel nem muda participação';
  end;
  begin
    insert into movimentos (imovel_id, competencia, tipo, valor) values ('TST1', (date_trunc('month', now()) + interval '1 month')::date, 'receita', 1);
    raise exception 'FALHA: aceitou competência futura';
  exception when raise_exception then
    if sqlerrm not like 'competência%' then raise; end if;
    raise notice 'ok: competência futura recusada';
  end;
  begin
    insert into movimentos (imovel_id, competencia, tipo, valor) values ('TST1', date_trunc('month', now())::date, 'receita', -1);
    raise exception 'FALHA: aceitou valor negativo';
  exception when check_violation then raise notice 'ok: valor negativo recusado'; end;
  insert into tarefas (titulo, imovel_id, status, criado_por) values ('Autoria forjada', 'TST1', 'semana', (select id from pessoas where email = 'admin@teste.rpe'));
  if (select p.email from tarefas t join pessoas p on p.id = t.criado_por where t.titulo = 'Autoria forjada') <> 'ops@teste.rpe' then
    raise exception 'FALHA: criado_por veio do cliente';
  end if;
  raise notice 'ok: autoria carimbada pelo servidor';
  perform _como('admin@teste.rpe');
  update pessoas set ativo = false where papel = 'admin' and email <> 'admin@teste.rpe';  -- sobra um admin
  begin
    update pessoas set papel = 'leitura' where email = 'admin@teste.rpe';
    raise exception 'FALHA: ficou sem admin';
  exception when raise_exception then
    if sqlerrm not like 'não dá para remover%' then raise; end if;
    raise notice 'ok: último admin não se rebaixa';
  end;

  -- 6. anon não tem privilégio nenhum
  reset role;
  set role anon;
  perform _como(null);
  begin
    select count(*) into n from imoveis;
    raise exception 'FALHA: anon leu imóveis';
  exception when insufficient_privilege then raise notice 'ok: anon sem privilégio em imóveis'; end;
  begin
    select e_autorizado() into n;
    raise exception 'FALHA: anon executou função';
  exception when insufficient_privilege then raise notice 'ok: anon não executa funções'; end;
  reset role;
end $$;

rollback;
