-- =====================================================================
-- Migração 0008: desempenho das políticas e da view de KPI
--
-- Diagnóstico no projeto real: v_imoveis_kpi levava ~20 s e estourava o
-- statement_timeout do PostgREST. Duas causas:
--   1. e_autorizado()/pode_editar()/e_admin() nas políticas eram avaliadas
--      linha a linha (função STABLE em qual simples). Escritas como
--      (select f()) viram InitPlan: uma avaliação por comando.
--   2. meses_realizado() aparecia ~12 vezes por linha na view e cada
--      chamada varria movimentos (com a política linha a linha de cima).
--      Agora é calculado uma vez, num cross join.
-- =====================================================================

alter policy alertas_criar on alertas with check ((select pode_editar()));
alter policy alertas_editar on alertas using ((select pode_editar())) with check ((select pode_editar()));
alter policy alertas_excluir on alertas using ((select e_admin()));
alter policy alertas_ler on alertas using ((select e_autorizado()));
alter policy auditoria_ler on auditoria using ((select e_admin()));
alter policy checklist_criar on checklist with check ((select pode_editar()));
alter policy checklist_editar on checklist using ((select pode_editar())) with check ((select pode_editar()));
alter policy checklist_excluir on checklist using ((select e_admin()));
alter policy checklist_ler on checklist using ((select e_autorizado()));
alter policy contratos_criar on contratos with check ((select pode_editar()));
alter policy contratos_editar on contratos using ((select pode_editar())) with check ((select pode_editar()));
alter policy contratos_excluir on contratos using ((select e_admin()));
alter policy contratos_ler on contratos using ((select e_autorizado()));
alter policy dividas_admin on dividas using ((select e_admin())) with check ((select e_admin()));
alter policy dividas_ler on dividas using ((select e_autorizado()));
alter policy documentos_criar on documentos with check ((select pode_editar()));
alter policy documentos_editar on documentos using ((select pode_editar())) with check ((select pode_editar()));
alter policy documentos_excluir on documentos using ((select e_admin()));
alter policy documentos_ler on documentos using ((select e_autorizado()));
alter policy imoveis_editar on imoveis using ((select pode_editar())) with check ((select pode_editar()));
alter policy imoveis_excluir on imoveis using ((select e_admin()));
alter policy imoveis_incluir on imoveis with check ((select e_admin()));
alter policy imoveis_ler on imoveis using ((select e_autorizado()));
alter policy mercado_admin on mercado using ((select e_admin())) with check ((select e_admin()));
alter policy mercado_ler on mercado using ((select e_autorizado()));
alter policy movimentos_criar on movimentos with check ((select pode_editar()));
alter policy movimentos_editar on movimentos using ((select pode_editar())) with check ((select pode_editar()));
alter policy movimentos_excluir on movimentos using ((select e_admin()));
alter policy movimentos_ler on movimentos using ((select e_autorizado()));
alter policy pessoas_admin on pessoas using ((select e_admin())) with check ((select e_admin()));
alter policy pessoas_ler on pessoas using ((select e_autorizado()));
alter policy tarefas_criar on tarefas with check ((select pode_editar()));
alter policy tarefas_editar on tarefas using ((select pode_editar())) with check ((select pode_editar()));
alter policy tarefas_excluir on tarefas using ((select e_admin()));
alter policy tarefas_ler on tarefas using ((select e_autorizado()));

alter policy documentos_storage_ler    on storage.objects using (bucket_id = 'documentos' and (select e_autorizado()));
alter policy documentos_storage_subir  on storage.objects with check (bucket_id = 'documentos' and (select pode_editar()));
alter policy documentos_storage_editar on storage.objects using (bucket_id = 'documentos' and (select e_admin())) with check (bucket_id = 'documentos' and (select e_admin()));
alter policy documentos_storage_apagar on storage.objects using (bucket_id = 'documentos' and (select e_admin()));

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
),
n as (
  select meses_realizado() as meses
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
  case when n.meses > 0 then round(coalesce(m.receita, 0) * 12.0 / n.meses, 2) end as receita_realizada_anual,
  case when n.meses > 0 then round(coalesce(m.opex, 0)    * 12.0 / n.meses, 2) end as opex_realizado_anual,
  case when n.meses > 0 then round(coalesce(m.capex, 0)   * 12.0 / n.meses, 2) end as capex_realizado_anual,
  case when n.meses > 0 then round(coalesce(m.divida, 0)  * 12.0 / n.meses, 2) end as divida_realizada_anual,
  case when n.meses > 0 then round((coalesce(m.receita, 0) - coalesce(m.opex, 0)) * 12.0 / n.meses, 2) end as noi_realizado_anual,
  case when i.valor_base > 0 and n.meses > 0
       then round(((coalesce(m.receita, 0) - coalesce(m.opex, 0)) * 12.0 / n.meses) / (i.valor_base * i.participacao), 4) end as yield_realizado,
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
cross join n
left join c on c.imovel_id = i.id
left join m on m.imovel_id = i.id
left join k on k.imovel_id = i.id
left join t on t.imovel_id = i.id
left join a on a.imovel_id = i.id
left join d on d.imovel_id = i.id
where i.ativo;
