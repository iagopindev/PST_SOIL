-- =====================================================================
--  APP RELATORIO DE VISITAS TECNICAS  ·  Parceria Nescafe x SOIL
--  Backend Supabase (PostgreSQL) — DDL + RLS + VIEWs + SEEDS
--  Gerado a partir da planilha 01_LS_APP.xlsx
--  COMO USAR: cole este arquivo inteiro no SQL Editor do Supabase e RUN.
-- =====================================================================

-- 0. EXTENSOES ---------------------------------------------------------
create extension if not exists "pgcrypto";
create extension if not exists "unaccent";

-- 1. ENUMS -------------------------------------------------------------
do $$ begin create type user_role as enum ('consultor','admin');
exception when duplicate_object then null; end $$;
do $$ begin create type user_status as enum ('pendente','aprovado','bloqueado');
exception when duplicate_object then null; end $$;
do $$ begin create type tipo_adubacao as enum ('correcao','manutencao');
exception when duplicate_object then null; end $$;
do $$ begin create type unidade_dose as enum ('kg/ha','L/ha');
exception when duplicate_object then null; end $$;

-- 2. NORMALIZACAO p/ nome de arquivo PDF -------------------------------
create or replace function norm_token(txt text)
returns text language sql immutable as $fn$
  select regexp_replace(initcap(coalesce(unaccent(txt),'')),'[^A-Za-z0-9]','','g')
$fn$;

-- 3. CATALOGOS ---------------------------------------------------------
create table if not exists fert_cafe (
  id bigserial primary key, nome text not null unique,
  n numeric(6,2) default 0, p2o5 numeric(6,2) default 0, k2o numeric(6,2) default 0,
  ca numeric(6,2) default 0, mg numeric(6,2) default 0, s numeric(6,2) default 0,
  b numeric(6,2) default 0, cu numeric(6,2) default 0, fe numeric(6,2) default 0,
  mn numeric(6,2) default 0, mo numeric(6,2) default 0, zn numeric(6,2) default 0,
  obs text, fonte text);

create table if not exists cpd_cafe (
  id bigserial primary key, molecula text not null unique,
  classes text, alvos text, fonte text, data_consulta text, nota text);

create table if not exists herb_cafe (
  id bigserial primary key, molecula text not null unique,
  classe text, grupo_mecanismo text, seletividade text,
  daninhas text, obs text, fonte text, data_consulta text);

-- 4. NUCLEO ------------------------------------------------------------
create table if not exists consultores_autorizados (
  email text primary key, nome text not null);

create table if not exists consultores (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null, email text not null unique,
  role user_role not null default 'consultor',
  status user_status not null default 'pendente',
  criado_em timestamptz not null default now());

create table if not exists fazendas (
  id uuid primary key default gen_random_uuid(),
  produtor text not null, fazenda text not null,
  cidade text, estado text, cafeeira text,
  consultor_email text, criada_em_campo boolean not null default false,
  created_by uuid references consultores(id) on delete set null,
  criado_em timestamptz not null default now(),
  display_nome text generated always as (produtor || ' - ' || fazenda) stored,
  unique (produtor, fazenda));

create table if not exists consultor_fazenda (
  consultor_id uuid not null references consultores(id) on delete cascade,
  fazenda_id uuid not null references fazendas(id) on delete cascade,
  primary key (consultor_id, fazenda_id));

create table if not exists talhoes (
  id uuid primary key default gen_random_uuid(),
  fazenda_id uuid not null references fazendas(id) on delete cascade,
  nome text not null,
  area_ha numeric(10,2) not null,          -- OBRIGATORIO
  criado_por uuid references consultores(id) on delete set null,
  criado_em timestamptz not null default now());

-- 5. VISITAS (imutavel) ------------------------------------------------
create table if not exists visitas (
  id uuid primary key default gen_random_uuid(),
  fazenda_id uuid not null references fazendas(id) on delete cascade,
  talhao_id uuid references talhoes(id) on delete set null,
  consultor_id uuid not null references consultores(id) on delete set null,
  inicio_em timestamptz not null,
  responsavel text, motivo text, tipo_adub tipo_adubacao,
  obs_nutricao text, obs_cpd text, obs_herb text,
  criado_em timestamptz not null default now());

create table if not exists visita_observacoes (
  id bigserial primary key,
  visita_id uuid not null references visitas(id) on delete cascade,
  categoria text not null, observado text, acao text);

create table if not exists visita_nutricao (
  id bigserial primary key,
  visita_id uuid not null references visitas(id) on delete cascade,
  fert_id bigint references fert_cafe(id), fert_nome text,
  dose_kg_ha numeric(10,2) not null,
  n_kg_ha numeric(12,4) default 0, p2o5_kg_ha numeric(12,4) default 0, k2o_kg_ha numeric(12,4) default 0);

create table if not exists visita_cpd (
  id bigserial primary key,
  visita_id uuid not null references visitas(id) on delete cascade,
  cpd_id bigint references cpd_cafe(id), cpd_nome text,
  dose numeric(10,2) not null, unidade unidade_dose not null default 'L/ha');

create table if not exists visita_herb (
  id bigserial primary key,
  visita_id uuid not null references visitas(id) on delete cascade,
  herb_id bigint references herb_cafe(id), herb_nome text,
  dose numeric(10,2) not null, unidade unidade_dose not null default 'L/ha');

create table if not exists visita_recomendacoes_check (
  id bigserial primary key,
  visita_id uuid not null references visitas(id) on delete cascade,
  origem_visita_id uuid references visitas(id) on delete set null,
  tipo text not null, descricao text not null, seguida boolean not null default false);

create table if not exists evidencias_meta (
  id bigserial primary key,
  visita_id uuid not null references visitas(id) on delete cascade,
  capturado_em timestamptz, latitude numeric(10,6), longitude numeric(10,6),
  ref_local text, descricao text);

create index if not exists idx_cf_consultor on consultor_fazenda(consultor_id);
create index if not exists idx_cf_fazenda   on consultor_fazenda(fazenda_id);
create index if not exists idx_vis_fazenda  on visitas(fazenda_id);
create index if not exists idx_vis_inicio   on visitas(inicio_em);
create index if not exists idx_talhao_faz   on talhoes(fazenda_id);

-- =====================================================================
-- 6. SEEDS DOS CATALOGOS
-- =====================================================================

-- FERT_CAFE (51)
insert into fert_cafe (nome,n,p2o5,k2o,ca,mg,s,b,cu,fe,mn,mo,zn,obs,fonte) values
('Ureia',45,0,0,0,0,0,0,0,0,0,0,0,'Fonte nitrogenada; teor típico 45–46% N','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Ureia protegida com inibidor de urease',45,0,0,0,0,0,0,0,0,0,0,0,'Fonte nitrogenada estabilizada; garantia depende do fabricante','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Ureia revestida/liberação controlada',44,0,0,0,0,0,0,0,0,0,0,0,'Teor representativo; varia com o revestimento','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Sulfato de amônio',21,0,0,0,0,24,0,0,0,0,0,0,'Fonte de N e S','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Nitrato de amônio',33,0,0,0,0,0,0,0,0,0,0,0,'Teor típico 32–34% N','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Nitrato de cálcio',15.5,0,0,19,0,0,0,0,0,0,0,0,'Fonte solúvel de N e Ca','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Nitrato de magnésio',11,0,0,0,9.5,0,0,0,0,0,0,0,'Fonte solúvel de N e Mg','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('MAP — fosfato monoamônico',11,52,0,0,0,0,0,0,0,0,0,0,'Fonte concentrada de N e P2O5','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('DAP — fosfato diamônico',18,46,0,0,0,0,0,0,0,0,0,0,'Fonte concentrada de N e P2O5','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Superfosfato simples',0,18,0,16,0,10,0,0,0,0,0,0,'Garantias típicas; composição varia conforme origem','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Superfosfato triplo',0,41,0,10,0,1,0,0,0,0,0,0,'Garantias representativas','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Fosfato natural reativo',0,29,0,30,0,0,0,0,0,0,0,0,'P2O5 total representativo; solubilidade varia','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Termofosfato magnesiano',0,17,0,18,7,4,0,0,0,0,0,0,'Garantias representativas','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Cloreto de potássio',0,0,60,0,0,0,0,0,0,0,0,0,'Fonte de K; contém cloreto','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Sulfato de potássio',0,0,50,0,0,17,0,0,0,0,0,0,'Fonte de K e S; baixo cloreto','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Nitrato de potássio',13,0,44,0,0,0,0,0,0,0,0,0,'Fonte solúvel de N e K','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Sulfato de potássio e magnésio',0,0,22,0,11,22,0,0,0,0,0,0,'Langbeinita; teores típicos','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Sulfato de magnésio',0,0,0,0,9,12,0,0,0,0,0,0,'Kieserita/heptaidratado variam; valores representativos','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Gesso agrícola',0,0,0,22,0,17,0,0,0,0,0,0,'Condicionador e fonte de Ca/S; teores típicos','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Calcário calcítico',0,0,0,38,3,0,0,0,0,0,0,0,'Ca e Mg elementares representativos; conferir PRNT e laudo','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Calcário dolomítico',0,0,0,25,12,0,0,0,0,0,0,0,'Ca e Mg elementares representativos; conferir PRNT e laudo','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Ácido bórico',0,0,0,0,0,0,17,0,0,0,0,0,'Fonte de B','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Bórax',0,0,0,0,0,0,11,0,0,0,0,0,'Fonte de B; teor depende do grau de hidratação','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Ulexita',0,0,0,0,0,0,10,0,0,0,0,0,'Fonte mineral de B; teor representativo','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Sulfato de zinco monohidratado',0,0,0,0,0,17,0,0,0,0,0,35,'Fonte de Zn e S','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Sulfato de zinco heptahidratado',0,0,0,0,0,11,0,0,0,0,0,22,'Fonte de Zn e S','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Óxido de zinco',0,0,0,0,0,0,0,0,0,0,0,72,'Teor representativo; baixa solubilidade em água','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Sulfato de manganês',0,0,0,0,0,18,0,0,0,31,0,0,'Fonte de Mn e S; grau comercial variável','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Sulfato de cobre',0,0,0,0,0,12,0,25,0,0,0,0,'Pentahidratado; fonte de Cu e S','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Sulfato ferroso',0,0,0,0,0,11,0,0,20,0,0,0,'Heptahidratado; fonte de Fe e S','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Molibdato de sódio',0,0,0,0,0,0,0,0,0,0,39,0,'Fonte de Mo; teor representativo','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Molibdato de amônio',0,0,0,0,0,0,0,0,0,0,54,0,'Fonte de Mo; teor representativo','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Quelato de ferro EDDHA',0,0,0,0,0,0,0,0,6,0,0,0,'Fertilizante quelatado; teor típico','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Quelato de zinco EDTA',0,0,0,0,0,0,0,0,0,0,0,14,'Fertilizante quelatado; teor típico','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Quelato de manganês EDTA',0,0,0,0,0,0,0,0,0,13,0,0,'Fertilizante quelatado; teor típico','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Quelato de cobre EDTA',0,0,0,0,0,0,0,14,0,0,0,0,'Fertilizante quelatado; teor típico','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 20-00-20',20,0,20,0,0,0,0,0,0,0,0,0,'Formulação de cobertura comum','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 20-05-20',20,5,20,0,0,0,0,0,0,0,0,0,'Formulação de produção; garantias nominais','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 20-05-20 + 2% Mg + 4% S',20,5,20,0,2,4,0,0,0,0,0,0,'Mistura com macronutrientes secundários','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 20-05-20 + 0,3% B + 0,2% Zn',20,5,20,0,0,0,0.3,0,0,0,0,0.2,'Mistura com micronutrientes','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 18-05-18',18,5,18,0,0,0,0,0,0,0,0,0,'Formulação comum para café','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 18-06-18',18,6,18,0,0,0,0,0,0,0,0,0,'Formulação comum para café','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 16-04-16',16,4,16,0,0,0,0,0,0,0,0,0,'Formulação equilibrada','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 15-05-15',15,5,15,0,0,0,0,0,0,0,0,0,'Formulação equilibrada','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 14-07-28',14,7,28,0,0,0,0,0,0,0,0,0,'Formulação com maior K','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 12-06-24',12,6,24,0,0,0,0,0,0,0,0,0,'Formulação com maior K','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 10-10-20',10,10,20,0,0,0,0,0,0,0,0,0,'Formulação para formação/produção conforme diagnóstico','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 19-04-19',19,4,19,0,0,0,0,0,0,0,0,0,'Formulação de plantio, conforme análise','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('NPK 08-28-16',8,28,16,0,0,0,0,0,0,0,0,0,'Formulação de plantio, conforme análise','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('MKP — fosfato monopotássico',0,52,34,0,0,0,0,0,0,0,0,0,'Fonte solúvel de P e K para fertirrigação/foliar','https://www.gov.br/agricultura/pt-br/assuntos/insumos-agropecuarios/insumos-agricolas/fertilizantes/legislacao/in-39-2018-fert-minerais-versao-publicada-dou-10-8-18.pdf'),
('Componha seu NPK',0,0,0,0,0,0,0,0,0,0,0,0,'','')
on conflict (nome) do nothing;

-- CPD_CAFE (75)
insert into cpd_cafe (molecula,classes,alvos,fonte,data_consulta,nota) values
('Abamectina','Acaricida; Inseticida','Ácaro-vermelho; bicho-mineiro','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Acefato','Inseticida; Acaricida','Bicho-mineiro; cochonilhas','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Acetamiprido','Inseticida','Bicho-mineiro; cochonilhas','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Alfa-cipermetrina','Inseticida','Bicho-mineiro','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Azadiractina','Inseticida; Acaricida','Bicho-mineiro; cochonilhas; ácaros','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Azoxistrobina','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Azoxistrobina + benzovindiflupir','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Azoxistrobina + ciproconazol','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Azoxistrobina + difenoconazol','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Bacillus amyloliquefaciens','Fungicida microbiológico; Bactericida microbiológico','Doenças de solo e foliares, conforme cepa e bula','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Bacillus subtilis','Fungicida microbiológico; Bactericida microbiológico','Cercosporiose; doenças de solo, conforme cepa e bula','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Beauveria bassiana','Inseticida microbiológico','Broca-do-café; cochonilhas, conforme cepa','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Bifentrina','Inseticida; Acaricida','Bicho-mineiro; ácaros','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Boscalida','Fungicida','Cercosporiose; phoma','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Buprofezina','Inseticida','Cochonilhas','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Cadusafós','Nematicida; Inseticida','Nematóides; pragas de solo','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Carbendazim','Fungicida','Cercosporiose; mancha-de-phoma','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Ciantraniliprole','Inseticida','Bicho-mineiro; broca-do-café','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Ciflutrina','Inseticida','Bicho-mineiro','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Ciproconazol','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Clorantraniliprole','Inseticida','Bicho-mineiro; broca-do-café','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Clorpirifós','Inseticida; Acaricida','Bicho-mineiro; cochonilhas; ácaros','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Clorotalonil','Fungicida','Cercosporiose; mancha-de-phoma','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Clotianidina','Inseticida','Bicho-mineiro; cigarras','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Cobre (hidróxido)','Fungicida; Bactericida','Ferrugem; cercosporiose; mancha-aureolada','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Cobre (oxicloreto)','Fungicida; Bactericida','Ferrugem; cercosporiose; mancha-aureolada','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Cobre (óxido cuproso)','Fungicida; Bactericida','Ferrugem; cercosporiose; bacterioses','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Cresoxim-metílico','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Deltametrina','Inseticida','Bicho-mineiro','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Diafentiurom','Inseticida; Acaricida','Ácaros; cochonilhas','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Difenoconazol','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Dimetoato','Inseticida; Acaricida','Bicho-mineiro; cochonilhas; ácaros','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Dinotefurano','Inseticida','Bicho-mineiro; cigarras; cochonilhas','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Emamectina benzoato','Inseticida','Bicho-mineiro','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Espinetoram','Inseticida','Bicho-mineiro; broca-do-café','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Espinosade','Inseticida','Bicho-mineiro; broca-do-café','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Espirodiclofeno','Acaricida','Ácaro-vermelho; ácaro-branco','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Espiromesifeno','Acaricida; Inseticida','Ácaros; cochonilhas','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Etoxazol','Acaricida','Ácaro-vermelho','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Fenpiroximato','Acaricida','Ácaro-vermelho; ácaro-branco','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Fipronil','Inseticida','Broca-do-café; cigarras; pragas de solo','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Fluazinam','Fungicida','Doenças foliares, conforme bula','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Fluopiram','Fungicida; Nematicida','Nematóides; doenças fúngicas conforme bula','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Fluxapiroxade','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Fostiazato','Nematicida; Inseticida','Nematóides; pragas de solo','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Glifosato','Herbicida','Plantas daninhas anuais e perenes em aplicação dirigida','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Glufosinato de amônio','Herbicida','Plantas daninhas em pós-emergência e aplicação dirigida','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Hexitiazoxi','Acaricida','Ácaro-vermelho','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Imidacloprido','Inseticida','Bicho-mineiro; cigarras; cochonilhas','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Indoxacarbe','Inseticida','Bicho-mineiro','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Lambda-cialotrina','Inseticida','Bicho-mineiro; broca-do-café','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Mancozebe','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Metarhizium anisopliae','Inseticida microbiológico','Cigarras; broca-do-café, conforme cepa','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Metconazol','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Metomil','Inseticida','Bicho-mineiro','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Oxicloreto de cobre + mancozebe','Fungicida; Bactericida','Ferrugem; cercosporiose; bacterioses','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Oxamila','Nematicida; Inseticida; Acaricida','Nematóides; pragas sugadoras','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Óxido cuproso','Fungicida; Bactericida','Ferrugem; cercosporiose; bacterioses','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Piraclostrobina','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Piraclostrobina + epoxiconazol','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Piraclostrobina + fluxapiroxade','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Piridabem','Acaricida; Inseticida','Ácaros; cochonilhas','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Propargito','Acaricida','Ácaro-vermelho; ácaro-branco','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Propiconazol','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Tebuconazol','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Teflubenzurom','Inseticida','Bicho-mineiro','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Tiametoxam','Inseticida','Bicho-mineiro; cigarras; cochonilhas','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Tiodicarbe','Inseticida','Bicho-mineiro','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Tiofanato-metílico','Fungicida','Cercosporiose; mancha-de-phoma','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Triazofós','Inseticida; Acaricida','Bicho-mineiro; ácaros','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Trichoderma asperellum','Fungicida microbiológico; Agente biológico de controle','Fungos de solo, conforme cepa e bula','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Trichoderma harzianum','Fungicida microbiológico; Agente biológico de controle','Fungos de solo, conforme cepa e bula','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Trifloxistrobina','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Trifloxistrobina + tebuconazol','Fungicida','Ferrugem; cercosporiose','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.'),
('Zeta-cipermetrina','Inseticida','Bicho-mineiro','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00','Confirmar registro vigente, cultura, alvo, dose, modalidade de aplicação e bula antes da recomendação.')
on conflict (molecula) do nothing;

-- HERB_CAFE (20)
insert into herb_cafe (molecula,classe,grupo_mecanismo,seletividade,daninhas,obs,fonte,data_consulta) values
('2,4-D','Herbicida','Auxina sintética — HRAC 4','Pós-emergência; aplicação dirigida','Guanxuma; picão-preto; corda-de-viola; trapoeraba','Evitar deriva sobre o cafeeiro e culturas sensíveis; confirmar formulação registrada.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Carfentrazona-etílica','Herbicida','Inibidor da PPO — HRAC 14','Pós-emergência; contato; aplicação dirigida','Trapoeraba; picão-preto; leiteiro; corda-de-viola','Melhor desempenho em plantas jovens; exige boa cobertura.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Cletodim','Herbicida','Inibidor da ACCase — HRAC 1','Pós-emergência; seletivo para gramíneas','Capim-amargoso; capim-colchão; capim-pé-de-galinha','Atua somente sobre gramíneas; observar adjuvante e estádio conforme bula.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Diquat','Herbicida','Desviador de elétrons do fotossistema I — HRAC 22','Pós-emergência; contato; aplicação dirigida','Plantas daninhas jovens de folhas largas e gramíneas','Ação de dessecação rápida; não confundir com paraquate.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Diuron','Herbicida','Inibidor do fotossistema II — HRAC 5','Pré e pós-emergência inicial; residual','Capim-colchão; capim-pé-de-galinha; picão-preto; caruru','Risco de lixiviação/fitotoxicidade varia com solo, chuva, dose e idade da lavoura.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Fluazifope-P-butílico','Herbicida','Inibidor da ACCase — HRAC 1','Pós-emergência; seletivo para gramíneas','Capim-colchão; capim-marmelada; capim-pé-de-galinha','Sem ação relevante sobre folhas largas; confirmar espectro na bula.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Flumioxazina','Herbicida','Inibidor da PPO — HRAC 14','Pré-emergência e pós inicial; residual/contato','Trapoeraba; caruru; picão-preto; corda-de-viola','Aplicação dirigida; evitar contato com tecidos verdes do cafeeiro.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Glifosato','Herbicida','Inibidor da EPSPS — HRAC 9','Pós-emergência; sistêmico; não seletivo','Capim-amargoso; braquiária; trapoeraba; picão-preto; tiririca','Aplicação dirigida; resistência é frequente em algumas espécies/biótipos.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Glufosinato de amônio','Herbicida','Inibidor da glutamina sintetase — HRAC 10','Pós-emergência; contato; não seletivo','Buva; capim-amargoso jovem; trapoeraba; picão-preto','Exige cobertura e condições favoráveis; aplicação dirigida.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Haloxifope-P-metílico','Herbicida','Inibidor da ACCase — HRAC 1','Pós-emergência; seletivo para gramíneas','Capim-amargoso; capim-colchão; capim-pé-de-galinha','Desempenho depende do estádio e suscetibilidade do biótipo.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Indaziflam','Herbicida','Inibidor da biossíntese de celulose — HRAC 29','Pré-emergência; residual','Gramíneas e folhas largas anuais em germinação','Usar apenas em cafeeiro com idade/implantação autorizada na bula; atenção ao solo.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Metsulfurom-metílico','Herbicida','Inibidor da ALS — HRAC 2','Pós-emergência; sistêmico; aplicação dirigida','Folhas largas, incluindo picão-preto e guanxuma, conforme bula','Alta atividade em baixa dose; risco elevado de deriva e carryover.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Oxyfluorfen','Herbicida','Inibidor da PPO — HRAC 14','Pré e pós-emergência inicial; contato/residual','Trapoeraba; caruru; beldroega; picão-preto','Aplicar de forma dirigida; contato com folhas novas pode causar injúria.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Pendimetalina','Herbicida','Inibidor de microtúbulos — HRAC 3','Pré-emergência; residual','Capim-colchão; capim-pé-de-galinha; caruru','Necessita posicionamento correto no solo e umidade para ativação.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Quizalofope-P-etílico','Herbicida','Inibidor da ACCase — HRAC 1','Pós-emergência; seletivo para gramíneas','Capim-amargoso; capim-colchão; capim-marmelada','Confirmar espécies, estádio e produto registrado para café.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Saflufenacil','Herbicida','Inibidor da PPO — HRAC 14','Pós-emergência; dessecação; aplicação dirigida','Buva; corda-de-viola; picão-preto; leiteiro','Ação rápida; frequentemente associado a herbicidas sistêmicos conforme bula.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Sethoxydim','Herbicida','Inibidor da ACCase — HRAC 1','Pós-emergência; seletivo para gramíneas','Capim-colchão; capim-marmelada; capim-pé-de-galinha','Apenas gramíneas; conferir adjuvante obrigatório.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Sulfentrazona','Herbicida','Inibidor da PPO — HRAC 14','Pré-emergência; residual','Tiririca; trapoeraba; corda-de-viola; folhas largas anuais','Persistência e seletividade dependem de textura, matéria orgânica, pH e dose.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Triclopir-butotílico','Herbicida','Auxina sintética — HRAC 4','Pós-emergência; sistêmico; aplicação dirigida','Plantas lenhosas; folhas largas de difícil controle','Evitar deriva; uso depende da indicação específica do produto/bula.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00'),
('Trifluralina','Herbicida','Inibidor de microtúbulos — HRAC 3','Pré-plantio/pré-emergência, conforme formulação','Gramíneas anuais; caruru','Necessidade de incorporação ou posicionamento varia conforme formulação.','https://agrofit.agricultura.gov.br/agrofit_cons/principal_agrofit_cons','2026-08-09 00:00:00')
on conflict (molecula) do nothing;

-- ALLOWLIST (11 consultores pre-aprovados)
insert into consultores_autorizados (email,nome) values
('alex.martinelli@kubitcafe.com.br','ALEX MARTINELLI'),
('tecnicoagricola4@blendcoffee.ind.br','ANDREY CAPUCHO'),
('celso.junior@grancafe.com.br','CELSO JUNIOR'),
('ezau.narciso@espressorobusta.com.br','EZAÚ NARCISO'),
('fabio.martinsneto@agrobiota.com.br','FABIO MARTINS'),
('julianaferreiraazevedo184@gmail.com','JULIANA FERREIRA'),
('higo0510ferraz@gmail.com','HIGO FERRAZ'),
('jaderson.suin@cooabriel.coop.br','JADERSON SUIN'),
('juliana.piassi-ext@ldc.com','JULIANA PIASSI'),
('rodrigospachecos@gmail.com','RODRIGO PACHECO'),
('tiagoagapito90@hotmail.com','TIAGO AGAPITO')
on conflict (email) do nothing;

-- FAZENDAS (181)
insert into fazendas (produtor,fazenda,cidade,estado,cafeeira,consultor_email) values
('ANGELO GABRIEL GOBBI','SITIO GOBBI','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('EDERILDO JOSE PRUDENCIO','SITIO SAO BENTO','PANCAS','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('ELIOMAR JOSE MORO','SITIO MORO','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('FERNANDO MARCHESINI','SITIO BOA SORTE','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('FLAVIO DEGASPERI LACERDA','SITIO BOA SORTE','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('FLAVIO JOSE PRUDENCIO','SITIO AMERICA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('IONI NEGRINI','SITIO BOA ESPERANÇA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('JADIR BRUNI','FAZENDA BRUNI','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('JOSE DOMINGOS DE SOUZA','SITIO NOSSA SENHORA APARECIDA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('JOSE MENDES DOS PASSOS','SITIO MENDES','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('LUIZ CARLOS DELAFINA','SITIO DALAFINA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('MARLONE SCARABELI NEGRINI','SITIO MO','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('MOISES AMICHI','SITIO MATA BELA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('PEDRO CANAL','SITIO IRMAOS CANAL','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('ROMULO BARBOSA MARTINS','SITIO ORIENTE','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('VALDEMIR ANTONIO DE LAZARI','SITIO DELAZARI','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('WALTER FRANCISCO SILVA','SITIO GOIABEIRA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','alex.martinelli@kubitcafe.com.br'),
('ALAOR ANTONIO PESSOTTI JUNIOR','FAZENDA BOA VISTA','LINHARES','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('ALEX AUGUSTO DA SILVA MARIN','SITIO ALEX MARIN','GOVERNADOR LINDENBERG','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('ANACLETO DADALTO','FAZENDA DUAS BARRAS','RIO BANANAL','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('ANDERSON DA SILVA','SITIO BEIJA FLOR','SOORETAMA','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('ANDERSON JEAN BONISEGNA','SITIO SANTA LUZIA','SOORETAMA','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('BRUNO BARRETO BRUNELLI','FAZENDA SAO JOAO','SOORETAMA','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('JACYELE MAGDA MARIN','FAZENDA DOIS IRMAOS','JAGUARE','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('JOSE ANTONIO VERGNA','SITIO RANCHINHO','LINHARES','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('JOSEMAR SPOLADORE POLESE','SITIO CORREGO DO MEIO','LINHARES','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('JUAREZ FRANCISCO SMARÇARO','SITIO SAO JORGE','LINHARES','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('JUAREZ FRANCISCO SMARÇARO','SITIO VENEZA','LINHARES','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('LEONARDO DAVID CONTADINI','SITIO POLEZE','LINHARES','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('MC AGRICOLA LTDA','FAZENDA SAO CARLOS','LINHARES','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('PEDRO SPEROTO','SITIO SAO JOAO','RIO BANANAL','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('ROBSON DOS REIS SILVA','SITIO LAGOA TERRA ALTA','LINHARES','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('THIAGO PONTINI MARTINS','FAZENDA DM/SANTA RITA','LINHARES','ESPIRITO SANTO','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER LINHARES','tecnicoagricola4@blendcoffee.ind.br'),
('ADEMAR DE BARROS','FAZENDA FORTALEZA','LINHARES','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('ALCENIR CAMILETTI','SITIO CAMILETTI','SOORETAMA','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('ALCIR ANTONIO CESCONETO','SITIO CESCONETO','VILA VALERIO','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('ANGELIM CESCON','FAZENDA SAO CIPRIANO','JAGUARE','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('BENTO MOISES BOZI','FAZENDA SAO CARLOS II','SOORETAMA','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('DEVALTER VAZ PEDRONI','SITIO BOM JARDIM','VILA VALERIO','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('EDIMAR CAMILETTI','SITIO TRES IRMAOS','SOORETAMA','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('EMERSON CERUTTI ALTOE','SITIO DEVENS','JAGUARE','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('GERSON CAMILETTI','SITIO ESPERANÇA','SOORETAMA','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('JOSEMAR MORO','FAZENDA MODELO','SAO MATEUS','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('NIVALDO AGRIZZI','FAZENDA ARARIBOIA','VILA VALERIO','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('PAULO SERGIO GALINA','SITIO GALINA','SOORETAMA','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('PEDRO PAULO ALTOE','FAZENDA JAQUEIRA','JAGUARE','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('RUBENS VIEIRA RIBEIRO','FAZENDA SANTA RITA','ARACRUZ','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('SERGIO DO LIVRAMENTO','SITIO JUERANA','SOORETAMA','ESPIRITO SANTO','GRANCAFE COMERCIO IMP. E EXP. DE CAFE LTDA','celso.junior@grancafe.com.br'),
('ADAO BURGARELLI TAVARA','SITIO ANDORINHA','SOORETAMA','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('ADEMAR LUIZ SIQUEIRA DA SILVA','SITIO SIQUEIRA','SOORETAMA','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('ADRIANO BALDI','SITIO BELA VISTA','SOORETAMA','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('ANSELMO VERGNA','SITIO NOVO HORIZONTE','LINHARES','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('ARY GOMES TAVARA','SITIO CORREGO DO CALÇADO','SOORETAMA','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('BRENO RIBEIRO MARZETTI','SITIO NOGUEIRA V','LINHARES','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('CARICIO LORENCINE','SITIO SANTA ANGELICA','SOORETAMA','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('FERNANDO DOS SANTOS','SITIO RENASCER','LINHARES','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('GELCIMAR VERGNA','SITIO BOA ESPERANÇA','LINHARES','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('JOAO MARCOS IZOTON CALMON','FAZENDA OLINDA','LINHARES','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('JULIANA MAIA DA SILVA','SITIO CALIFORNIA','SOORETAMA','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('LEONARDO DAVID CONTADINI','SITIO BOA VISTA','LINHARES','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('RONIVALDO MACETE','SITIO RODA D''ÁGUA','LINHARES','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('RUDNEY RIBEIRO DA SILVA','SITIO PARAISO','LINHARES','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('VICTOR BRAVIM MACHADO','SITIO VM','SOORETAMA','ESPIRITO SANTO','VALOR COMERCIO DE CAFES LTDA','ezau.narciso@espressorobusta.com.br'),
('POTYGUARA CARDOSO SIQUEIRA','SITIO MOENDY','PRADO','BAHIA','LOUIS DREYFUS COMPANY BRASIL S.A - ES','fabio.martinsneto@agrobiota.com.br'),
('AGROPECUARIA ILHA DE VERA CRUZ','AGROPECUARIA ILHA DE VERA CRUZ','ITABELA','BAHIA','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER ITAMARAJU','fabio.martinsneto@agrobiota.com.br'),
('ALVARO JOSE MORAES DE MATOS BRECHBUEHL','FAZENDA VICOSA','ALCOBAÇA','BAHIA','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER ITAMARAJU','fabio.martinsneto@agrobiota.com.br'),
('CARLOS VANDERLEI ARDICON','FAZENDA AGUA BRANCA','PORTO SEGURO','BAHIA','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER ITAMARAJU','fabio.martinsneto@agrobiota.com.br'),
('EDVALDO COMAN COUTINHO','FAZENDA CACHILO','PRADO','BAHIA','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER ITAMARAJU','fabio.martinsneto@agrobiota.com.br'),
('EMANOEL CARLOS ARDISSON','FAZENDA VIDA NOVA','ITAMARAJU','BAHIA','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER ITAMARAJU','fabio.martinsneto@agrobiota.com.br'),
('GERALDO CARLETI','FAZENDA DOIS RIOS I','PORTO SEGURO','BAHIA','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER ITAMARAJU','fabio.martinsneto@agrobiota.com.br'),
('GUSTAVO MARTINS STURM','FAZENDA BOM RETIRO','TEIXEIRA DE FREITAS','BAHIA','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - BA','fabio.martinsneto@agrobiota.com.br'),
('JONAS DOMINGOS ZANARDO','FAZENDA BOA VISTA','IBIRAPUÃ','BAHIA','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - BA','fabio.martinsneto@agrobiota.com.br'),
('JOSE ROBERTO CALIMAN','FAZENDA SAO PEDRO','ITAMARAJU','BAHIA','BLENDCOFFEE COMERCIO EXPORTACAO E IMPORTACAO LTDA - TRADER ITAMARAJU','fabio.martinsneto@agrobiota.com.br'),
('SARAMANDAIA AGRICOLA LTDA','FAZENDA SARAMANDAIA','ALCOBAÇA','BAHIA','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - BA','fabio.martinsneto@agrobiota.com.br'),
('ANDERSON BOA FERREIRA','FAZENDA SANTA EMILIA','SOORETAMA','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('ADILSON CAPACIO VIANA','SITIO SERRINHA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('ADILSON PEREIRA DE MELO','SITIO MELO','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('ALAERTE LUIS NICCHIO','SITIO NICCHIO','SAO DOMINGOS DO NORTE','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('ALCY BARCELOS SAMORA','SITIO SAMORA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('ALESSANDRO NICCHIO','SITIO BRAÇO DO SUL','SAO DOMINGOS DO NORTE','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('ANTENOR JOSE DE LACERDA','SITIO DAS PEROBAS','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('ANTONIO CARLOS DE LACERDA','SITIO BOA SORTE','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('ELIAS MARIANO DA SILVA','SITIO CORREGO DO OURO','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('JAIR ANTONIO ROCHA','SITIO TRES IRMAOS','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('JOCIMAR JACOBOSKI LIMA','SITIO MACUCO','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('JONAS ANTONIO FORRECHI','SITIO SAO PEDRO','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('JORGE WROBLEWISKI','SITIO SAO JORGE','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('JOSE CARLOS KUBIT','SITIO SAO JOSE','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('JOSE RENATO MENDES DA CUNHA','SITIO SAO PEDRO','BARRA DE SAO FRANCISCO','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('JOSE RICARDO DE OLIVEIRA GUARESQUI','SITIO CONILON','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('JULIANA POLEZ GUARESQUI','SITIO CHAPADA DOS VENTOS','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('OSMAR MENDES DA CUNHA','SITIO DOIS IRMAOS','BARRA DE SAO FRANCISCO','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('PAULO PINHEIRO DE OLIVEIRA LACERDA','SITIO PALMITAL','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('SALOMAO TAVARES DE LACERDA','SITIO MARCELA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('TIAGO MANZOLI','SITIO PARAISO','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('VANESSA FEDESZEN WROBLEWSKI','SITIO CINCO IRMAOS','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('VINICIOS DELOGO LACERDA','SITIO AGUAS CLARAS','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('WALACE JOSE TEIXEIRA','SITIO TEIXEIRA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','higo0510ferraz@gmail.com'),
('ANDERSON ANTONIO NOSSA','SITIO SANTO ANTONIO','RIO BANANAL','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('ELDA GOLDNER MARGON NICOLI','SITIO CORREGO BOLIVIA','GOVERNADOR LINDENBERG','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('FABRICIO ZAMPIROLLI','SITIO AGUA BOA','SOORETAMA','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('GILBERTO TEIXEIRA CERQUEIRA','SITIO SANTA LUZIA','LINHARES','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('JESSICA MILDEMBERG','SITIO LAGOA NOVA','LINHARES','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('JOSE ROBERTO MENEGHELI','SITIO ANCHIETA','GOVERNADOR LINDENBERG','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('MATHEUS AGNEZI','SITIO COQUEIRO','SOORETAMA','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('NILDSON ORIGE GIULIATTE','SITIO SAO SEBASTIAO','RIO BANANAL','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('OZENIR BALDO NICOLI','SITIO NOSSA SENHORA DA SAUDE','GOVERNADOR LINDENBERG','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('PAULO CEZAR NOSSA','SITIO BOM FUTURO','RIO BANANAL','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('PAULO CEZAR NOSSA','SITIO SANTO ANTONIO','LINHARES','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('TARSIZO ZAMPIROLLI','SITIO BOA ESPERANCA','SOORETAMA','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('THIAGO CARMINATI','SITIO CARMINATI','RIO BANANAL','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('ZEFERINO LORENZONI','SITIO SANTA JULIA','LINHARES','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('ZELIA MARIA ARAGÃO POLEZE','SITIO POLEZE','RIO BANANAL','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','julianaferreiraazevedo184@gmail.com'),
('AGILDO MENDES DE VASCONCELOS','SITIO VASCONCELLOS','SAO GABRIEL DA PALHA','ESPIRITO SANTO','COOABRIEL','jaderson.suin@cooabriel.coop.br'),
('ANGELO VIALETTO BAKU','SITIO VIOLETA','NOVA VENECIA','ESPIRITO SANTO','COOABRIEL','jaderson.suin@cooabriel.coop.br'),
('DANILO BRAZZALI','SITIO DOIS IRMÃOS','NOVA VENECIA','ESPIRITO SANTO','COOABRIEL','jaderson.suin@cooabriel.coop.br'),
('ELIVELTON ROSSIN','SITIO BELA VISTA','VILA PAVAO','ESPIRITO SANTO','COOABRIEL','jaderson.suin@cooabriel.coop.br'),
('FERNANDO MARTINS BRIERE','SITIO NOVA ESPERANÇA','NOVA VENECIA','ESPIRITO SANTO','COOABRIEL','jaderson.suin@cooabriel.coop.br'),
('JOAO ARAUJO','SITIO JACUTINGA','NOVA VENECIA','ESPIRITO SANTO','COOABRIEL','jaderson.suin@cooabriel.coop.br'),
('JOEL JOSE CESCONETO','SITIO MARAVILHA','NOVA VENECIA','ESPIRITO SANTO','COOABRIEL','jaderson.suin@cooabriel.coop.br'),
('MARIO JANN','FAZENDA SOCORRO','VILA PAVAO','ESPIRITO SANTO','COOABRIEL','jaderson.suin@cooabriel.coop.br'),
('OLEI PANSIERE','FAZENDA PIP NUCK','NOVA VENECIA','ESPIRITO SANTO','COOABRIEL','jaderson.suin@cooabriel.coop.br'),
('RENATO BASTIANELLO','SITIO MARVIM','ECOPORANGA','ESPIRITO SANTO','COOABRIEL','jaderson.suin@cooabriel.coop.br'),
('AILTO FLEGLER','SITIO JAMILA','VILA PAVAO','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('ANTONIO AUGUSTO SIMADON','FAZENDA SANTA IZABEL','NOVA VENECIA','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('DETINEU WUTKE','SITIO SAO SEBASTIAO','VILA PAVAO','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('DOMINGOS PEREIRA DO NASCIMENTO','SITIO DOURADO','NOVA VENECIA','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('FAZENDAS ECOLOGICAS','FAZENDA CACHOEIRA DO CRAVO','SAO MATEUS','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('GILBERTO DOS REIS ZUCOLOTO','FAZENDA SERRA DE CIMA','NOVA VENECIA','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('HELENA PANSIERE','FAZENDA BOA VISTA','NOVA VENECIA','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('JUAREZ PIONTKOWSKI','SITIO DA RAPADURA','VILA PAVAO','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('MATEUS COAN','SITIO AGUA BOA','SAO MATEUS','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('NEIMAR ELIAS PANSIERE','SITIO SAO MIGUEL','NOVA VENECIA','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('NELZINA ZULSKE THON','SITIO COQUEIRAL','NOVA VENECIA','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('RAFAEL MACHADO FORTES','SITIO 2 IRMAOS','NOVA VENECIA','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('ROGELIO CALEGARI','SITIO VARGEM ALTA','NOVA VENECIA','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('ROQUE FELIX DE BARBE','SITIO LA PAZ II','SOORETAMA','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('SERGIO PIONTKOWSKI','SITIO PIONTIKOWSKI','VILA PAVAO','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('WAGNER MARTINELI FRISSO','SITIO WF','NOVA VENECIA','ESPIRITO SANTO','LOUIS DREYFUS COMPANY BRASIL S.A - ES','juliana.piassi-ext@ldc.com'),
('ADAUTO ORLETTI','FAZENDA VITORIO ORLETTI','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('ADRIANO PEIXOTO DE ANDRADE','SITIO ALVORADA','PINHEIROS','ESPIRITO SANTO','KUBIT CAFE LTDA','rodrigospachecos@gmail.com'),
('ADRIANO PEIXOTO DE ANDRADE','SITIO DUAS FLORES','PINHEIROS','ESPIRITO SANTO','KUBIT CAFE LTDA','rodrigospachecos@gmail.com'),
('BERNARDO COMERIO SCHULTHAIS','SITIO BERNARDO SCHULTHAIS','GOVERNADOR LINDENBERG','ESPIRITO SANTO','KUBIT CAFE LTDA','rodrigospachecos@gmail.com'),
('FERNANDO ARAUJO ALTOE','FAZENDA ALTOE','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('ISMAEL ORLETTI','FAZENDA CACHOEIRINHA','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('ISMAEL ORLETTI','FAZENDA SATURNINO','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('JOAO LUIZ BAYER','SITIO CEU AZUL','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('JOSIANE CORDEIRO ORLETTI','FAZENDA TRES CORAÇOES','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('JOSILENE CORDEIRO ORLETTI','FAZENDA RENASCER','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('JOVINO CARLOS ORLETTI','FAZENDA MATUTINHA','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('LENITON CESAR GOIS DE OLIVEIRA','FAZENDA ESTANCIA LC','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('LIZETE ARAÚJO ALTOÉ','FAZENDA RIO DO SUL','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('MYRIAM REGINA LYRIO BORGO','FAZENDA FORTALEZA','MONTANHA','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('RODRIGO COMERIO SCHULTHAIS','SITIO ALEGRE ESPERANÇA','GOVERNADOR LINDENBERG','ESPIRITO SANTO','KUBIT CAFE LTDA','rodrigospachecos@gmail.com'),
('RODRIGO COMERIO SCHULTHAIS','SITIO SAO SEBASTIAO','GOVERNADOR LINDENBERG','ESPIRITO SANTO','KUBIT CAFE LTDA','rodrigospachecos@gmail.com'),
('ROMEU DAVID','SITIO BOA VISTA','SAO GABRIEL DA PALHA','ESPIRITO SANTO','KUBIT CAFE LTDA','rodrigospachecos@gmail.com'),
('SAULO FAVARO','SITIO DUAS IRMÃS','PINHEIROS','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('TIAGO FAVARATO PIEROTE','FAZENDA FORTALEZA','MONTANHA','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('VALTEVIR ANDRADE','SITIO OURO VERDE','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','rodrigospachecos@gmail.com'),
('WALTER JOSÉ BERGAMIN','SÍTIO BERGAMIN','BOA ESPERANÇA','ESPIRITO SANTO','ROBUSTA COFFEE EXPORTACAO E COMERCIO DE CAFE LTDA - ES','rodrigospachecos@gmail.com'),
('WANILDO GUSTAVO SCHULTHAIS','SITIO RODRIGO','GOVERNADOR LINDENBERG','ESPIRITO SANTO','KUBIT CAFE LTDA','rodrigospachecos@gmail.com'),
('ADEMIR DALFIOR','SITIO CASSANDRO','GOVERNADOR LINDENBERG','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('ALEX STELZER','SITIO DO ALEX','PANCAS','ESPIRITO SANTO','KUBIT CAFE LTDA','tiagoagapito90@hotmail.com'),
('ANILTON GOMES PEREIRA','FAZENDA COMPER','GOVERNADOR LINDENBERG','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('BRAZ HENRIQUE FIOROT','FAZENDA GORETI','JAGUARE','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('CARLINDO BARBOSA FIUZA','SITIO BOM FIM','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','tiagoagapito90@hotmail.com'),
('CARLOS FERNANDO MONTEIRO LINDENBERG FILHO','FAZENDA TRES MARIAS','LINHARES','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('GENYR DALFIOR FERREIRA','SITIO ORIENTE','GOVERNADOR LINDENBERG','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('JESUS ROQUE LUBIANA','FAZENDA AEROPORTO','NOVA VENECIA','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('JOAO CARMINATI','SITIO CHAPADA GRANDE','VILA VALERIO','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('JOAO CARMINATI','SITIO ELDORADO','VILA VALERIO','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('JOSE FRANCISCO ROCHA','SITIO SANTA HELENA','AGUIA BRANCA','ESPIRITO SANTO','KUBIT CAFE LTDA','tiagoagapito90@hotmail.com'),
('JOSIAS MARTINS','SITIO SAO PEDRO','PANCAS','ESPIRITO SANTO','KUBIT CAFE LTDA','tiagoagapito90@hotmail.com'),
('JULIA MARCIA PANCIERI MOTA','FAZENDA GUARANI','GOVERNADOR LINDENBERG','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('MAICON CAMATA','SITIO APARECIDA','MARILANDIA','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('MAURO CEOLIN','FAZENDA PAMPULHA','SOORETAMA','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('ROMULO CAMATA','FAZENDA SAO PEDRO','MARILANDIA','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('SIDINEI CARLINI','SITIO ENTRE PEDRAS','BARRA DE SAO FRANCISCO','ESPIRITO SANTO','KUBIT CAFE LTDA','tiagoagapito90@hotmail.com'),
('VINICIUS CAMATA','FAZENDA GUARUJA','SOORETAMA','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('VINICIUS JOAO ZANOTTI','SITIO CAFUNDO','ITAGUAÇU','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com'),
('WILLIAN WAGNER','SITIO WAGNER','RIO BANANAL','ESPIRITO SANTO','ED&F MAN VOLCAFE BRASIL LTDA','tiagoagapito90@hotmail.com')
on conflict (produtor,fazenda) do nothing;
-- =====================================================================
-- 7. TRIGGERS: provisionamento de usuário e vínculo consultor↔fazenda
-- =====================================================================

-- 7.1 Ao criar um usuário no Supabase Auth, cria o perfil em "consultores".
--     Se o e-mail estiver na allowlist da planilha => role/consultor + status APROVADO.
--     Se o e-mail for o do ADM => role ADMIN aprovado.
--     Caso contrário => status PENDENTE (aguardando o ADM).
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_nome   text;
  v_role   user_role   := 'consultor';
  v_status user_status := 'pendente';
begin
  -- ADM Nestlé
  if lower(new.email) = 'adm@br.nestle.com' then
    v_role := 'admin'; v_status := 'aprovado'; v_nome := 'ADM_NESTLE';
  else
    select nome into v_nome from consultores_autorizados where email = lower(new.email);
    if found then
      v_status := 'aprovado';                    -- consultor conhecido da planilha
    else
      v_nome := coalesce(new.raw_user_meta_data->>'nome', split_part(new.email,'@',1));
    end if;
  end if;

  insert into consultores (id, nome, email, role, status)
  values (new.id, coalesce(v_nome, split_part(new.email,'@',1)), lower(new.email), v_role, v_status)
  on conflict (id) do nothing;

  -- vincula automaticamente as fazendas cujo consultor_email == e-mail do usuário
  insert into consultor_fazenda (consultor_id, fazenda_id)
  select new.id, f.id from fazendas f
  where f.consultor_email = lower(new.email)
  on conflict do nothing;

  return new;
end $$;

drop trigger if exists trg_new_user on auth.users;
create trigger trg_new_user
after insert on auth.users
for each row execute function handle_new_user();

-- 7.2 Fazenda criada em campo: vincula ao consultor criador e marca a flag.
create or replace function handle_fazenda_campo()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.created_by is not null then
    new.criada_em_campo := true;
    insert into consultor_fazenda (consultor_id, fazenda_id)
    values (new.created_by, new.id) on conflict do nothing;
  end if;
  return new;
end $$;

drop trigger if exists trg_fazenda_campo on fazendas;
create trigger trg_fazenda_campo
after insert on fazendas
for each row when (new.created_by is not null)
execute function handle_fazenda_campo();

-- 7.3 Helpers de autorização (usados nas policies)
create or replace function is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from consultores
                 where id = auth.uid() and role='admin' and status='aprovado')
$$;

create or replace function is_aprovado()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from consultores
                 where id = auth.uid() and status='aprovado')
$$;

-- 7.4 Cálculo automático de N/P2O5/K2O (kg/ha) ao inserir nutrição
create or replace function calc_npk_nutricao()
returns trigger language plpgsql security definer set search_path = public as $$
declare fr fert_cafe%rowtype;
begin
  if new.fert_id is not null then
    select * into fr from fert_cafe where id = new.fert_id;
    if found then
      new.n_kg_ha    := round(new.dose_kg_ha * fr.n   /100.0, 4);
      new.p2o5_kg_ha := round(new.dose_kg_ha * fr.p2o5/100.0, 4);
      new.k2o_kg_ha  := round(new.dose_kg_ha * fr.k2o /100.0, 4);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_calc_npk on visita_nutricao;
create trigger trg_calc_npk
before insert or update on visita_nutricao
for each row execute function calc_npk_nutricao();

-- =====================================================================
-- 8. ROW LEVEL SECURITY
-- =====================================================================
alter table consultores               enable row level security;
alter table fazendas                  enable row level security;
alter table consultor_fazenda         enable row level security;
alter table talhoes                   enable row level security;
alter table visitas                   enable row level security;
alter table visita_observacoes        enable row level security;
alter table visita_nutricao           enable row level security;
alter table visita_cpd                enable row level security;
alter table visita_herb               enable row level security;
alter table visita_recomendacoes_check enable row level security;
alter table evidencias_meta           enable row level security;
alter table fert_cafe                 enable row level security;
alter table cpd_cafe                  enable row level security;
alter table herb_cafe                 enable row level security;

-- 8.1 CATÁLOGOS: leitura para qualquer usuário aprovado; escrita só admin
create policy cat_fert_read on fert_cafe for select using (is_aprovado());
create policy cat_cpd_read  on cpd_cafe  for select using (is_aprovado());
create policy cat_herb_read on herb_cafe for select using (is_aprovado());
create policy cat_fert_adm  on fert_cafe for all using (is_admin()) with check (is_admin());
create policy cat_cpd_adm   on cpd_cafe  for all using (is_admin()) with check (is_admin());
create policy cat_herb_adm  on herb_cafe for all using (is_admin()) with check (is_admin());

-- 8.2 CONSULTORES: cada um lê o próprio perfil; admin lê/gerencia todos
create policy cons_self_read on consultores for select
  using (id = auth.uid() or is_admin());
create policy cons_self_upd on consultores for update
  using (id = auth.uid()) with check (id = auth.uid() and role = role); -- não troca o próprio papel
create policy cons_admin_all on consultores for all
  using (is_admin()) with check (is_admin());   -- ADM aprova/bloqueia/remove

-- 8.3 FAZENDAS: consultor vê as suas (vínculo) ou as que criou; admin vê tudo
create policy faz_read on fazendas for select using (
  is_admin()
  or created_by = auth.uid()
  or exists (select 1 from consultor_fazenda cf
             where cf.fazenda_id = fazendas.id and cf.consultor_id = auth.uid())
);
create policy faz_insert on fazendas for insert with check (
  is_aprovado() and created_by = auth.uid()     -- cadastro de fazenda em campo
);
create policy faz_admin on fazendas for all using (is_admin()) with check (is_admin());

-- 8.4 VINCULO N:N
create policy cf_read on consultor_fazenda for select
  using (consultor_id = auth.uid() or is_admin());
create policy cf_insert on consultor_fazenda for insert
  with check (consultor_id = auth.uid() or is_admin());
create policy cf_admin on consultor_fazenda for all using (is_admin()) with check (is_admin());

-- 8.5 TALHÕES: CRUD do consultor dono da fazenda; admin leitura global
create policy talhao_read on talhoes for select using (
  is_admin()
  or exists (select 1 from consultor_fazenda cf
             where cf.fazenda_id = talhoes.fazenda_id and cf.consultor_id = auth.uid())
);
create policy talhao_cud on talhoes for all using (
  exists (select 1 from consultor_fazenda cf
          where cf.fazenda_id = talhoes.fazenda_id and cf.consultor_id = auth.uid())
) with check (
  exists (select 1 from consultor_fazenda cf
          where cf.fazenda_id = talhoes.fazenda_id and cf.consultor_id = auth.uid())
);
create policy talhao_admin on talhoes for select using (is_admin());

-- 8.6 VISITAS: consultor insere/lê as próprias; admin lê tudo.
--     IMUTABILIDADE: NÃO há policy de UPDATE nem DELETE => banco recusa edição/exclusão.
create policy vis_read on visitas for select using (
  is_admin()
  or consultor_id = auth.uid()
  or exists (select 1 from consultor_fazenda cf
             where cf.fazenda_id = visitas.fazenda_id and cf.consultor_id = auth.uid())
);
create policy vis_insert on visitas for insert with check (
  is_aprovado() and consultor_id = auth.uid()
  and exists (select 1 from consultor_fazenda cf
              where cf.fazenda_id = visitas.fazenda_id and cf.consultor_id = auth.uid())
);
-- (sem update/delete propositalmente — histórico imutável)

-- 8.7 BLOCOS FILHOS DA VISITA (mesma regra: acesso derivado da visita mãe)
--     INSERT permitido ao dono; SELECT ao dono/admin; sem UPDATE/DELETE.
do $$
declare t text;
begin
  foreach t in array array['visita_observacoes','visita_nutricao','visita_cpd',
                           'visita_herb','visita_recomendacoes_check','evidencias_meta']
  loop
    execute format($f$
      create policy %1$s_read on %1$s for select using (
        exists (select 1 from visitas v where v.id = %1$s.visita_id
                and (is_admin() or v.consultor_id = auth.uid())));
      create policy %1$s_ins on %1$s for insert with check (
        exists (select 1 from visitas v where v.id = %1$s.visita_id
                and v.consultor_id = auth.uid() and is_aprovado()));
    $f$, t);
  end loop;
end $$;

-- =====================================================================
-- 9. VIEWs AGREGADAS PARA O DASHBOARD EXECUTIVO (admin)
--    RLS das VIEWs: security_invoker => respeitam as policies acima
--    (admin enxerga tudo; consultor não acessa este módulo pela UI).
-- =====================================================================
alter default privileges in schema public grant select on tables to authenticated;

-- 9.1 Visão base de visitas enriquecida
create or replace view vw_visitas_base
with (security_invoker = true) as
select v.id, v.inicio_em, v.tipo_adub,
       c.id as consultor_id, c.nome as consultor,
       f.id as fazenda_id, f.display_nome as fazenda, f.produtor,
       f.cidade, f.estado, f.cafeeira,
       to_char(v.inicio_em,'YYYY-MM') as ano_mes
from visitas v
join consultores c on c.id = v.consultor_id
join fazendas   f on f.id = v.fazenda_id;

-- 11.1 Visitas por mês
create or replace view vw_visitas_mensal
with (security_invoker = true) as
select ano_mes, count(*) as total_visitas
from vw_visitas_base group by ano_mes order by ano_mes;

-- 11.1 Ranking por consultor
create or replace view vw_ranking_consultor
with (security_invoker = true) as
select consultor_id, consultor, count(*) as total_visitas
from vw_visitas_base group by consultor_id, consultor
order by total_visitas desc;

-- 11.1 Visitas por consultor x fazenda
create or replace view vw_visitas_consultor_fazenda
with (security_invoker = true) as
select consultor, fazenda, count(*) as total_visitas,
       max(inicio_em) as ultima_visita
from vw_visitas_base group by consultor, fazenda;

-- 11.2 Fazendas NÃO visitadas + dias desde última visita (alerta parametrizável)
create or replace view vw_fazendas_status
with (security_invoker = true) as
select f.id as fazenda_id, f.display_nome as fazenda, f.produtor,
       f.cidade, f.estado, f.cafeeira,
       coalesce(c.nome, f.consultor_email) as consultor_responsavel,
       max(v.inicio_em) as ultima_visita,
       case when max(v.inicio_em) is null then null
            else (current_date - max(v.inicio_em)::date) end as dias_sem_visita
from fazendas f
left join consultor_fazenda cf on cf.fazenda_id = f.id
left join consultores c on c.id = cf.consultor_id
left join visitas v on v.fazenda_id = f.id
group by f.id, f.display_nome, f.produtor, f.cidade, f.estado, f.cafeeira, c.nome, f.consultor_email;

-- 11.3 Ranking de observações da visita
create or replace view vw_obs_ranking
with (security_invoker = true) as
select o.categoria, count(*) as ocorrencias
from visita_observacoes o group by o.categoria order by ocorrencias desc;

-- 11.3 Fertilizantes/CPD/Herbicidas mais recomendados
create or replace view vw_top_fertilizantes
with (security_invoker = true) as
select coalesce(fert_nome,'(custom)') as item, count(*) as recomendacoes,
       round(sum(dose_kg_ha),2) as dose_total_kg_ha
from visita_nutricao group by 1 order by recomendacoes desc;

create or replace view vw_top_cpd
with (security_invoker = true) as
select coalesce(cpd_nome,'(custom)') as item, count(*) as recomendacoes
from visita_cpd group by 1 order by recomendacoes desc;

create or replace view vw_top_herb
with (security_invoker = true) as
select coalesce(herb_nome,'(custom)') as item, count(*) as recomendacoes
from visita_herb group by 1 order by recomendacoes desc;

-- 11.3 Taxa de adesão do produtor (continuidade item 7)
create or replace view vw_taxa_adesao
with (security_invoker = true) as
select tipo,
       count(*) filter (where seguida) as seguidas,
       count(*) as total,
       round(100.0*count(*) filter (where seguida)/nullif(count(*),0),1) as pct_adesao
from visita_recomendacoes_check group by tipo;

-- 11.4 NPK por fazenda (kg/ha) — separando correcao vs manutencao
create or replace view vw_npk_por_fazenda
with (security_invoker = true) as
select f.id as fazenda_id, f.display_nome as fazenda, f.estado, f.cafeeira,
       v.tipo_adub,
       to_char(v.inicio_em,'YYYY-MM') as ano_mes,
       round(sum(n.n_kg_ha),2)    as n_kg_ha,
       round(sum(n.p2o5_kg_ha),2) as p2o5_kg_ha,
       round(sum(n.k2o_kg_ha),2)  as k2o_kg_ha
from visita_nutricao n
join visitas v on v.id = n.visita_id
join fazendas f on f.id = v.fazenda_id
group by f.id, f.display_nome, f.estado, f.cafeeira, v.tipo_adub, ano_mes;

-- 11.5 Extras: KPIs gerais
create or replace view vw_kpis_gerais
with (security_invoker = true) as
select
  (select count(*) from consultores where status='aprovado' and role='consultor') as consultores_ativos,
  (select count(*) from fazendas) as fazendas_total,
  (select count(*) from visitas)  as visitas_total,
  (select count(distinct fazenda_id) from visitas) as fazendas_visitadas,
  (select count(*) from evidencias_meta) as evidencias_total,
  round((select count(*) from visitas)::numeric
        / nullif((select count(*) from consultores where status='aprovado' and role='consultor'),0),2)
        as media_visitas_por_consultor;

-- =====================================================================
-- FIM. Próximo passo (fora do SQL): criar o usuário admin
--   adm@br.nestle.com no painel Authentication > Users com senha
--   provisória e trocá-la no primeiro acesso. O trigger 7.1 cria o
--   perfil admin automaticamente no primeiro login.
-- =====================================================================
