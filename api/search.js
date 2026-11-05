const { getPool } = require('./_db');

const SEARCH_SQL = `
WITH inp AS (
  SELECT
    trim(coalesce($1::text, '')) AS q_raw,
    public.f_unaccent(lower(trim(coalesce($1::text, '')))) AS q_term,
    public.normalize_part_number(coalesce($1::text, '')) AS q_norm,
    CASE WHEN $2::text ~ '^[0-9]{4}$' THEN $2::int ELSE NULL END AS yr,
    nullif(trim(coalesce($3::text, '')), '') AS make_slug,
    nullif(trim(coalesce($4::text, '')), '') AS model_slug,
    nullif(trim(coalesce($5::text, '')), '') AS version_slug,
    nullif(trim(coalesce($6::text, '')), '') AS category_slug
),
sku_hits AS (
  SELECT s.id AS sku_id, 0.85::float8 AS score
  FROM inp i
  JOIN sku s ON s.is_active
  WHERE i.q_norm <> ''
    AND public.f_unaccent(lower(s.sku_code)) = i.q_norm

  UNION ALL

  SELECT s.id, 1.0::float8
  FROM inp i
  JOIN reference_number rn ON rn.number_normalized = i.q_norm
  JOIN sku s ON s.interchange_group_id = rn.interchange_group_id AND s.is_active
  WHERE length(i.q_norm) >= 3

  UNION ALL

  SELECT s.id, GREATEST(
    similarity(public.f_unaccent(lower(s.name_es)), i.q_term),
    similarity(public.f_unaccent(lower(s.sku_code)), i.q_term),
    similarity(public.f_unaccent(lower(pc.name_es)), i.q_term)
  )::float8
  FROM inp i
  JOIN sku s ON s.is_active
  JOIN part_category pc ON pc.id = s.part_category_id
  WHERE i.q_term <> ''
    AND (
      public.f_unaccent(lower(s.name_es)) OPERATOR(public.%) i.q_term
      OR public.f_unaccent(lower(s.sku_code)) OPERATOR(public.%) i.q_term
      OR public.f_unaccent(lower(pc.name_es)) OPERATOR(public.%) i.q_term
    )

  UNION ALL

  SELECT s.id, GREATEST(
    similarity(rn.number_normalized, i.q_norm),
    CASE WHEN rn.number_normalized LIKE i.q_norm || '%' THEN 0.9 ELSE 0 END
  )::float8
  FROM inp i
  JOIN reference_number rn ON rn.number_normalized OPERATOR(public.%) i.q_norm
  JOIN sku s ON s.interchange_group_id = rn.interchange_group_id AND s.is_active
  WHERE length(i.q_norm) >= 3

  UNION ALL

  SELECT DISTINCT s.id, GREATEST(
    similarity(public.f_unaccent(lower(mk.name)), i.q_term),
    similarity(public.f_unaccent(lower(mo.name)), i.q_term),
    similarity(public.f_unaccent(lower(vv.display_name)), i.q_term)
  )::float8
  FROM inp i
  JOIN sku s ON s.is_active
  JOIN sku_fitment sf ON sf.sku_id = s.id
  JOIN vehicle_version vv ON vv.id = sf.vehicle_version_id
  JOIN model mo ON mo.id = vv.model_id
  JOIN make mk ON mk.id = mo.make_id
  WHERE i.q_term <> ''
    AND (
      public.f_unaccent(lower(mk.name)) OPERATOR(public.%) i.q_term
      OR public.f_unaccent(lower(mo.name)) OPERATOR(public.%) i.q_term
      OR public.f_unaccent(lower(vv.display_name)) OPERATOR(public.%) i.q_term
    )

  UNION ALL

  SELECT s.id, 0.55::float8
  FROM inp i
  JOIN sku s ON s.is_active
  JOIN part_category pc ON pc.id = s.part_category_id
  WHERE i.q_term = ''
    AND (i.yr IS NOT NULL OR i.make_slug IS NOT NULL OR i.model_slug IS NOT NULL
         OR i.version_slug IS NOT NULL OR i.category_slug IS NOT NULL)
),
ranked AS (
  SELECT sku_id, MAX(score) AS score
  FROM sku_hits
  WHERE score > 0.12
  GROUP BY sku_id
),
filtered AS (
  SELECT r.sku_id, r.score
  FROM ranked r
  JOIN sku s ON s.id = r.sku_id
  JOIN part_category pc ON pc.id = s.part_category_id
  CROSS JOIN inp i
  WHERE (i.category_slug IS NULL OR pc.slug = i.category_slug)
    AND (
      (i.yr IS NULL AND i.make_slug IS NULL AND i.model_slug IS NULL AND i.version_slug IS NULL)
      OR EXISTS (
        SELECT 1
        FROM sku_fitment sf
        JOIN vehicle_version vv ON vv.id = sf.vehicle_version_id
        JOIN model mo ON mo.id = vv.model_id
        JOIN make mk ON mk.id = mo.make_id
        WHERE sf.sku_id = s.id
          AND (i.yr IS NULL OR int4range(i.yr, i.yr, '[]') && sf.year_range)
          AND (i.make_slug IS NULL OR mk.slug = i.make_slug)
          AND (i.model_slug IS NULL OR mo.slug = i.model_slug)
          AND (i.version_slug IS NULL OR vv.slug = i.version_slug)
      )
    )
)
SELECT
  s.sku_code,
  s.name_es,
  pb.name AS brand_name,
  pc.name_es AS category_name_es,
  (
    SELECT si.url
    FROM sku_image si
    WHERE si.sku_id = s.id
    ORDER BY si.is_primary DESC, si.sort_order
    LIMIT 1
  ) AS primary_image_url,
  COALESCE((
    SELECT json_agg(json_build_object(
      'make_name', mk.name,
      'model_name', mo.name,
      'year_from', sf.year_from,
      'year_to', sf.year_to,
      'position_label_es', sf.position_label_es,
      'version_display_name', vv.display_name
    ) ORDER BY mk.name, mo.name, sf.year_from)
    FROM sku_fitment sf
    JOIN vehicle_version vv ON vv.id = sf.vehicle_version_id
    JOIN model mo ON mo.id = vv.model_id
    JOIN make mk ON mk.id = mo.make_id
    WHERE sf.sku_id = s.id
  ), '[]'::json) AS fitments,
  COALESCE((
    SELECT json_agg(json_build_object(
      'number_raw', rn.number_raw,
      'kind', rn.kind,
      'brand_name', rpb.name
    ) ORDER BY rn.number_raw)
    FROM reference_number rn
    LEFT JOIN part_brand rpb ON rpb.id = rn.brand_id
    WHERE s.interchange_group_id IS NOT NULL
      AND rn.interchange_group_id = s.interchange_group_id
  ), '[]'::json) AS reference_numbers,
  f.score
FROM filtered f
JOIN sku s ON s.id = f.sku_id
JOIN part_brand pb ON pb.id = s.part_brand_id
JOIN part_category pc ON pc.id = s.part_category_id
ORDER BY f.score DESC, s.sku_code
LIMIT 20;
`;

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');

  if (req.method === 'OPTIONS') {
    res.setHeader('Allow', 'GET, OPTIONS');
    return res.status(204).end();
  }

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { q = '', year = '', make = '', model = '', version = '', category = '' } =
    req.query || {};

  const hasText = String(q).trim().length > 0;
  const hasFilters = Boolean(year || make || model || version || category);
  if (!hasText && !hasFilters) {
    return res.status(400).json({
      error: 'Provide q and/or vehicle filters (year, make, model, version, category).',
    });
  }

  const pool = getPool();
  if (!pool) {
    return res.status(503).json({ error: 'Database not configured' });
  }

  try {
    const { rows } = await pool.query(SEARCH_SQL, [
      String(q),
      String(year || ''),
      String(make || ''),
      String(model || ''),
      String(version || ''),
      String(category || ''),
    ]);

    const results = rows.map((row) => ({
      sku_code: row.sku_code,
      name_es: row.name_es,
      brand_name: row.brand_name,
      category_name_es: row.category_name_es,
      primary_image_url: row.primary_image_url,
      fitments: row.fitments,
      reference_numbers: row.reference_numbers,
    }));

    return res.status(200).json({ results, count: results.length });
  } catch (err) {
    console.error('search error', err);
    return res.status(500).json({ error: 'Search failed' });
  } finally {
    if (pool) {
      await pool.end();
    }
  }
};
