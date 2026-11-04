-- Example queries for autopart.guru (parameter placeholders: :year, :make_id, etc.)

-- =============================================================================
-- 1) Cascading dropdowns (Mexico catalog)
-- =============================================================================

-- Años disponibles (vehículos vendidos en MX)
SELECT DISTINCT vy.model_year AS year
FROM vehicle_version_year vy
JOIN vehicle_version_market vm ON vm.vehicle_version_id = vy.vehicle_version_id
WHERE vm.market_code = 'MX'
ORDER BY vy.model_year DESC;

-- Marcas para un año
SELECT DISTINCT mk.id, mk.name, mk.slug
FROM make mk
JOIN model mo ON mo.make_id = mk.id
JOIN vehicle_version vv ON vv.model_id = mo.id
JOIN vehicle_version_year vy ON vy.vehicle_version_id = vv.id
JOIN vehicle_version_market vm ON vm.vehicle_version_id = vv.id
WHERE vy.model_year = :year
  AND vm.market_code = 'MX'
  AND mk.is_active
ORDER BY mk.name;

-- Modelos para año + marca
SELECT DISTINCT mo.id, mo.name, mo.slug
FROM model mo
JOIN vehicle_version vv ON vv.model_id = mo.id
JOIN vehicle_version_year vy ON vy.vehicle_version_id = vv.id
JOIN vehicle_version_market vm ON vm.vehicle_version_id = vv.id
WHERE vy.model_year = :year
  AND mo.make_id = :make_id
  AND vm.market_code = 'MX'
  AND mo.is_active
ORDER BY mo.name;

-- Versiones (motor / acabado) para año + modelo
SELECT vv.id, vv.display_name, vv.trim, vv.engine_desc, vv.body_style
FROM vehicle_version vv
JOIN vehicle_version_year vy ON vy.vehicle_version_id = vv.id
JOIN vehicle_version_market vm ON vm.vehicle_version_id = vv.id
WHERE vy.model_year = :year
  AND vv.model_id = :model_id
  AND vm.market_code = 'MX'
  AND vv.is_active
ORDER BY vv.display_name;

-- =============================================================================
-- 2) Categorías de refacción (árbol para UI)
-- =============================================================================
WITH RECURSIVE tree AS (
  SELECT id, parent_id, slug, name_es, sort_order, 0 AS depth, name_es AS path_es
  FROM part_category
  WHERE parent_id IS NULL AND is_active
  UNION ALL
  SELECT c.id, c.parent_id, c.slug, c.name_es, c.sort_order, t.depth + 1,
         t.path_es || ' › ' || c.name_es
  FROM part_category c
  JOIN tree t ON c.parent_id = t.id
  WHERE c.is_active
)
SELECT * FROM tree ORDER BY path_es;

-- Subcategorías bajo Suspensión (ejemplo)
SELECT id, slug, name_es
FROM part_category
WHERE parent_id = (SELECT id FROM part_category WHERE slug = 'suspension')
  AND is_active
ORDER BY sort_order, name_es;

-- =============================================================================
-- 3) Partes para vehículo + categoría
-- =============================================================================
-- :vehicle_version_id, :model_year, :category_id (o slug)

SELECT
  s.id AS sku_id,
  pb.name AS brand_name,
  s.sku_code,
  s.name_es,
  s.specs,
  sf.axle,
  sf.side,
  sf.position_label_es,
  sf.qualifiers,
  sf.notes_es AS fitment_notes,
  img.url AS primary_image_url
FROM sku_fitment sf
JOIN sku s ON s.id = sf.sku_id
JOIN part_brand pb ON pb.id = s.part_brand_id
LEFT JOIN LATERAL (
  SELECT si.url
  FROM sku_image si
  WHERE si.sku_id = s.id
  ORDER BY si.is_primary DESC, si.sort_order
  LIMIT 1
) img ON true
WHERE sf.vehicle_version_id = :vehicle_version_id
  AND int4range(:model_year, :model_year, '[]') && sf.year_range
  AND s.part_category_id = :category_id
  AND s.is_active
ORDER BY pb.name, s.sku_code;

-- Misma búsqueda filtrando por slug de categoría
SELECT s.id, pb.name, s.sku_code, s.name_es, img.url
FROM sku_fitment sf
JOIN sku s ON s.id = sf.sku_id
JOIN part_brand pb ON pb.id = s.part_brand_id
JOIN part_category pc ON pc.id = s.part_category_id
LEFT JOIN LATERAL (
  SELECT si.url FROM sku_image si WHERE si.sku_id = s.id
  ORDER BY si.is_primary DESC, si.sort_order LIMIT 1
) img ON true
WHERE sf.vehicle_version_id = :vehicle_version_id
  AND int4range(:model_year, :model_year, '[]') && sf.year_range
  AND pc.slug = 'suspension-buje'
  AND s.is_active;

-- =============================================================================
-- 4) Búsqueda por número equivalente (OEM o aftermarket)
-- =============================================================================
-- :search_number — se normaliza igual que en importación

WITH needle AS (
  SELECT public.normalize_part_number(:search_number) AS n
)
SELECT
  rn.number_raw,
  rn.kind,
  pb.name AS ref_brand,
  ig.id AS interchange_group_id,
  s.id AS sku_id,
  spb.name AS sku_brand,
  s.sku_code,
  s.name_es
FROM reference_number rn
JOIN needle ON rn.number_normalized = needle.n
JOIN interchange_group ig ON ig.id = rn.interchange_group_id
LEFT JOIN part_brand pb ON pb.id = rn.brand_id
LEFT JOIN sku s ON s.interchange_group_id = ig.id AND s.is_active
LEFT JOIN part_brand spb ON spb.id = s.part_brand_id
ORDER BY s.sku_code NULLS LAST;

-- =============================================================================
-- 5) Búsqueda difusa (nombre + SKU + números de referencia, español)
-- =============================================================================
-- :q — texto libre; umbral ajustable

WITH q AS (
  SELECT public.f_unaccent(lower(trim(:q))) AS term
)
SELECT *
FROM (
  SELECT
    'sku'::text AS hit_type,
    s.id AS entity_id,
    s.sku_code AS label,
    s.name_es AS detail,
    similarity(public.f_unaccent(lower(s.name_es)), (SELECT term FROM q)) AS score
  FROM sku s
  WHERE s.is_active
    AND (
      public.f_unaccent(lower(s.name_es)) % (SELECT term FROM q)
      OR public.f_unaccent(lower(s.sku_code)) % (SELECT term FROM q)
    )
  UNION ALL
  SELECT
    'reference_number',
    rn.id,
    rn.number_raw,
    coalesce(pb.name, 'Sin marca') || ' · ' || rn.kind::text,
    similarity(rn.number_normalized, public.normalize_part_number(:q))
  FROM reference_number rn
  LEFT JOIN part_brand pb ON pb.id = rn.brand_id
  WHERE rn.number_normalized % public.normalize_part_number(:q)
) hits
WHERE hits.score > 0.15
ORDER BY hits.score DESC
LIMIT 25;

-- =============================================================================
-- 6) Vehículos compatibles con un SKU (página de detalle)
-- =============================================================================
SELECT
  sf.year_from,
  sf.year_to,
  mk.name AS make_name,
  mo.name AS model_name,
  vv.display_name AS version_name,
  sf.axle,
  sf.side,
  sf.position_label_es,
  sf.qualifiers
FROM sku_fitment sf
JOIN vehicle_version vv ON vv.id = sf.vehicle_version_id
JOIN model mo ON mo.id = vv.model_id
JOIN make mk ON mk.id = mo.make_id
WHERE sf.sku_id = :sku_id
ORDER BY mk.name, mo.name, sf.year_from;
