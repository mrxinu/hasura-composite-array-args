CREATE TABLE parks (
  id          serial PRIMARY KEY,
  name        text    NOT NULL,
  acreage     numeric NOT NULL,
  founded_in  int     NOT NULL
);

INSERT INTO parks (name, acreage, founded_in) VALUES
  ('Yellowstone',    2219791, 1872),
  ('Yosemite',        759620, 1890),
  ('Crater Lake',     183224, 1902);

-- The interesting bit: argument is a strongly-typed array of the `parks`
-- row type. Inside the function body, (p).name / (p).acreage / etc are
-- real Postgres columns with real types.
CREATE FUNCTION summarize_parks(parks_input parks[])
RETURNS SETOF parks
LANGUAGE sql STABLE AS $$
  SELECT (p).*
  FROM unnest(parks_input) AS p
  WHERE (p).acreage > 200000;
$$;
