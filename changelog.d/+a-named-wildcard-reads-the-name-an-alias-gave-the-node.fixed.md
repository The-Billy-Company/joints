Named query wildcards now use a node's use-site alias namedness. A named alias
over an anonymous or hidden symbol answers `(_)`, while an anonymous alias over
a named symbol does not. Bare supertype queries test the reduced symbol beneath
an alias. Concrete names continue to match only the name the tree wears.

The regression covers aliases, fields, choices and supertype membership on a
pressed fixture grammar, including exact capture kinds and byte spans.
