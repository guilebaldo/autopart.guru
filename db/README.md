# Base de datos — autopart.guru

Esquema PostgreSQL para catálogo y buscador de refacciones automotrices (mercado México). Las fotos viven en almacenamiento de objetos (R2, Vercel Blob, etc.); la base solo guarda `url` y/o `storage_key`.

## Archivos

| Archivo | Propósito |
|---------|-----------|
| `schema.sql` | Tablas, índices, extensiones (`pg_trgm`, `unaccent`) |
| `seed_sample.sql` | Datos de **ejemplo** (no producción) |
| `queries.sql` | Consultas de referencia (UI en cascada, catálogo, equivalencias) |
| `import_templates/*.csv` | Encabezados para preparar carga masiva |

## Modelo (resumen)

### Vehículos

Jerarquía para el selector **año → marca → modelo → versión**:

- **`make`** / **`model`**: marca y modelo (p. ej. Chevrolet, Camaro).
- **`vehicle_version`**: configuración concreta (acabado, motor, carrocería) — p. ej. «SS 6.2L V8».
- **`vehicle_version_year`**: años en que se vendió esa versión (evita duplicar filas por cada año).
- **`vehicle_version_market`**: alcance del catálogo (p. ej. `MX`).

La vista **`v_vehicle`** aplana año + marca + modelo + versión para reportes.

### Refacciones

- **`part_category`**: árbol de categorías con nombres en **español** (`parent_id`).
- **`part_brand`**: fabricante aftermarket u OEM (Moog, Gonher, GM, …).
- **`sku`**: pieza vendible (`sku_code` + marca). Atributos flexibles en **`specs`** (`jsonb`).
- **`sku_image`**: varias imágenes por SKU; una primaria (`is_primary`).

### Aplicaciones (fitment)

**`sku_fitment`** enlaza un SKU con una **`vehicle_version`** y un rango de años **`year_from`…`year_to`** (inclusivo). Columnas:

- **`axle`** / **`side`**: delantero/trasero, izquierdo/derecho/ambos.
- **`qualifiers`** (`jsonb`): p. ej. `{"abs": true}`.
- **`year_range`**: rango `int4range` generado + índice GiST para consultas eficientes por año.

Un mismo SKU puede tener varias filas de aplicación (p. ej. buje SB-132 en Corsa y Astra).

### Equivalencias / intercambio

Requisito central del ramo:

- **`interchange_group`**: grupo lógico de piezas equivalentes.
- **`reference_number`**: números OEM o aftermarket normalizados (`number_normalized` vía `normalize_part_number()`).
- Cada **`sku`** puede apuntar a un `interchange_group_id`; buscar por cualquier número del grupo devuelve los SKU relacionados.

Los números se guardan en crudo (`number_raw`) y normalizados (sin espacios/guiones, mayúsculas, sin acentos) para búsqueda exacta y difusa.

## Decisiones de diseño

1. **Versión vs. año**: la versión es estable; los años van en tabla puente. Así el dropdown de versiones no se multiplica por año.
2. **Rangos de año en fitment**: un repuesto puede aplicar 2008–2010 aunque el vehículo exista otros años; el overlap se resuelve con `int4range` y `&&`.
3. **`jsonb` en specs y qualifiers**: catálogo heterogéneo (amortiguadores vs. bandas) sin migrar columnas por tipo.
4. **Búsqueda en español**: `unaccent` + `pg_trgm` en nombres y números; función `f_unaccent` inmutable para índices.
5. **Mercado MX**: filtro explícito en consultas de UI; se pueden añadir mercados en `market`.

## Carga local (desarrollo)

Requiere PostgreSQL 16+ (o Neon con las mismas extensiones).

```bash
createdb autopart_guru
psql -d autopart_guru -f db/schema.sql
psql -d autopart_guru -f db/seed_sample.sql
```

Probar consultas (sustituir parámetros):

```bash
psql -d autopart_guru -f db/queries.sql
```

## Plantillas CSV

En `import_templates/` cada archivo incluye **solo encabezados** (y una fila opcional de muestra en algunos casos). Orden sugerido de importación:

1. `makes.csv`
2. `models.csv`
3. `vehicle_versions.csv`
4. `vehicle_version_years.csv`
5. `vehicle_version_markets.csv`
6. `part_categories.csv`
7. `part_brands.csv`
8. `interchange_groups.csv` (`group_key` = identificador estable en CSV)
9. `reference_numbers.csv`
10. `skus.csv`
11. `sku_images.csv`
12. `sku_fitments.csv`

**Normalización de números**: al importar `reference_numbers`, calcular `number_normalized = normalize_part_number(number_raw)` en SQL o en tu script ETL.

**`specs_json` / `qualifiers_json`**: JSON válido en una celda (comillas escapadas en CSV).

Un script de importación (Python/`COPY`/Neon) aún no está en el repo; estos CSV definen el contrato de datos para el seed real.

## Neon (producción futura)

1. Crear proyecto Neon PostgreSQL.
2. Habilitar extensiones `pg_trgm` y `unaccent` (soportadas en Neon).
3. Ejecutar `schema.sql`, luego seed/import.
4. Desde Next.js: connection string con pooler; solo lectura pública al catálogo si aplica RLS más adelante.
