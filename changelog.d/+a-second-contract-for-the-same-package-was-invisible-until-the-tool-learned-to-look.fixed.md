`contract-test.zone` is gone. It was a coarser, older draft of the same
`package joints` - five directories in one undifferentiated zone, committed by
accident in a feature commit about something else - and nothing referenced it.

It never failed anything because it never ran: zoning up to 1.2.0 only
discovered contracts inside a `contract/` drawer, so a `.zone` at the repository
root was silently skipped. The moment the real contract moved to the root, both
were found, both were judged, and the stale one contributed four `use`
violations against zones it had invented. A duplicate contract for one package
is not a second opinion; it is two laws for the same tree, and the tree only has
one shape.
