# directory — artifact scheme

A directory artifact represents a filesystem subtree whose children are themselves artifacts.

URIs: `directory|<backend>/<relative-path>`.

## Composition

Creating a directory with `children` records a `composed_of` edge per child URI. Backends store these alongside the subtree (the `local-filesystem` backend writes a sibling `<path>.edges.json`).

## Backends

Any backend that can store hierarchies can back this scheme: `local-filesystem` (default), `s3-filesystem`, `git-tree`, …
