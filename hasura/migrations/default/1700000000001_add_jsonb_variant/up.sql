-- Sibling function that takes the same conceptual input (a batch of mountain
-- rows) but as jsonb instead of mountains[]. Clients send a JSON array of
-- objects with named fields — no Postgres-literal escaping, no positional
-- column order, but no Postgres-side type checking either: jsonb is
-- jsonb. Errors only surface when jsonb_to_recordset materializes the
-- rows.
CREATE FUNCTION summarize_mountains_json(mountains_input jsonb)
RETURNS SETOF mountains
LANGUAGE sql STABLE AS $$
  SELECT m.*
  FROM jsonb_to_recordset(mountains_input)
    AS m(id int, name text, elevation_m int, first_summited int)
  WHERE m.elevation_m > 6000;
$$;
