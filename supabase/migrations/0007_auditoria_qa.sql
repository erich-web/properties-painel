-- =====================================================================
-- Migração 0007: correções da auditoria independente de QA/segurança
--
-- 1. meses_realizado() só conta meses fechados (o mês corrente parcial e
--    uma competência futura distorciam o realizado anualizado de todos).
-- 2. Validações que faltavam: valores não negativos, meta entre 0 e 1,
--    competência no máximo o mês corrente.
-- 3. Operacional não pode excluir imóvel (ativo=false), trocar o id nem a
--    participação — isso é decisão de admin.
-- 4. Nunca ficar sem admin ativo.
-- 5. Autoria vem do servidor (pessoa_atual()), não do cliente.
-- 6. Imóvel novo nasce com as 8 linhas do checklist em 'falta' (antes
--    aparecia verde por ausência).
-- 7. Auditoria também em dividas e mercado; authenticated perde TRUNCATE,
--    TRIGGER e REFERENCES.
-- 8. Storage: sobrescrever objeto só admin; bucket com limite de 50 MB e
--    tipos permitidos.
-- 9. View: status_meta sem valor base cai em 'fora_da_regua' (não em
--    'abaixo'); novas colunas receita_terceiros_mensal / yield_terceiros
--    para enxergar a renda sem o intra-grupo.
-- =====================================================================

-- 1. meses fechados
create or replace function meses_realizado()
returns integer language sql stable set search_path = public as $$
  select coalesce(count(distinct competencia), 0)::integer
  from movimentos
  where competencia >= date_trunc('month', now())::date - interval '12 months'
    and competencia <  date_trunc('month', now())::date
$$;

-- 2. validações
alter table imoveis
  add constraint imoveis_valores_chk check (
    coalesce(valor_min, 0) >= 0 and coalesce(valor_base, 0) >= 0 and coalesce(valor_max, 0) >= 0
    and coalesce(aluguel_mercado_mensal, 0) >= 0 and coalesce(divida_saldo, 0) >= 0
    and coalesce(iptu_anual, 0) >= 0 and coalesce(taxa_lixo, 0) >= 0 and coalesce(condominio_anual, 0) >= 0
    and coalesce(seguro_anual, 0) >= 0 and coalesce(outros_anual, 0) >= 0),
  add constraint imoveis_meta_chk check (meta_yield between 0 and 1);
alter table movimentos add constraint movimentos_valor_chk check (valor >= 0);
alter table dividas add constraint dividas_valores_chk check (
  coalesce(parcela_mensal, 0) >= 0 and coalesce(saldo_estimado, 0) >= 0 and coalesce(valor_original, 0) >= 0);

create or replace function validar_movimento()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.competencia > date_trunc('month', now())::date then
    raise exception 'competência % no futuro', to_char(new.competencia, 'MM/YYYY');
  end if;
  return new;
end $$;
create trigger val_movimentos before insert or update on movimentos for each row execute function validar_movimento();

-- 3. colunas de imóvel que só admin muda
create or replace function proteger_imovel()
returns trigger language plpgsql set search_path = public as $$
begin
  if not e_admin() and (new.id <> old.id or new.ativo is distinct from old.ativo
                        or new.participacao is distinct from old.participacao) then
    raise exception 'só admin muda id, ativo ou participação do imóvel';
  end if;
  return new;
end $$;
create trigger prot_imoveis before update on imoveis for each row execute function proteger_imovel();

-- 4. nunca sem admin
create or replace function garantir_admin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'DELETE' or new.papel <> 'admin' or not new.ativo)
     and old.papel = 'admin' and old.ativo
     and not exists (select 1 from pessoas where papel = 'admin' and ativo and id <> old.id) then
    raise exception 'não dá para remover o último admin ativo';
  end if;
  return coalesce(new, old);
end $$;
revoke execute on function garantir_admin() from public, anon, authenticated;
create trigger adm_pessoas before update or delete on pessoas for each row execute function garantir_admin();

-- 5. autoria pelo servidor
create or replace function carimbar_autor()
returns trigger language plpgsql set search_path = public as $$
declare p uuid := pessoa_atual();
begin
  if p is null then return new; end if;
  if tg_table_name = 'documentos' then new.enviado_por := p;
  elsif tg_table_name in ('tarefas', 'movimentos') then
    if tg_op = 'INSERT' then new.criado_por := p; else new.criado_por := old.criado_por; end if;
  elsif tg_table_name = 'alertas' then
    if new.estado is distinct from old.estado and new.estado <> 'aberto' then new.resolvido_por := p; new.resolvido_em := coalesce(new.resolvido_em, now()); end if;
  end if;
  return new;
end $$;
revoke execute on function carimbar_autor() from public, anon, authenticated;
create trigger aut_documentos before insert on documentos for each row execute function carimbar_autor();
create trigger aut_tarefas    before insert or update on tarefas    for each row execute function carimbar_autor();
create trigger aut_movimentos before insert or update on movimentos for each row execute function carimbar_autor();
create trigger aut_alertas    before update on alertas for each row execute function carimbar_autor();

-- 6. checklist nasce com o imóvel
create or replace function criar_checklist()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into checklist (imovel_id, item, status)
  select new.id, x, 'falta' from unnest(array['matricula','titulo','iptu','certidao','seguro','receita','licencas','pj']) x
  on conflict do nothing;
  return new;
end $$;
revoke execute on function criar_checklist() from public, anon, authenticated;
create trigger chk_imoveis after insert on imoveis for each row execute function criar_checklist();

-- 7. auditoria e privilégios
create trigger aud_dividas after insert or update or delete on dividas for each row execute function registrar_auditoria();
create trigger aud_mercado after insert or update or delete on mercado for each row execute function registrar_auditoria();
revoke truncate, trigger, references on all tables in schema public from authenticated;
alter default privileges in schema public revoke truncate, trigger, references on tables from authenticated;
revoke execute on function validar_movimento(), proteger_imovel() from public, anon, authenticated;

-- 8. storage
drop policy if exists documentos_storage_editar on storage.objects;
create policy documentos_storage_editar on storage.objects
  for update using (bucket_id = 'documentos' and e_admin())
  with check (bucket_id = 'documentos' and e_admin());
update storage.buckets set
  file_size_limit = 52428800,
  allowed_mime_types = array['application/pdf','image/jpeg','image/png','image/webp','image/heic',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain','text/csv']
where id = 'documentos';

-- 9. view
create or replace view v_imoveis_kpi with (security_invoker = true) as
with c as (
  select imovel_id,
         sum(aluguel_mensal) filter (where status in ('vigente','vencido','indeterminado') and tipo <> 'comodato') as receita_contratada_mensal,
         sum(aluguel_mensal) filter (where status in ('vigente','vencido','indeterminado') and tipo = 'intra_grupo')  as receita_intra_mensal,
         count(*) filter (where status in ('vigente','vencido','indeterminado'))              as n_contratos,
         count(*) filter (where status = 'vencido' or (fim is not null and fim < current_date and status = 'vigente')) as n_contratos_vencidos
  from contratos group by imovel_id
),
m as (
  select imovel_id,
         sum(valor) filter (where tipo = 'receita') as receita,
         sum(valor) filter (where tipo = 'receita' and intra_grupo) as receita_intra,
         sum(valor) filter (where tipo = 'opex')    as opex,
         sum(valor) filter (where tipo = 'capex')   as capex,
         sum(valor) filter (where tipo = 'divida')  as divida,
         sum(valor) filter (where tipo = 'aporte')  as aporte
  from movimentos
  where competencia >= date_trunc('month', now())::date - interval '12 months'
    and competencia <  date_trunc('month', now())::date
  group by imovel_id
),
k as (
  select imovel_id,
         count(*) filter (where status in ('pendente','vencido','falta')) as docs_pendentes,
         count(*) filter (where status = 'vencido')                       as docs_vencidos,
         count(*) filter (where status <> 'na')                           as docs_aplicaveis,
         round(100.0 * sum(case status when 'ok' then 1 when 'pendente' then 0.5 else 0 end)
               / nullif(count(*) filter (where status <> 'na'), 0)) as score_documental
  from checklist group by imovel_id
),
t as (
  select imovel_id, count(*) filter (where status in ('backlog','semana','andamento')) as tarefas_abertas
  from tarefas group by imovel_id
),
a as (
  select imovel_id, count(*) filter (where estado = 'aberto') as alertas_abertos,
         count(*) filter (where estado = 'aberto' and severidade = 'alta') as alertas_altos
  from alertas group by imovel_id
),
d as (
  select imovel_id, sum(coalesce(parcela_mensal, 0)) as parcela_mensal from dividas group by imovel_id
)
select
  i.*,
  case when i.custo_aquisicao is null then null
       else i.custo_aquisicao + i.custos_transacao + i.capex end                      as custo_total,
  case when i.custo_aquisicao is null then null
       else round((i.custo_aquisicao + i.custos_transacao + i.capex) * i.participacao, 2) end as custo_total_cota,
  round(i.valor_base * i.participacao, 2)                                              as valor_base_cota,
  round(i.valor_min  * i.participacao, 2)                                              as valor_min_cota,
  round(i.valor_max  * i.participacao, 2)                                              as valor_max_cota,
  round(i.valor_base * i.participacao - i.divida_saldo, 2)                             as equity,
  i.iptu_anual + i.taxa_lixo + i.condominio_anual + i.seguro_anual + i.outros_anual    as custo_carregamento_anual,
  coalesce(d.parcela_mensal, 0) * 12                                                   as servico_divida_anual,
  coalesce(c.receita_contratada_mensal, 0)                                             as receita_contratada_mensal,
  coalesce(c.receita_contratada_mensal, 0) * 12                                        as receita_contratada_anual,
  coalesce(c.receita_intra_mensal, 0) * 12                                             as receita_intra_anual,
  coalesce(c.n_contratos, 0)                                                           as n_contratos,
  coalesce(c.n_contratos_vencidos, 0)                                                  as n_contratos_vencidos,
  i.aluguel_mercado_mensal * 12                                                        as aluguel_mercado_anual,
  case when meses_realizado() > 0 then round(coalesce(m.receita, 0) * 12.0 / meses_realizado(), 2) end as receita_realizada_anual,
  case when meses_realizado() > 0 then round(coalesce(m.opex, 0)    * 12.0 / meses_realizado(), 2) end as opex_realizado_anual,
  case when meses_realizado() > 0 then round(coalesce(m.capex, 0)   * 12.0 / meses_realizado(), 2) end as capex_realizado_anual,
  case when meses_realizado() > 0 then round(coalesce(m.divida, 0)  * 12.0 / meses_realizado(), 2) end as divida_realizada_anual,
  case when meses_realizado() > 0 then round((coalesce(m.receita, 0) - coalesce(m.opex, 0)) * 12.0 / meses_realizado(), 2) end as noi_realizado_anual,
  case when i.valor_base > 0 and meses_realizado() > 0
       then round(((coalesce(m.receita, 0) - coalesce(m.opex, 0)) * 12.0 / meses_realizado()) / (i.valor_base * i.participacao), 4) end as yield_realizado,
  case when i.valor_base > 0
       then round((coalesce(c.receita_contratada_mensal, 0) * 12 - (i.iptu_anual + i.taxa_lixo + i.condominio_anual + i.seguro_anual + i.outros_anual)) / (i.valor_base * i.participacao), 4) end as yield_contratado,
  case when i.valor_base > 0
       then round((i.aluguel_mercado_mensal * 12 - (i.iptu_anual + i.taxa_lixo + i.condominio_anual + i.seguro_anual + i.outros_anual)) / (i.valor_base * i.participacao), 4) end as yield_mercado,
  case when i.valor_base > 0
       then round((coalesce(c.receita_contratada_mensal, 0) * 12 - (i.iptu_anual + i.taxa_lixo + i.condominio_anual + i.seguro_anual + i.outros_anual)) / (i.valor_base * i.participacao) - i.meta_yield, 4) end as gap_meta,
  case
    when i.uso_proprio then 'uso_proprio'
    when i.situacao in ('participacao','financeiro','obra','terreno') then 'fora_da_regua'
    when coalesce(i.valor_base, 0) <= 0 then 'fora_da_regua'
    when coalesce(c.receita_contratada_mensal, 0) = 0 then 'sem_renda'
    when (coalesce(c.receita_contratada_mensal, 0) * 12 - (i.iptu_anual + i.taxa_lixo + i.condominio_anual + i.seguro_anual + i.outros_anual)) / (i.valor_base * i.participacao) >= i.meta_yield then 'acima'
    else 'abaixo'
  end                                                                                  as status_meta,
  coalesce(k.docs_pendentes, 0)   as docs_pendentes,
  coalesce(k.docs_vencidos, 0)    as docs_vencidos,
  coalesce(k.docs_aplicaveis, 0)  as docs_aplicaveis,
  k.score_documental,
  coalesce(t.tarefas_abertas, 0)  as tarefas_abertas,
  coalesce(a.alertas_abertos, 0)  as alertas_abertos,
  coalesce(a.alertas_altos, 0)    as alertas_altos,
  -- renda e yield sem o intra-grupo (visão "de terceiros")
  coalesce(c.receita_contratada_mensal, 0) - coalesce(c.receita_intra_mensal, 0)      as receita_terceiros_mensal,
  case when i.valor_base > 0
       then round(((coalesce(c.receita_contratada_mensal, 0) - coalesce(c.receita_intra_mensal, 0)) * 12 - (i.iptu_anual + i.taxa_lixo + i.condominio_anual + i.seguro_anual + i.outros_anual)) / (i.valor_base * i.participacao), 4) end as yield_terceiros
from imoveis i
left join c on c.imovel_id = i.id
left join m on m.imovel_id = i.id
left join k on k.imovel_id = i.id
left join t on t.imovel_id = i.id
left join a on a.imovel_id = i.id
left join d on d.imovel_id = i.id
where i.ativo;
