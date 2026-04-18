# document provider

A thin, backend-agnostic document wrapper. URI syntax is `document:<backend>/<id>` — the provider
looks at `<backend>` and delegates `artifact.sh` calls to that backend's provider (defaulting to
`file-local`).

This indirection lets workflows express intent as "this step produces a design-document artifact"
without hard-coding the storage — a workspace preference can flip a whole repo's documents from
local to Confluence by changing the default backend.
