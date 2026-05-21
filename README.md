# Hasura custom function with a table-row-array argument

## TL;DR (the answer to Harris's question)

**Yes — with one caveat.** Hasura *will* track a custom function whose argument
is an array of a table's row type (`parks[]`) and the Postgres side is fully
strongly typed. But at the GraphQL boundary, Hasura exposes the argument as a
**custom scalar named after the Postgres array type** (here: `_parks`,
Postgres's internal name for `parks[]`). The client passes the value as a
Postgres array literal of composite literals — a single opaque string —
not as a structured GraphQL input object.

In short:

- **Strongly typed in SQL** — inside the function, `parks_input` is a real
  `parks[]` and `(p).name`, `(p).acreage`, etc. are real columns with real
  types. Pass the wrong number of fields or wrong types and Postgres rejects
  it.
- **Stringly typed at the edge** — at the GraphQL layer it's a single scalar
  with no per-field validation. Clients must hand-build a Postgres array
  literal.

The standing feature request to generate proper GraphQL input objects from
composite types is [hasura/graphql-engine#7078][7078], with related history
in [#3757][3757].

[7078]: https://github.com/hasura/graphql-engine/issues/7078
[3757]: https://github.com/hasura/graphql-engine/issues/3757

## What this repo proves

The setup is real and verified working against `hasura/graphql-engine:v2.40.0`.
End-to-end:

1. `parks` table created and tracked.
2. `summarize_parks(parks_input parks[]) RETURNS SETOF parks` created and
   tracked.
3. Hasura exposes `parks_input` as a custom scalar `_parks`.
4. A GraphQL query passing three park rows as a Postgres array literal of
   composite literals returns the two whose acreage > 200,000.

```graphql
query BigParks($p: _parks!) {
  summarize_parks(args: { parks_input: $p }) {
    id
    name
    acreage
    founded_in
  }
}
```

With variables:

```json
{
  "p": "{\"(1,Yellowstone,2219791,1872)\",\"(2,Yosemite,759620,1890)\",\"(3,\\\"Crater Lake\\\",183224,1902)\"}"
}
```

Response:

```json
{
  "data": {
    "summarize_parks": [
      { "id": 1, "name": "Yellowstone", "acreage": 2219791, "founded_in": 1872 },
      { "id": 2, "name": "Yosemite",     "acreage": 759620,  "founded_in": 1890 }
    ]
  }
}
```

Crater Lake (183,224 acres) is correctly filtered out — the function got a
real `parks[]` and the `WHERE (p).acreage > 200000` clause did its job.

## Run it yourself

```bash
docker compose up -d
# Wait ~15s for migrations to apply. Then either:
#   - open http://localhost:58080/console (admin secret: `toysecret`)
#   - or hit the GraphQL endpoint with the curl below
```

If a previous metadata reload is needed (the first boot can race the source
init), poke it:

```bash
curl -s -X POST http://localhost:58080/v1/metadata \
  -H 'X-Hasura-Admin-Secret: toysecret' \
  -H 'Content-Type: application/json' \
  -d '{"type":"reload_metadata","args":{"reload_sources":true}}'
```

Then run the query:

```bash
curl -s -X POST http://localhost:58080/v1/graphql \
  -H 'X-Hasura-Admin-Secret: toysecret' \
  -H 'Content-Type: application/json' \
  -d @example-request.json | python3 -m json.tool
```

(See `example-request.json` and `example-query.graphql` for the literal forms.)

Ports are remapped to avoid clashes with anything already bound on 5432/8080:

- Hasura console / GraphQL: <http://localhost:58080>
- Postgres: `localhost:55432` (user `postgres`, password `toypass`)

## The interesting files

- `hasura/migrations/default/1700000000000_init/up.sql` — table, seed data,
  and the `parks[]`-taking function.
- `hasura/metadata/databases/default/tables/public_parks.yaml` — tracks
  `parks`.
- `hasura/metadata/databases/default/functions/public_summarize_parks.yaml` —
  tracks `summarize_parks`. Note there is **nothing special** in the metadata
  for the composite-array arg; Hasura figures it out from the Postgres
  signature.

## The composite-array literal, decoded

```
{"(1,Yellowstone,2219791,1872)","(2,Yosemite,759620,1890)","(3,\"Crater Lake\",183224,1902)"}
```

- Outer `{ ... }` — Postgres array literal.
- Each element is a composite (row) literal: `(col1,col2,col3,col4)`.
- Composite literals inside an array literal are double-quoted.
- Text values containing spaces or commas (`Crater Lake`) need *another*
  layer of double-quoting inside the composite literal.
- All those double quotes then need to be backslash-escaped when the whole
  thing is embedded in a JSON string in the HTTP request.
- Column order must match the table's column order. Hasura/Postgres won't
  let you name columns at this layer — that's exactly the missing strong
  typing.

## When to use `jsonb` instead

If you don't strictly need Postgres-side type enforcement, take a `jsonb`
argument and `jsonb_to_recordset(...)` inside the function. Clients then
pass a normal JSON array of objects — no Postgres-literal escaping, no
positional-column trap. You lose Postgres-side type checking, but for most
GraphQL use cases that's the pragmatic call. Reach for the `table[]` form
when:

- The function is also called from elsewhere in SQL (triggers, other
  functions, `psql`) and you want Postgres to enforce the shape there too.
- You want Postgres to do constraint-style validation (NOT NULL, types)
  before your function body sees the rows.
