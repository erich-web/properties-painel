-- =====================================================================
-- Migração 0003: visões do painel
--
-- As visões herdam a RLS das tabelas (security_invoker), então quem não
-- lê imoveis também não lê v_imoveis_kpi.
-- =====================================================================

-- Quantos meses de tesouraria existem na janela de 12 meses: é por eles
-- que o realizado é anualizado (jan–set = 9 meses → × 12/9).
create or replace function meses_realizado()
returns integer language sql stable set search_path = public as $$
  select coalesce(count(distinct competencia), 0)::integer
  from movimentos
  where competencia >= date_trunc('month', now())::date - interval '12 months'
$$;

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
  -- realizado (tesouraria), anualizado pelos meses disponíveis
  case when meses_realizado() > 0 then round(coalesce(m.receita, 0) * 12.0 / meses_realizado(), 2) end as receita_realizada_anual,
  case when meses_realizado() > 0 then round(coalesce(m.opex, 0)    * 12.0 / meses_realizado(), 2) end as opex_realizado_anual,
  case when meses_realizado() > 0 then round(coalesce(m.capex, 0)   * 12.0 / meses_realizado(), 2) end as capex_realizado_anual,
  case when meses_realizado() > 0 then round(coalesce(m.divida, 0)  * 12.0 / meses_realizado(), 2) end as divida_realizada_anual,
  case when meses_realizado() > 0 then round((coalesce(m.receita, 0) - coalesce(m.opex, 0)) * 12.0 / meses_realizado(), 2) end as noi_realizado_anual,
  -- yields sobre o valor base da cota
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
    when coalesce(c.receita_contratada_mensal, 0) = 0 then 'sem_renda'
    when i.valor_base > 0 and (coalesce(c.receita_contratada_mensal, 0) * 12 - (i.iptu_anual + i.taxa_lixo + i.condominio_anual + i.seguro_anual + i.outros_anual)) / (i.valor_base * i.participacao) >= i.meta_yield then 'acima'
    else 'abaixo'
  end                                                                                  as status_meta,
  coalesce(k.docs_pendentes, 0)   as docs_pendentes,
  coalesce(k.docs_vencidos, 0)    as docs_vencidos,
  coalesce(k.docs_aplicaveis, 0)  as docs_aplicaveis,
  k.score_documental,
  coalesce(t.tarefas_abertas, 0)  as tarefas_abertas,
  coalesce(a.alertas_abertos, 0)  as alertas_abertos,
  coalesce(a.alertas_altos, 0)    as alertas_altos
from imoveis i
left join c on c.imovel_id = i.id
left join m on m.imovel_id = i.id
left join k on k.imovel_id = i.id
left join t on t.imovel_id = i.id
left join a on a.imovel_id = i.id
left join d on d.imovel_id = i.id
where i.ativo;

-- Agenda de contratos: vencimentos e reajustes nos próximos meses.
create or replace view v_contratos_agenda with (security_invoker = true) as
select
  ct.*,
  i.nome as imovel_nome,
  case when ct.fim is not null then (ct.fim - current_date) end as dias_para_fim,
  case
    when ct.mes_reajuste is null then null
    when make_date(extract(year from current_date)::int, ct.mes_reajuste, 1) >= date_trunc('month', current_date)::date
      then make_date(extract(year from current_date)::int, ct.mes_reajuste, 1)
    else make_date(extract(year from current_date)::int + 1, ct.mes_reajuste, 1)
  end as proximo_reajuste,
  (ct.status = 'vencido' or (ct.fim is not null and ct.fim < current_date and ct.status = 'vigente')) as vencido
from contratos ct
join imoveis i on i.id = ct.imovel_id;

-- Estoque: o que está disponível (ou parcialmente vago) para locação.
create or replace view v_estoque with (security_invoker = true) as
select k.id, k.nome, k.cidade, k.regiao, k.tipo, k.situacao, k.valor_base_cota, k.aluguel_mercado_mensal,
       k.aluguel_mercado_anual, k.custo_carregamento_anual, k.servico_divida_anual, k.yield_mercado, k.recomendacao, k.acao,
       k.n_contratos
from v_imoveis_kpi k
where k.situacao in ('disponivel', 'parcial', 'uso_grupo');

-- Caixa mensal por imóvel (para os gráficos da aba Caixa).
create or replace view v_caixa_mensal with (security_invoker = true) as
select imovel_id, competencia,
       sum(valor) filter (where tipo = 'receita') as receita,
       sum(valor) filter (where tipo = 'receita' and intra_grupo) as receita_intra,
       sum(valor) filter (where tipo = 'opex')    as opex,
       sum(valor) filter (where tipo = 'capex')   as capex,
       sum(valor) filter (where tipo = 'divida')  as divida,
       sum(valor) filter (where tipo = 'aporte')  as aporte
from movimentos
group by imovel_id, competencia;
