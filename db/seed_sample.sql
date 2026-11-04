-- SAMPLE DATA ONLY — autopart.guru
-- Not for production import; illustrates relationships for developers.

BEGIN;

INSERT INTO market (code, name) VALUES
  ('MX', 'México');

INSERT INTO make (slug, name) VALUES
  ('chevrolet', 'Chevrolet'),
  ('opel', 'Opel');

INSERT INTO model (make_id, slug, name)
SELECT id, 'camaro', 'Camaro' FROM make WHERE slug = 'chevrolet'
UNION ALL
SELECT id, 'corsa', 'Corsa' FROM make WHERE slug = 'chevrolet'
UNION ALL
SELECT id, 'astra', 'Astra' FROM make WHERE slug = 'opel';

INSERT INTO vehicle_version (model_id, slug, display_name, trim, body_style, engine_desc, engine_liters, engine_code, fuel_type, drivetrain)
SELECT mo.id, 'ss-v8-62', 'SS 6.2L V8', 'SS', 'Coupé', '6.2L V8', 6.20, 'LT1', 'gasolina', 'RWD'
FROM model mo JOIN make mk ON mk.id = mo.make_id
WHERE mk.slug = 'chevrolet' AND mo.slug = 'camaro'
UNION ALL
SELECT mo.id, 'lt-20t', 'LT 2.0T', 'LT', 'Coupé', '2.0L Turbo', 2.00, 'LTG', 'gasolina', 'RWD'
FROM model mo JOIN make mk ON mk.id = mo.make_id
WHERE mk.slug = 'chevrolet' AND mo.slug = 'camaro'
UNION ALL
SELECT mo.id, 'joy-14', 'Joy 1.4', 'Joy', 'Hatchback', '1.4L', 1.40, 'A14XER', 'gasolina', 'FWD'
FROM model mo JOIN make mk ON mk.id = mo.make_id
WHERE mk.slug = 'chevrolet' AND mo.slug = 'corsa'
UNION ALL
SELECT mo.id, 'enjoy-18', 'Enjoy 1.8', 'Enjoy', 'Hatchback', '1.8L', 1.80, 'Z18XER', 'gasolina', 'FWD'
FROM model mo JOIN make mk ON mk.id = mo.make_id
WHERE mk.slug = 'opel' AND mo.slug = 'astra';

INSERT INTO vehicle_version_year (vehicle_version_id, model_year)
SELECT vv.id, y.year
FROM vehicle_version vv
JOIN model mo ON mo.id = vv.model_id
JOIN make mk ON mk.id = mo.make_id
CROSS JOIN (VALUES (2016), (2017), (2018)) AS y(year)
WHERE mk.slug = 'chevrolet' AND mo.slug = 'camaro' AND vv.slug = 'ss-v8-62'
UNION ALL
SELECT vv.id, y.year
FROM vehicle_version vv
JOIN model mo ON mo.id = vv.model_id
JOIN make mk ON mk.id = mo.make_id
CROSS JOIN (VALUES (2016), (2017)) AS y(year)
WHERE mk.slug = 'chevrolet' AND mo.slug = 'camaro' AND vv.slug = 'lt-20t'
UNION ALL
SELECT vv.id, y.year
FROM vehicle_version vv
JOIN model mo ON mo.id = vv.model_id
JOIN make mk ON mk.id = mo.make_id
CROSS JOIN (VALUES (2008), (2009), (2010)) AS y(year)
WHERE mk.slug = 'chevrolet' AND mo.slug = 'corsa' AND vv.slug = 'joy-14'
UNION ALL
SELECT vv.id, y.year
FROM vehicle_version vv
JOIN model mo ON mo.id = vv.model_id
JOIN make mk ON mk.id = mo.make_id
CROSS JOIN (VALUES (2005), (2006), (2007)) AS y(year)
WHERE mk.slug = 'opel' AND mo.slug = 'astra' AND vv.slug = 'enjoy-18';

INSERT INTO vehicle_version_market (vehicle_version_id, market_code)
SELECT vv.id, 'MX'
FROM vehicle_version vv;

INSERT INTO part_category (parent_id, slug, name_es, sort_order)
VALUES
  (NULL, 'suspension', 'Suspensión', 10),
  (NULL, 'frenos', 'Frenos', 20),
  (NULL, 'motor', 'Motor', 30);

INSERT INTO part_category (parent_id, slug, name_es, sort_order)
SELECT id, 'suspension-amortiguador', 'Amortiguador', 11 FROM part_category WHERE slug = 'suspension'
UNION ALL
SELECT id, 'suspension-rotula', 'Rótula', 12 FROM part_category WHERE slug = 'suspension'
UNION ALL
SELECT id, 'suspension-buje', 'Buje', 13 FROM part_category WHERE slug = 'suspension';

INSERT INTO part_brand (slug, name, brand_kind) VALUES
  ('moog', 'Moog', 'aftermarket'),
  ('syd', 'SYD', 'aftermarket'),
  ('gonher', 'Gonher', 'aftermarket'),
  ('gm', 'General Motors', 'oem');

INSERT INTO interchange_group (label, notes) VALUES
  ('SAMPLE — buje horquilla Corsa/Astra', 'Equivalencias de ejemplo'),
  ('SAMPLE — rótula inferior Camaro', 'Equivalencias de ejemplo');

INSERT INTO reference_number (interchange_group_id, brand_id, kind, number_raw, number_normalized, notes)
SELECT ig.id, pb.id, 'aftermarket'::reference_number_kind, 'SB-132', public.normalize_part_number('SB-132'), 'Número SYD'
FROM interchange_group ig, part_brand pb
WHERE ig.label LIKE 'SAMPLE — buje%' AND pb.slug = 'syd'
UNION ALL
SELECT ig.id, pb.id, 'oem'::reference_number_kind, '93240779', public.normalize_part_number('93240779'), 'GM OEM'
FROM interchange_group ig, part_brand pb
WHERE ig.label LIKE 'SAMPLE — buje%' AND pb.slug = 'gm'
UNION ALL
SELECT ig.id, pb.id, 'aftermarket'::reference_number_kind, 'K201434', public.normalize_part_number('K201434'), 'Moog'
FROM interchange_group ig, part_brand pb
WHERE ig.label LIKE 'SAMPLE — buje%' AND pb.slug = 'moog'
UNION ALL
SELECT ig.id, pb.id, 'aftermarket'::reference_number_kind, 'RK620053', public.normalize_part_number('RK620053'), 'Moog rótula'
FROM interchange_group ig, part_brand pb
WHERE ig.label LIKE 'SAMPLE — rótula%' AND pb.slug = 'moog';

INSERT INTO sku (part_brand_id, part_category_id, interchange_group_id, sku_code, name_es, description_es, specs)
SELECT pb.id, pc.id, ig.id, 'SB-132', 'Buje de horquilla delantero', 'SAMPLE — buje poliuretano', '{"material": "poliuretano", "eje": "delantero"}'::jsonb
FROM part_brand pb, part_category pc, interchange_group ig
WHERE pb.slug = 'syd' AND pc.slug = 'suspension-buje' AND ig.label LIKE 'SAMPLE — buje%'
UNION ALL
SELECT pb.id, pc.id, ig.id, 'RK620053', 'Rótula de suspensión inferior', 'SAMPLE — rótula Moog Camaro', '{"eje": "delantero", "lado": "ambos"}'::jsonb
FROM part_brand pb, part_category pc, interchange_group ig
WHERE pb.slug = 'moog' AND pc.slug = 'suspension-rotula' AND ig.label LIKE 'SAMPLE — rótula%'
UNION ALL
SELECT pb.id, pc.id, NULL, 'GON-AM-4412', 'Amortiguador delantero', 'SAMPLE — sin grupo de equivalencia aún', '{"tipo": "gas", "posicion": "delantero"}'::jsonb
FROM part_brand pb, part_category pc
WHERE pb.slug = 'gonher' AND pc.slug = 'suspension-amortiguador';

INSERT INTO sku_image (sku_id, storage_key, url, alt_text_es, is_primary, sort_order)
SELECT s.id, 'sample/syd/sb-132.jpg', 'https://cdn.example.mx/parts/sample/syd/sb-132.jpg', 'Buje SYD SB-132', true, 0
FROM sku s JOIN part_brand pb ON pb.id = s.part_brand_id WHERE pb.slug = 'syd' AND s.sku_code = 'SB-132'
UNION ALL
SELECT s.id, 'sample/moog/rk620053.jpg', 'https://cdn.example.mx/parts/sample/moog/rk620053.jpg', 'Rótula Moog RK620053', true, 0
FROM sku s JOIN part_brand pb ON pb.id = s.part_brand_id WHERE pb.slug = 'moog' AND s.sku_code = 'RK620053';

INSERT INTO sku_fitment (sku_id, vehicle_version_id, year_from, year_to, axle, side, position_label_es, qualifiers, notes_es)
SELECT s.id, vv.id, 2008, 2010, 'delantero'::fitment_axle, 'ambos'::fitment_side, 'Horquilla delantera', '{"abs": false}'::jsonb, 'SAMPLE — Corsa Joy'
FROM sku s
JOIN part_brand pb ON pb.id = s.part_brand_id
JOIN vehicle_version vv ON vv.slug = 'joy-14'
JOIN model mo ON mo.id = vv.model_id AND mo.slug = 'corsa'
WHERE pb.slug = 'syd' AND s.sku_code = 'SB-132'
UNION ALL
SELECT s.id, vv.id, 2005, 2007, 'delantero'::fitment_axle, 'ambos'::fitment_side, 'Horquilla delantera', '{}'::jsonb, 'SAMPLE — Astra Enjoy'
FROM sku s
JOIN part_brand pb ON pb.id = s.part_brand_id
JOIN vehicle_version vv ON vv.slug = 'enjoy-18'
JOIN model mo ON mo.id = vv.model_id AND mo.slug = 'astra'
WHERE pb.slug = 'syd' AND s.sku_code = 'SB-132'
UNION ALL
SELECT s.id, vv.id, 2016, 2018, 'delantero'::fitment_axle, 'ambos'::fitment_side, 'Inferior', '{"abs": true}'::jsonb, 'SAMPLE — Camaro SS'
FROM sku s
JOIN part_brand pb ON pb.id = s.part_brand_id
JOIN vehicle_version vv ON vv.slug = 'ss-v8-62'
WHERE pb.slug = 'moog' AND s.sku_code = 'RK620053';

COMMIT;
