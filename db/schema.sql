-- autopart.guru — PostgreSQL schema
-- Target: Neon PostgreSQL 16+, Spanish catalog, Mexico-focused vehicles.
--
-- Design notes (see db/README.md):
-- • Vehicle picker: año → marca → modelo → versión (motor/acabado/carrocería).
-- • SKU fitment uses vehicle_version + inclusive year range (int4range + GiST).
-- • Interchange: reference numbers grouped in interchange_group (OEM + aftermarket).
-- • Photos: URLs/keys only; binary assets live in object storage.

BEGIN;

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Stable immutable wrapper so expression indexes on unaccent() are valid.
CREATE OR REPLACE FUNCTION public.f_unaccent(text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE STRICT
AS $$
  SELECT unaccent('public.unaccent', $1);
$$;

CREATE OR REPLACE FUNCTION public.normalize_part_number(raw text)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $$
  SELECT upper(regexp_replace(public.f_unaccent(trim(coalesce(raw, ''))), '[^A-Z0-9]', '', 'g'));
$$;

-- ---------------------------------------------------------------------------
-- Reference / lookup
-- ---------------------------------------------------------------------------
CREATE TABLE market (
  code         char(2) PRIMARY KEY,
  name         text NOT NULL,
  CONSTRAINT market_code_upper CHECK (code = upper(code))
);

CREATE TABLE make (
  id           bigserial PRIMARY KEY,
  slug         text NOT NULL UNIQUE,
  name         text NOT NULL,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE model (
  id           bigserial PRIMARY KEY,
  make_id      bigint NOT NULL REFERENCES make (id) ON DELETE RESTRICT,
  slug         text NOT NULL,
  name         text NOT NULL,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (make_id, slug)
);

-- Trim / motor / carrocería — shared across model years via vehicle_version_year.
CREATE TABLE vehicle_version (
  id              bigserial PRIMARY KEY,
  model_id        bigint NOT NULL REFERENCES model (id) ON DELETE RESTRICT,
  slug            text NOT NULL,
  display_name    text NOT NULL,
  trim            text,
  body_style      text,
  engine_desc     text,
  engine_liters   numeric(4, 2),
  engine_code     text,
  fuel_type       text,
  drivetrain      text,
  notes           text,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (model_id, slug)
);

CREATE TABLE vehicle_version_year (
  vehicle_version_id bigint NOT NULL REFERENCES vehicle_version (id) ON DELETE CASCADE,
  model_year         smallint NOT NULL,
  PRIMARY KEY (vehicle_version_id, model_year),
  CONSTRAINT vehicle_version_year_valid CHECK (model_year BETWEEN 1980 AND 2035)
);

-- Which versions were marketed in Mexico (catalog scope).
CREATE TABLE vehicle_version_market (
  vehicle_version_id bigint NOT NULL REFERENCES vehicle_version (id) ON DELETE CASCADE,
  market_code        char(2) NOT NULL REFERENCES market (code) ON DELETE RESTRICT,
  PRIMARY KEY (vehicle_version_id, market_code)
);

CREATE INDEX idx_vehicle_version_model ON vehicle_version (model_id);
CREATE INDEX idx_vehicle_version_year_year ON vehicle_version_year (model_year);

-- ---------------------------------------------------------------------------
-- Part taxonomy (Spanish labels, hierarchical)
-- ---------------------------------------------------------------------------
CREATE TABLE part_category (
  id           bigserial PRIMARY KEY,
  parent_id    bigint REFERENCES part_category (id) ON DELETE SET NULL,
  slug         text NOT NULL UNIQUE,
  name_es      text NOT NULL,
  description_es text,
  sort_order   int NOT NULL DEFAULT 0,
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_part_category_parent ON part_category (parent_id);

-- ---------------------------------------------------------------------------
-- Brands (aftermarket manufacturers + OEM nameplates for reference numbers)
-- ---------------------------------------------------------------------------
CREATE TABLE part_brand (
  id           bigserial PRIMARY KEY,
  slug         text NOT NULL UNIQUE,
  name         text NOT NULL,
  brand_kind   text NOT NULL DEFAULT 'aftermarket'
               CHECK (brand_kind IN ('aftermarket', 'oem', 'private_label')),
  is_active    boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Interchange / equivalencias
-- ---------------------------------------------------------------------------
CREATE TABLE interchange_group (
  id           bigserial PRIMARY KEY,
  label        text,
  notes        text,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TYPE reference_number_kind AS ENUM (
  'oem',
  'aftermarket',
  'superseded',
  'competitor',
  'barcode',
  'other'
);

CREATE TABLE reference_number (
  id                    bigserial PRIMARY KEY,
  interchange_group_id  bigint NOT NULL REFERENCES interchange_group (id) ON DELETE CASCADE,
  brand_id              bigint REFERENCES part_brand (id) ON DELETE SET NULL,
  kind                  reference_number_kind NOT NULL DEFAULT 'aftermarket',
  number_raw            text NOT NULL,
  number_normalized     text NOT NULL,
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reference_number_nonempty CHECK (length(trim(number_raw)) > 0),
  UNIQUE (number_normalized, brand_id, kind)
);

CREATE INDEX idx_reference_number_group ON reference_number (interchange_group_id);
CREATE INDEX idx_reference_number_normalized ON reference_number (number_normalized);
CREATE INDEX idx_reference_number_trgm
  ON reference_number USING gin (number_normalized gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- SKU (sellable part)
-- ---------------------------------------------------------------------------
CREATE TABLE sku (
  id                    bigserial PRIMARY KEY,
  part_brand_id         bigint NOT NULL REFERENCES part_brand (id) ON DELETE RESTRICT,
  part_category_id      bigint NOT NULL REFERENCES part_category (id) ON DELETE RESTRICT,
  interchange_group_id  bigint REFERENCES interchange_group (id) ON DELETE SET NULL,
  sku_code              text NOT NULL,
  name_es               text NOT NULL,
  description_es        text,
  specs                 jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active             boolean NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (part_brand_id, sku_code)
);

CREATE INDEX idx_sku_category ON sku (part_category_id);
CREATE INDEX idx_sku_interchange ON sku (interchange_group_id);
CREATE INDEX idx_sku_specs ON sku USING gin (specs);
CREATE INDEX idx_sku_name_trgm ON sku USING gin (public.f_unaccent(name_es) gin_trgm_ops);
CREATE INDEX idx_sku_code_trgm ON sku USING gin (sku_code gin_trgm_ops);

CREATE TABLE sku_image (
  id           bigserial PRIMARY KEY,
  sku_id       bigint NOT NULL REFERENCES sku (id) ON DELETE CASCADE,
  storage_key  text,
  url          text NOT NULL,
  alt_text_es  text,
  is_primary   boolean NOT NULL DEFAULT false,
  sort_order   int NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sku_image_url_nonempty CHECK (length(trim(url)) > 0)
);

CREATE UNIQUE INDEX sku_image_one_primary
  ON sku_image (sku_id)
  WHERE is_primary;

CREATE INDEX idx_sku_image_sku ON sku_image (sku_id, sort_order);

-- ---------------------------------------------------------------------------
-- Fitment (aplicaciones)
-- ---------------------------------------------------------------------------
CREATE TYPE fitment_side AS ENUM ('izquierdo', 'derecho', 'ambos', 'na');
CREATE TYPE fitment_axle AS ENUM ('delantero', 'trasero', 'ambos', 'na');

CREATE TABLE sku_fitment (
  id                   bigserial PRIMARY KEY,
  sku_id               bigint NOT NULL REFERENCES sku (id) ON DELETE CASCADE,
  vehicle_version_id   bigint NOT NULL REFERENCES vehicle_version (id) ON DELETE RESTRICT,
  year_from            smallint NOT NULL,
  year_to              smallint NOT NULL,
  axle                 fitment_axle NOT NULL DEFAULT 'na',
  side                 fitment_side NOT NULL DEFAULT 'na',
  position_label_es    text,
  qualifiers           jsonb NOT NULL DEFAULT '{}'::jsonb,
  notes_es             text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sku_fitment_years CHECK (year_from <= year_to),
  CONSTRAINT sku_fitment_year_bounds CHECK (
    year_from BETWEEN 1980 AND 2035 AND year_to BETWEEN 1980 AND 2035
  ),
  year_range int4range GENERATED ALWAYS AS (int4range(year_from, year_to, '[]')) STORED
);

CREATE INDEX idx_sku_fitment_sku ON sku_fitment (sku_id);
CREATE INDEX idx_sku_fitment_vehicle ON sku_fitment (vehicle_version_id);
CREATE INDEX idx_sku_fitment_year_range ON sku_fitment USING gist (year_range);
CREATE INDEX idx_sku_fitment_vehicle_years
  ON sku_fitment (vehicle_version_id, year_from, year_to);
CREATE INDEX idx_sku_fitment_qualifiers ON sku_fitment USING gin (qualifiers);

-- ---------------------------------------------------------------------------
-- Convenience view: expanded vehicle for search/display
-- ---------------------------------------------------------------------------
CREATE VIEW v_vehicle AS
SELECT
  vy.model_year,
  mk.id   AS make_id,
  mk.slug AS make_slug,
  mk.name AS make_name,
  mo.id   AS model_id,
  mo.slug AS model_slug,
  mo.name AS model_name,
  vv.id   AS vehicle_version_id,
  vv.slug AS version_slug,
  vv.display_name AS version_display_name,
  vv.trim,
  vv.engine_desc,
  vv.body_style
FROM vehicle_version_year vy
JOIN vehicle_version vv ON vv.id = vy.vehicle_version_id
JOIN model mo ON mo.id = vv.model_id
JOIN make mk ON mk.id = mo.make_id;

COMMIT;
