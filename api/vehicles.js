const { getPool } = require('./_db');

const MARKET = 'MX';

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'public, max-age=300');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');

  if (req.method === 'OPTIONS') {
    res.setHeader('Allow', 'GET, OPTIONS');
    return res.status(204).end();
  }

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const pool = getPool();
  if (!pool) {
    return res.status(503).json({ error: 'Database not configured' });
  }

  const level = String(req.query.level || '').toLowerCase();
  const yearRaw = String(req.query.year || '').trim();
  const make = String(req.query.make || '').trim().toLowerCase() || null;
  const model = String(req.query.model || '').trim().toLowerCase() || null;
  const year = yearRaw && /^[0-9]{4}$/.test(yearRaw) ? Number(yearRaw) : null;

  try {
    let rows;
    switch (level) {
      case 'years':
        rows = await pool.query(
          `SELECT DISTINCT vy.model_year AS year
           FROM vehicle_version_year vy
           JOIN vehicle_version_market vm ON vm.vehicle_version_id = vy.vehicle_version_id
           JOIN vehicle_version vv ON vv.id = vy.vehicle_version_id
           JOIN model mo ON mo.id = vv.model_id
           JOIN make mk ON mk.id = mo.make_id
           WHERE vm.market_code = $1
             AND mk.is_active AND mo.is_active AND vv.is_active
             AND ($2::text IS NULL OR mk.slug = $2)
             AND ($3::text IS NULL OR mo.slug = $3)
           ORDER BY vy.model_year DESC`,
          [MARKET, make, model]
        );
        return res.status(200).json({
          level: 'years',
          items: rows.rows.map((r) => ({ year: r.year })),
        });

      case 'makes':
        rows = await pool.query(
          `SELECT DISTINCT mk.slug, mk.name
           FROM make mk
           JOIN model mo ON mo.make_id = mk.id
           JOIN vehicle_version vv ON vv.model_id = mo.id
           JOIN vehicle_version_year vy ON vy.vehicle_version_id = vv.id
           JOIN vehicle_version_market vm ON vm.vehicle_version_id = vv.id
           WHERE vm.market_code = $1
             AND mk.is_active AND mo.is_active AND vv.is_active
             AND ($2::int IS NULL OR vy.model_year = $2)
           ORDER BY mk.name`,
          [MARKET, year]
        );
        return res.status(200).json({
          level: 'makes',
          items: rows.rows,
        });

      case 'models':
        if (!make) {
          return res.status(400).json({ error: 'make is required for models' });
        }
        rows = await pool.query(
          `SELECT DISTINCT mo.slug, mo.name
           FROM model mo
           JOIN make mk ON mk.id = mo.make_id
           JOIN vehicle_version vv ON vv.model_id = mo.id
           JOIN vehicle_version_year vy ON vy.vehicle_version_id = vv.id
           JOIN vehicle_version_market vm ON vm.vehicle_version_id = vv.id
           WHERE vm.market_code = $1
             AND mk.slug = $2
             AND mo.is_active AND vv.is_active
             AND ($3::int IS NULL OR vy.model_year = $3)
           ORDER BY mo.name`,
          [MARKET, make, year]
        );
        return res.status(200).json({
          level: 'models',
          items: rows.rows,
        });

      case 'versions':
        if (!make || !model) {
          return res.status(400).json({ error: 'make and model are required for versions' });
        }
        rows = await pool.query(
          `SELECT DISTINCT vv.slug, vv.display_name, vv.engine_desc, vv.trim, vv.body_style
           FROM vehicle_version vv
           JOIN model mo ON mo.id = vv.model_id
           JOIN make mk ON mk.id = mo.make_id
           JOIN vehicle_version_year vy ON vy.vehicle_version_id = vv.id
           JOIN vehicle_version_market vm ON vm.vehicle_version_id = vv.id
           WHERE vm.market_code = $1
             AND mk.slug = $2
             AND mo.slug = $3
             AND vv.is_active
             AND ($4::int IS NULL OR vy.model_year = $4)
           ORDER BY vv.display_name`,
          [MARKET, make, model, year]
        );
        return res.status(200).json({
          level: 'versions',
          items: rows.rows,
        });

      case 'categories':
        rows = await pool.query(
          `SELECT pc.slug, pc.name_es, parent.name_es AS group_name_es
           FROM part_category pc
           LEFT JOIN part_category parent ON parent.id = pc.parent_id
           WHERE pc.is_active
             AND pc.parent_id IS NOT NULL
           ORDER BY parent.sort_order, pc.sort_order, pc.name_es`
        );
        return res.status(200).json({
          level: 'categories',
          items: rows.rows.map((r) => ({
            slug: r.slug,
            name_es: r.name_es,
            group_name_es: r.group_name_es,
          })),
        });

      default:
        return res.status(400).json({
          error: 'Invalid level. Use years, makes, models, versions, or categories.',
        });
    }
  } catch (err) {
    console.error('vehicles error', err);
    return res.status(500).json({ error: 'Vehicle lookup failed' });
  } finally {
    await pool.end();
  }
};
