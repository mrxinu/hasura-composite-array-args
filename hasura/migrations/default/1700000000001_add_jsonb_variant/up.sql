-- Sibling function that takes the same conceptual input (a batch of park
-- rows) but as jsonb instead of parks[]. Clients send a JSON array of
-- objects with named fields — no Postgres-literal escaping, no positional
-- column order, but no Postgres-side type checking either: jsonb is
-- jsonb. Errors only surface when jsonb_to_recordset materializes the
-- rows.
CREATE FUNCTION summarize_parks_json(parks_input jsonb)
RETURNS SETOF parks
LANGUAGE sql STABLE AS $$
  SELECT p.*
  FROM jsonb_to_recordset(parks_input)
    AS p(id int, name text, acreage numeric, founded_in int)
  WHERE p.acreage > 200000;
$$;
