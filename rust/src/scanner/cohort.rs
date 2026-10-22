//! Generic offside and quote/fence protocols selected by complete terminal cohorts.

use super::{ScanHit, ScannerError, ScannerState, charge};
use crate::{compiler::Automaton, ids::SymbolId};

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct Fence {
    mark: Vec<u8>,
    raw: bool,
    format: bool,
    triple: bool,
}
impl Fence {
    pub(super) fn clone_work(&self) -> usize {
        1usize.saturating_add(self.mark.len())
    }
}
#[derive(Debug)]
pub(super) struct Quotes {
    open: SymbolId,
    body: SymbolId,
    close: SymbolId,
    escape: SymbolId,
}
#[derive(Clone, Copy, Debug)]
enum Comments {
    Hash,
    Slashes,
}

#[derive(Debug)]
pub(super) struct Offside {
    indent: SymbolId,
    dedent: SymbolId,
    newline: SymbolId,
    hush: Vec<SymbolId>,
    comments: Comments,
}
#[derive(Debug, Default)]
pub(super) struct Cohorts {
    quotes: Option<Quotes>,
    offside: Option<Offside>,
}
struct Lead {
    at: usize,
    column: u32,
    fresh: bool,
    comment: Option<u32>,
    broken: bool,
}
impl Cohorts {
    pub fn bind(g: &Automaton) -> Self {
        let external = |name| g.external_by_name(name);
        let quotes = match (
            external("string_start"),
            external("_string_content"),
            external("string_end"),
            external("escape_interpolation"),
        ) {
            (Some(open), Some(body), Some(close), Some(escape)) => Some(Quotes {
                open,
                body,
                close,
                escape,
            }),
            _ => None,
        };
        let offside = [
            ("_dedent", "_newline", Comments::Hash),
            ("_outdent", "_automatic_semicolon", Comments::Slashes),
        ]
        .into_iter()
        .find_map(|(dedent, newline, comments)| {
            match (external("_indent"), external(dedent), external(newline)) {
                (Some(indent), Some(dedent), Some(newline)) => Some(Offside {
                    indent,
                    dedent,
                    newline,
                    comments,
                    hush: [")", "]", "}"]
                        .iter()
                        .filter_map(|n| g.terminal_by_name(n))
                        .collect(),
                }),
                _ => None,
            }
        });
        Self { quotes, offside }
    }
    pub fn claims(&self, s: SymbolId) -> bool {
        self.quotes
            .as_ref()
            .is_some_and(|q| [q.open, q.body, q.close, q.escape].contains(&s))
            || self
                .offside
                .as_ref()
                .is_some_and(|q| [q.indent, q.dedent, q.newline].contains(&s))
    }
    #[allow(clippy::too_many_arguments)]
    pub fn step(
        &self,
        o: &mut ScannerState,
        source: &[u8],
        at: usize,
        fresh: bool,
        after_node: bool,
        wanted: &[SymbolId],
        already: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        if at > source.len() {
            return Ok(None);
        }
        if let (Some(q), Some(fence)) = (&self.quotes, o.quotes.last()) {
            // The parser may be in a format expression: permissions decide which
            // portion of the still-open quote is visible to this reading.
            let hit = if [q.body, q.close, q.escape]
                .iter()
                .any(|s| wanted.contains(s))
            {
                read(fence, source, at, remaining)?
            } else {
                None
            };
            if let Some((part, end)) = hit {
                let symbol = match part {
                    Part::Body => q.body,
                    Part::Escape => q.escape,
                    Part::Close => q.close,
                };
                if wanted.contains(&symbol)
                    && !(self
                        .offside
                        .as_ref()
                        .is_some_and(|s| wanted.contains(&q.body) && wanted.contains(&s.indent)))
                {
                    if matches!(part, Part::Close) {
                        o.quotes.pop();
                    }
                    return Ok(Some(ScanHit {
                        symbol,
                        start: at,
                        end,
                    }));
                }
            }
        }
        if fresh || after_node {
            if let Some(q) = self.offside.as_ref().filter(|q| {
                !o.columns.is_empty()
                    || [q.indent, q.dedent, q.newline]
                        .iter()
                        .any(|s| wanted.contains(s))
            }) {
                let lead = lead(source, at, q.comments, remaining)?;
                let here = o.columns.last().copied().unwrap_or(0);
                if lead.fresh && !lead.broken {
                    if wanted.contains(&q.indent)
                        && lead.column > here
                        && !already.contains(&q.indent)
                    {
                        if o.columns.len() == 96 {
                            return Err(ScannerError::Limit("indentation depth"));
                        }
                        o.columns.push(lead.column);
                        return Ok(Some(ScanHit {
                            symbol: q.indent,
                            start: at,
                            end: at,
                        }));
                    }
                    if lead.column < here
                        && !o.quotes.last().is_some_and(|f| f.format)
                        && lead.comment.is_none_or(|c| c < here)
                        && !already.contains(&q.dedent)
                    {
                        let about_to_quote = self.quotes.as_ref().is_some_and(|s| {
                            wanted.contains(&s.open)
                                && source.get(lead.at).is_some_and(|c| {
                                    matches!(
                                        c,
                                        b'\''
                                            | b'"'
                                            | b'`'
                                            | b'r'
                                            | b'R'
                                            | b'f'
                                            | b'F'
                                            | b'b'
                                            | b'B'
                                            | b't'
                                            | b'T'
                                            | b'u'
                                            | b'U'
                                    )
                                })
                        });
                        if wanted.contains(&q.dedent)
                            || (!wanted.contains(&q.newline)
                                && !q.hush.iter().any(|s| wanted.contains(s))
                                && !about_to_quote)
                        {
                            o.columns.pop();
                            return Ok(Some(ScanHit {
                                symbol: q.dedent,
                                start: at,
                                end: at,
                            }));
                        }
                    }
                    if wanted.contains(&q.newline) && !already.contains(&q.newline) {
                        return Ok(Some(ScanHit {
                            symbol: q.newline,
                            start: at,
                            end: at,
                        }));
                    }
                }
            }
        }
        if let Some(q) = &self.quotes {
            if wanted.contains(&q.open) {
                if let Some((end, fence)) = open(source, at, remaining)? {
                    if o.quotes.len() == 16 {
                        return Err(ScannerError::Limit("quote depth"));
                    }
                    o.quotes.push(fence);
                    return Ok(Some(ScanHit {
                        symbol: q.open,
                        start: at,
                        end,
                    }));
                }
            }
        }
        Ok(None)
    }
}
fn lead(
    source: &[u8],
    at: usize,
    comments: Comments,
    remaining: &mut usize,
) -> Result<Lead, ScannerError> {
    let (mut i, mut column, mut fresh, mut comment) = (at, 0u32, false, None);
    while let Some(&c) = source.get(i) {
        charge(remaining)?;
        match c {
            b'\n' => {
                fresh = true;
                column = 0;
                i += 1;
            }
            b' ' => {
                column = column.saturating_add(1).min(65535);
                i += 1;
            }
            b'\r' | 12 => {
                column = 0;
                i += 1;
            }
            b'\t' => {
                column = (column / 8 + 1).saturating_mul(8).min(65535);
                i += 1;
            }
            b'#' | b'/'
                if (matches!(comments, Comments::Hash) && c == b'#')
                    || (matches!(comments, Comments::Slashes)
                        && (source[i..].starts_with(b"//") || source[i..].starts_with(b"/*"))) =>
            {
                if !fresh {
                    return Ok(Lead {
                        at: i,
                        column,
                        fresh: false,
                        comment: None,
                        broken: false,
                    });
                }
                if comment.is_none() {
                    comment = Some(column);
                }
                if source[i..].starts_with(b"/*") && matches!(comments, Comments::Slashes) {
                    i += 2;
                    column = column.saturating_add(2).min(65535);
                    let mut depth = 1usize;
                    while i < source.len() {
                        charge(remaining)?;
                        if source[i..].starts_with(b"/*") {
                            depth += 1;
                            i += 2;
                            column = column.saturating_add(2).min(65535);
                        } else if source[i..].starts_with(b"*/") {
                            depth -= 1;
                            i += 2;
                            column = column.saturating_add(2).min(65535);
                            if depth == 0 {
                                break;
                            }
                        } else {
                            match source[i] {
                                b'\n' => column = 0,
                                b'\t' => column = (column / 8 + 1).saturating_mul(8).min(65535),
                                _ => column = column.saturating_add(1).min(65535),
                            }
                            i += 1;
                        }
                    }
                } else {
                    while i < source.len() && source[i] != b'\n' {
                        charge(remaining)?;
                        i += 1;
                    }
                    if i < source.len() {
                        i += 1;
                    }
                    column = 0;
                }
            }
            b'\\' => {
                let mut j = i + 1;
                if source.get(j) == Some(&b'\r') {
                    j += 1;
                }
                if j >= source.len() {
                    return Ok(Lead {
                        at: j,
                        column,
                        fresh,
                        comment,
                        broken: false,
                    });
                }
                if source[j] != b'\n' {
                    return Ok(Lead {
                        at: i,
                        column,
                        fresh,
                        comment,
                        broken: true,
                    });
                }
                i = j + 1;
                column = 0;
            }
            _ => {
                return Ok(Lead {
                    at: i,
                    column,
                    fresh,
                    comment,
                    broken: false,
                });
            }
        }
    }
    Ok(Lead {
        at: i,
        column: 0,
        fresh: true,
        comment,
        broken: false,
    })
}
fn open(
    source: &[u8],
    at: usize,
    remaining: &mut usize,
) -> Result<Option<(usize, Fence)>, ScannerError> {
    let (mut i, mut raw, mut format) = (at, false, false);
    while let Some(&c) = source.get(i) {
        charge(remaining)?;
        match c {
            b'f' | b'F' | b't' | b'T' => format = true,
            b'r' | b'R' => raw = true,
            b'b' | b'B' | b'u' | b'U' => {}
            _ => break,
        }
        i += 1;
    }
    let Some(&quote) = source.get(i) else {
        return Ok(None);
    };
    if ![b'"', b'\'', b'`'].contains(&quote) {
        return Ok(None);
    }
    i += 1;
    let triple = quote != b'`' && source.get(i..i + 2) == Some(&[quote, quote]);
    if triple {
        i += 2;
    }
    Ok(Some((
        i,
        Fence {
            mark: vec![quote; if triple { 3 } else { 1 }],
            raw,
            format,
            triple,
        },
    )))
}
#[derive(Clone, Copy)]
enum Part {
    Body,
    Escape,
    Close,
}
fn read(
    f: &Fence,
    source: &[u8],
    at: usize,
    remaining: &mut usize,
) -> Result<Option<(Part, usize)>, ScannerError> {
    if source.get(at..).is_some_and(|s| s.starts_with(&f.mark)) {
        return Ok(Some((Part::Close, at + f.mark.len())));
    }
    if f.format && source.get(at).is_some_and(|c| matches!(c, b'{' | b'}')) {
        if source.get(at + 1) == source.get(at) {
            return Ok(Some((Part::Escape, at + 2)));
        }
        return Ok(None);
    }
    let mut i = at;
    while let Some(&c) = source.get(i) {
        charge(remaining)?;
        if source[i..].starts_with(&f.mark) {
            break;
        }
        if c == b'\\' {
            if f.raw {
                let brace = f.format && source.get(i + 1).is_some_and(|c| matches!(c, b'{' | b'}'));
                i += if i + 1 < source.len() && !brace { 2 } else { 1 };
                continue;
            }
            break;
        }
        if (f.format && matches!(c, b'{' | b'}')) || (c == b'\n' && !f.triple) {
            break;
        }
        i += 1;
    }
    Ok((i > at).then_some((Part::Body, i)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn quote_copy_work_includes_the_owned_delimiter() {
        let quote = Fence {
            mark: b"\"\"\"".to_vec(),
            raw: false,
            format: true,
            triple: true,
        };
        assert_eq!(quote.clone_work(), 4);
    }
    fn grammar() -> Automaton {
        let names = [
            "_indent",
            "_dedent",
            "_newline",
            "string_start",
            "_string_content",
            "string_end",
            "escape_interpolation",
        ];
        Automaton::from_tree_sitter(&serde_json::to_vec(&json!({"name":"offside","externals":names.iter().map(|name|json!({"type":"SYMBOL","name":name})).collect::<Vec<_>>(),"rules":{"doc":{"type":"STRING","value":"x"}}})).unwrap()).unwrap()
    }
    #[test]
    fn offside_preserves_tabs_continuations_comments_and_successive_dedents() {
        let g = grammar();
        let p = Cohorts::bind(&g);
        let i = g.external_by_name("_indent").unwrap();
        let d = g.external_by_name("_dedent").unwrap();
        let n = g.external_by_name("_newline").unwrap();
        let mut state = ScannerState::default();
        assert_eq!(
            p.step(&mut state, b"\n\tx", 0, true, false, &[i, n], &[], &mut 100)
                .unwrap()
                .unwrap()
                .symbol,
            i
        );
        assert_eq!(state.columns, [8]);
        assert_eq!(
            p.step(
                &mut state,
                b"\n\t#comment\nx",
                0,
                true,
                false,
                &[d, n],
                &[],
                &mut 100
            )
            .unwrap()
            .unwrap()
            .symbol,
            n
        );
        assert_eq!(state.columns, [8]);
        assert!(
            p.step(&mut state, b"\\q", 0, true, false, &[n], &[], &mut 100)
                .unwrap()
                .is_none()
        );
        state.columns = vec![4, 8];
        for expected in [vec![4], vec![]] {
            assert_eq!(
                p.step(&mut state, b"", 0, true, false, &[d], &[], &mut 100)
                    .unwrap()
                    .unwrap()
                    .symbol,
                d
            );
            assert_eq!(state.columns, expected);
        }
    }
    #[test]
    fn quote_permission_checks_avoid_scanning_format_expressions_and_restore_exactly() {
        let g = grammar();
        let p = Cohorts::bind(&g);
        let open = g.external_by_name("string_start").unwrap();
        let body = g.external_by_name("_string_content").unwrap();
        let close = g.external_by_name("string_end").unwrap();
        let escape = g.external_by_name("escape_interpolation").unwrap();
        let source = b"f\"a{{{x}b\"";
        let mut state = ScannerState::default();
        assert_eq!(
            p.step(&mut state, source, 0, true, false, &[open], &[], &mut 100)
                .unwrap()
                .unwrap()
                .end,
            2
        );
        assert_eq!(
            p.step(&mut state, source, 2, true, false, &[body], &[], &mut 100)
                .unwrap()
                .unwrap()
                .end,
            3
        );
        assert_eq!(
            p.step(&mut state, source, 3, true, false, &[escape], &[], &mut 100)
                .unwrap()
                .unwrap()
                .end,
            5
        );
        let saved = state.clone();
        let mut remaining = 0;
        assert!(
            p.step(
                &mut state,
                source,
                6,
                false,
                false,
                &[],
                &[],
                &mut remaining
            )
            .unwrap()
            .is_none()
        );
        assert_eq!(remaining, 0);
        assert_eq!(state, saved);
        assert_eq!(
            p.step(&mut state, source, 9, true, false, &[close], &[], &mut 100)
                .unwrap()
                .unwrap()
                .end,
            10
        );
        assert!(state.quotes.is_empty());
        state = saved;
        assert_eq!(state.quotes.len(), 1);
    }
}

#[cfg(test)]
mod comment_styles {
    use super::*;
    use serde_json::json;
    #[test]
    fn complete_offside_cohorts_select_their_comment_convention() {
        let names = ["_indent", "_outdent", "_automatic_semicolon"];
        let graph=Automaton::from_tree_sitter(&serde_json::to_vec(&json!({"name":"cohort","externals":names.iter().map(|name|json!({"type":"SYMBOL","name":name})).collect::<Vec<_>>(),"rules":{"doc":{"type":"STRING","value":"x"}}})).unwrap()).unwrap();
        let cohorts = Cohorts::bind(&graph);
        assert!(
            names
                .iter()
                .all(|name| cohorts.claims(graph.external_by_name(name).unwrap()))
        );
        let source = b"\n\t/*a*/  x";
        let slashes = lead(source, 0, Comments::Slashes, &mut 100).unwrap();
        assert_eq!(slashes.column, 15);
        assert_eq!(slashes.at, source.len() - 1);
        assert_eq!(slashes.comment, Some(8));
        let hash = lead(source, 0, Comments::Hash, &mut 100).unwrap();
        assert_eq!(hash.at, 2);
        assert_eq!(hash.column, 8);
        assert_eq!(hash.comment, None);
        let source = b"\n  /* outer /* inner */\n x */  y";
        let got = lead(source, 0, Comments::Slashes, &mut 100).unwrap();
        assert_eq!(got.at, source.len() - 1);
        assert_eq!(got.column, 7);
    }
}
