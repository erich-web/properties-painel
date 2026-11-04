-- =====================================================================
-- RPE Properties — Monitor de Imóveis (painel de gestão)
-- Migração 0001: fundação
--
-- O painel é uma casca: o arquivo HTML não carrega número nenhum. Quem
-- entra com link mágico e tem e-mail na tabela pessoas lê o que o papel
-- permite; quem não tem, entra e não vê uma linha (ver 0002_rls.sql).
--
-- Decisões de modelagem:
-- 1. imoveis.id é o código curto usado no monitor (VC, MAC164, CASC…),
--    porque é assim que o time fala dos ativos e como a planilha, o
--    relatório e os documentos já se referem a eles.
-- 2. Receita contratada vem de contratos; receita realizada vem de
--    movimentos (tesouraria, mês a mês). As duas convivem na view de KPI
--    para o painel mostrar "o que deveria render" e "o que rendeu".
-- 3. uso_proprio separa o patrimônio de uso da família do "fundo": esses
--    imóveis têm aluguel de mercado só como custo de oportunidade e não
--    entram na régua de meta de rentabilidade.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
create type papel_tipo as enum ('admin', 'operacional', 'leitura');

create type situacao_tipo as enum (
  'locado',        -- gera renda com contrato(s)
  'parcial',       -- galeria/prédio com unidades vagas
  'disponivel',    -- em estoque: pronto para locar (ou vender)
  'uso_proprio',   -- patrimônio de uso da família
  'uso_grupo',     -- ocupado por empresa do grupo sem contrato
  'obra',          -- em construção / na planta
  'terreno',       -- lote sem uso
  'participacao',  -- SPE / Ltda / SCP / SIC
  'financeiro'     -- aplicação / caixa
);

create type contrato_tipo   as enum ('locacao', 'temporada', 'comodato', 'intra_grupo', 'arrendamento');
create type contrato_status as enum ('vigente', 'vencido', 'indeterminado', 'minuta', 'encerrado');

create type doc_categoria as enum (
  'matricula', 'titulo', 'iptu', 'certidao', 'seguro', 'contrato',
  'licenca', 'financiamento', 'societario', 'obra', 'laudo', 'outro'
);
create type item_status as enum ('ok', 'pendente', 'vencido', 'falta', 'na');

create type tarefa_status     as enum ('backlog', 'semana', 'andamento', 'concluida', 'cancelada');
create type tarefa_prioridade as enum ('alta', 'media', 'baixa');

create type movimento_tipo as enum ('receita', 'opex', 'capex', 'divida', 'aporte');

create type alerta_severidade as enum ('alta', 'media', 'baixa');
create type alerta_estado     as enum ('aberto', 'resolvido');

-- ---------------------------------------------------------------------
-- Pessoas — quem pode entrar, e com que papel
-- ---------------------------------------------------------------------
create table pessoas (
  id            uuid primary key default gen_random_uuid(),
  email         text not null unique check (email = lower(email)),
  nome          text not null,
  papel         papel_tipo not null default 'leitura',
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  ultimo_acesso timestamptz
);

-- ---------------------------------------------------------------------
-- Identidade — base de todas as políticas de RLS
-- ---------------------------------------------------------------------
create or replace function pessoa_atual()
returns uuid language sql stable security definer set search_path = public
as $$
  select p.id from pessoas p
  where p.email = lower(coalesce(auth.jwt() ->> 'email', ''))
    and p.ativo
  limit 1
$$;

create or replace function e_autorizado()
returns boolean language sql stable security definer set search_path = public
as $$ select pessoa_atual() is not null $$;

create or replace function papel_atual()
returns papel_tipo language sql stable security definer set search_path = public
as $$ select p.papel from pessoas p where p.id = pessoa_atual() $$;

create or replace function e_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(papel_atual() = 'admin', false) $$;

create or replace function pode_editar()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(papel_atual() in ('admin', 'operacional'), false) $$;

-- Marca o último acesso sem exigir permissão de update na tabela.
create or replace function registrar_acesso()
returns void language sql security definer set search_path = public
as $$ update pessoas set ultimo_acesso = now() where id = pessoa_atual() $$;

-- ---------------------------------------------------------------------
-- Imóveis (e demais ativos do radar: participações e posições financeiras)
-- Valores a 100% do ativo; a cota do grupo sai de participacao.
-- ---------------------------------------------------------------------
create table imoveis (
  id                 text primary key check (id ~ '^[A-Z0-9]{2,8}$'),
  nome               text not null,
  cidade             text,
  uf                 text,
  regiao             text,
  bairro             text,
  tipo               text,
  endereco           text,
  titular            text,
  titular_tipo       text,                       -- 'PF', 'PJ', 'PJ (50%)', 'PJ (offshore)'…
  participacao       numeric(8,6) not null default 1 check (participacao > 0 and participacao <= 1),
  uso_proprio        boolean not null default false,
  situacao           situacao_tipo not null default 'disponivel',
  matricula          text,
  inscricao          text,
  area_terreno       numeric(12,2),
  area_construida    numeric(12,2),
  area_privativa     numeric(12,2),
  data_aquisicao     text,                       -- texto: às vezes só o ano/mês é conhecido
  custo_aquisicao    numeric(14,2),
  custos_transacao   numeric(14,2) not null default 0,
  capex              numeric(14,2) not null default 0,
  valor_venal        numeric(14,2),
  ano_venal          integer,
  iptu_anual         numeric(14,2) not null default 0,
  taxa_lixo          numeric(14,2) not null default 0,
  condominio_anual   numeric(14,2) not null default 0,
  seguro_anual       numeric(14,2) not null default 0,
  outros_anual       numeric(14,2) not null default 0,
  divida_saldo       numeric(14,2) not null default 0,
  aluguel_mercado_mensal numeric(14,2) not null default 0,   -- o que renderia a mercado
  valor_min          numeric(14,2),
  valor_base         numeric(14,2),
  valor_max          numeric(14,2),
  confianca          text,
  metodo             text,
  uso                text,
  status_estrategico text,
  acao               text,
  recomendacao       text,                       -- 'manter' | 'alugar' | 'vender' | 'decidir' | 'regularizar'
  recomendacao_motivo text,
  prioridade         integer not null default 3 check (prioridade between 1 and 3),
  meta_yield         numeric(6,4) not null default 0.08,     -- meta de NOI / valor base
  fontes             text,
  ativo              boolean not null default true,
  atualizado_em      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Contratos de locação (uma linha por unidade/locatário)
-- ---------------------------------------------------------------------
create table contratos (
  id               uuid primary key default gen_random_uuid(),
  imovel_id        text not null references imoveis(id),
  unidade          text,                         -- loja/sala/apto, quando o imóvel tem várias
  locatario        text not null,
  tipo             contrato_tipo not null default 'locacao',
  inicio           date,
  fim              date,
  aluguel_mensal   numeric(14,2) not null default 0 check (aluguel_mensal >= 0),
  encargos_mensais numeric(14,2) not null default 0,
  indice           text,                         -- IGP-M, IPCA…
  mes_reajuste     integer check (mes_reajuste between 1 and 12),
  ultimo_reajuste  date,
  garantia         text,
  status           contrato_status not null default 'vigente',
  observacoes      text,
  documento_id     uuid,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
create index contratos_imovel_idx on contratos (imovel_id, status);

-- ---------------------------------------------------------------------
-- Documentos — o índice do acervo. O arquivo em si fica no Storage
-- (bucket privado 'documentos', caminho em caminho_storage); documentos
-- ainda não subidos têm só caminho_original (a pasta no Mac).
-- ---------------------------------------------------------------------
create table documentos (
  id               uuid primary key default gen_random_uuid(),
  imovel_id        text references imoveis(id),  -- null = documento da holding
  categoria        doc_categoria not null default 'outro',
  titulo           text not null,
  descricao        text,
  caminho_storage  text unique,
  nome_arquivo     text,
  tamanho_bytes    bigint,
  mime             text,
  emitido_em       date,
  validade         date,
  caminho_original text,
  origem           text not null default 'upload' check (origem in ('pasta', 'upload')),
  enviado_por      uuid references pessoas(id),
  criado_em        timestamptz not null default now()
);
create index documentos_imovel_idx on documentos (imovel_id, categoria);

alter table contratos
  add constraint contratos_documento_fk foreign key (documento_id) references documentos(id) on delete set null;

-- ---------------------------------------------------------------------
-- Checklist documental — um status por item e imóvel
-- ---------------------------------------------------------------------
create table checklist (
  imovel_id     text not null references imoveis(id),
  item          text not null check (item in ('matricula','titulo','iptu','certidao','seguro','receita','licencas','pj')),
  status        item_status not null default 'falta',
  observacao    text,
  documento_id  uuid references documentos(id) on delete set null,
  atualizado_em timestamptz not null default now(),
  primary key (imovel_id, item)
);

-- ---------------------------------------------------------------------
-- Tarefas — semana e backlog (as do CFO nascem com origem 'cfo')
-- ---------------------------------------------------------------------
create table tarefas (
  id             uuid primary key default gen_random_uuid(),
  titulo         text not null,
  descricao      text,
  imovel_id      text references imoveis(id),
  responsavel_id uuid references pessoas(id),
  prioridade     tarefa_prioridade not null default 'media',
  status         tarefa_status not null default 'backlog',
  prazo          date,
  categoria      text,                           -- Documental, Contrato, Financeiro, Societário, Obra…
  origem         text not null default 'manual' check (origem in ('cfo', 'manual')),
  impacto_anual  numeric(14,2),
  ordem          integer not null default 100,
  criado_por     uuid references pessoas(id),
  criado_em      timestamptz not null default now(),
  concluida_em   timestamptz
);
create index tarefas_status_idx on tarefas (status, prazo);

-- ---------------------------------------------------------------------
-- Movimentos — caixa realizado por imóvel e mês (tesouraria)
-- ---------------------------------------------------------------------
create table movimentos (
  id          uuid primary key default gen_random_uuid(),
  imovel_id   text references imoveis(id),       -- null = estrutura/holding
  competencia date not null check (extract(day from competencia) = 1),
  tipo        movimento_tipo not null,
  grupo       text,
  subgrupo    text,
  valor       numeric(14,2) not null,            -- receita > 0; despesas > 0 (o tipo diz o sinal)
  intra_grupo boolean not null default false,
  descricao   text,
  origem      text not null default 'manual',
  criado_por  uuid references pessoas(id),
  criado_em   timestamptz not null default now()
);
create index movimentos_imovel_idx on movimentos (imovel_id, competencia);

-- ---------------------------------------------------------------------
-- Dívidas, alertas e referências de mercado
-- ---------------------------------------------------------------------
create table dividas (
  id               uuid primary key default gen_random_uuid(),
  imovel_id        text not null references imoveis(id),
  credor           text not null,
  contrato         text,
  valor_original   numeric(14,2),
  sistema          text,
  taxa             text,
  parcela_mensal   numeric(14,2),
  primeira_parcela text,
  ultima_parcela   text,
  saldo_estimado   numeric(14,2),
  obs              text
);

create table alertas (
  id            uuid primary key default gen_random_uuid(),
  imovel_id     text references imoveis(id),     -- null = portfólio
  severidade    alerta_severidade not null default 'media',
  tema          text,
  prazo         date,
  texto         text not null,
  estado        alerta_estado not null default 'aberto',
  resolvido_em  timestamptz,
  resolvido_por uuid references pessoas(id),
  criado_em     timestamptz not null default now()
);

create table mercado (
  id        text primary key,
  imovel_id text references imoveis(id),
  descricao text not null,
  valor     numeric(16,4),
  unidade   text,
  fonte     text,
  url       text,
  data      text
);

-- ---------------------------------------------------------------------
-- Auditoria — quem mudou o quê
-- ---------------------------------------------------------------------
create table auditoria (
  id          bigint generated always as identity primary key,
  pessoa_id   uuid,
  ator_email  text,
  acao        text not null,
  entidade    text not null,
  entidade_id text,
  antes       jsonb,
  depois      jsonb,
  criado_em   timestamptz not null default now()
);
create index auditoria_entidade_idx on auditoria (entidade, entidade_id, criado_em desc);

create or replace function registrar_auditoria()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_antes jsonb; v_depois jsonb;
begin
  if tg_op = 'DELETE' then v_antes := to_jsonb(old);
  elsif tg_op = 'INSERT' then v_depois := to_jsonb(new);
  else v_antes := to_jsonb(old); v_depois := to_jsonb(new);
  end if;
  insert into auditoria (pessoa_id, ator_email, acao, entidade, entidade_id, antes, depois)
  values (pessoa_atual(), coalesce(auth.jwt() ->> 'email', 'sistema'), tg_op, tg_table_name,
          coalesce(v_depois ->> 'id', v_antes ->> 'id', v_depois ->> 'imovel_id', v_antes ->> 'imovel_id'),
          v_antes, v_depois);
  return coalesce(new, old);
end $$;

create trigger aud_pessoas    after insert or update or delete on pessoas    for each row execute function registrar_auditoria();
create trigger aud_imoveis    after insert or update or delete on imoveis    for each row execute function registrar_auditoria();
create trigger aud_contratos  after insert or update or delete on contratos  for each row execute function registrar_auditoria();
create trigger aud_documentos after insert or update or delete on documentos for each row execute function registrar_auditoria();
create trigger aud_checklist  after insert or update or delete on checklist  for each row execute function registrar_auditoria();
create trigger aud_tarefas    after insert or update or delete on tarefas    for each row execute function registrar_auditoria();
create trigger aud_movimentos after insert or update or delete on movimentos for each row execute function registrar_auditoria();
create trigger aud_alertas    after insert or update or delete on alertas    for each row execute function registrar_auditoria();

-- Carimbo de atualização
create or replace function carimbar_atualizado()
returns trigger language plpgsql as $$
begin new.atualizado_em := now(); return new; end $$;

create trigger ts_imoveis   before update on imoveis   for each row execute function carimbar_atualizado();
create trigger ts_contratos before update on contratos for each row execute function carimbar_atualizado();
create trigger ts_checklist before update on checklist for each row execute function carimbar_atualizado();

-- Tarefa concluída recebe a data; reaberta perde.
create or replace function carimbar_conclusao()
returns trigger language plpgsql as $$
begin
  if new.status = 'concluida' and (old.status is distinct from 'concluida') then new.concluida_em := now();
  elsif new.status <> 'concluida' then new.concluida_em := null;
  end if;
  return new;
end $$;
create trigger ts_tarefas before update on tarefas for each row execute function carimbar_conclusao();
