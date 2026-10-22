//! The supported external delimiter protocols, bound by complete symbol cohorts.
//! Python quote/layout memory lives in `cohort`; these protocols cover Rust raw
//! strings, Ruby's six literal openers, and quoted nonexpanding shell heredocs.

use super::{ScanHit, ScannerError, charge};
use crate::{SymbolId, compiler::Automaton};

const MAX_STACK: usize = 16;
const MAX_MARK: usize = 256;
const MAX_NESTING: usize = 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Kind {
    RustRaw,
    Ruby,
    QuotedHeredoc,
}

#[derive(Debug)]
struct Family {
    kind: Kind,
    opens: Vec<SymbolId>,
    body: SymbolId,
    close: SymbolId,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct Span {
    family: usize,
    mark: Vec<u8>,
    paired: Option<u8>,
    nesting: usize,
    interpolates: bool,
    space_ends: bool,
    had_body: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(super) struct FenceState {
    stack: Vec<Span>,
}

impl FenceState {
    pub(super) fn clone_work(&self) -> usize {
        self.stack.iter().fold(0usize, |work, span| {
            work.saturating_add(1).saturating_add(span.mark.len())
        })
    }
    pub(super) fn is_empty(&self) -> bool {
        self.stack.is_empty()
    }
}

pub(super) struct FenceProgram {
    families: Vec<Family>,
}

impl FenceProgram {
    pub(super) fn bind(graph: &Automaton) -> Result<Option<Self>, ScannerError> {
        let protocols: &[(Kind, &[&str], &str, &str)] = &[
            (
                Kind::RustRaw,
                &["_raw_string_literal_start"],
                "raw_string_literal_content",
                "_raw_string_literal_end",
            ),
            (
                Kind::Ruby,
                &[
                    "_string_start",
                    "_symbol_start",
                    "_subshell_start",
                    "_regex_start",
                    "_string_array_start",
                    "_symbol_array_start",
                ],
                "string_content",
                "_string_end",
            ),
            (
                Kind::QuotedHeredoc,
                &["heredoc_start"],
                "_heredoc_body_beginning",
                "heredoc_end",
            ),
        ];
        let mut families = vec![];
        for &(kind, open_names, body_name, close_name) in protocols {
            let opens: Option<Vec<_>> = open_names
                .iter()
                .map(|name| graph.external_by_name(name))
                .collect();
            if let (Some(opens), Some(body), Some(close)) = (
                opens,
                graph.external_by_name(body_name),
                graph.external_by_name(close_name),
            ) {
                families.push(Family {
                    kind,
                    opens,
                    body,
                    close,
                });
            }
        }
        Ok((!families.is_empty()).then_some(Self { families }))
    }

    pub(super) fn claims(&self, symbol: SymbolId) -> bool {
        self.families
            .iter()
            .any(|f| f.body == symbol || f.close == symbol || f.opens.contains(&symbol))
    }

    pub(super) fn step(
        &self,
        state: &mut FenceState,
        source: &[u8],
        at: usize,
        _fresh: bool,
        wanted: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        if at > source.len() {
            return Err(ScannerError::Program("fence offset exceeds source".into()));
        }
        if let Some(span) = state.stack.last() {
            let family = &self.families[span.family];
            if wanted.contains(&family.body) || wanted.contains(&family.close) {
                let mut next = span.clone();
                match read(family.kind, &mut next, source, at, remaining)? {
                    Read::Close(end) if wanted.contains(&family.close) => {
                        state.stack.pop();
                        return Ok(Some(ScanHit {
                            symbol: family.close,
                            start: at,
                            end,
                        }));
                    }
                    // Rust's grammar requires the content terminal even for
                    // r"". Its single zero-width body changes scanner memory.
                    Read::Close(_) if wanted.contains(&family.body) && !span.had_body => {
                        state.stack.last_mut().unwrap().had_body = true;
                        return Ok(Some(ScanHit {
                            symbol: family.body,
                            start: at,
                            end: at,
                        }));
                    }
                    Read::Body(end) if wanted.contains(&family.body) => {
                        next.had_body = true;
                        *state.stack.last_mut().unwrap() = next;
                        return Ok(Some(ScanHit {
                            symbol: family.body,
                            start: at,
                            end,
                        }));
                    }
                    _ => {}
                }
            }
        }
        for (family_id, family) in self.families.iter().enumerate() {
            if !family.opens.iter().any(|s| wanted.contains(s)) {
                continue;
            }
            charge(remaining)?;
            let opened = match family.kind {
                Kind::RustRaw => open_raw(source, at, remaining)?,
                Kind::Ruby => open_ruby(source, at, &family.opens, wanted),
                Kind::QuotedHeredoc => open_heredoc(source, at, remaining)?,
            };
            let Some((tag, end, mut span)) = opened else {
                continue;
            };
            if !wanted.contains(&family.opens[tag]) {
                continue;
            }
            if state.stack.len() >= MAX_STACK {
                return Err(ScannerError::Limit("nested external literals"));
            }
            span.family = family_id;
            state.stack.push(span);
            return Ok(Some(ScanHit {
                symbol: family.opens[tag],
                start: at,
                end,
            }));
        }
        Ok(None)
    }
}

fn span(mark: Vec<u8>) -> Span {
    Span {
        family: 0,
        mark,
        paired: None,
        nesting: 0,
        interpolates: false,
        space_ends: false,
        had_body: false,
    }
}

type Opened = Option<(usize, usize, Span)>;

fn open_raw(source: &[u8], at: usize, remaining: &mut usize) -> Result<Opened, ScannerError> {
    let mut end = at;
    if matches!(source.get(end), Some(b'b' | b'c')) {
        end += 1;
    }
    if source.get(end) != Some(&b'r') {
        return Ok(None);
    }
    end += 1;
    let hashes_from = end;
    while source.get(end) == Some(&b'#') {
        charge(remaining)?;
        end += 1;
        if end - hashes_from >= MAX_MARK {
            return Err(ScannerError::Limit("raw string delimiter"));
        }
    }
    if source.get(end) != Some(&b'"') {
        return Ok(None);
    }
    let mut mark = vec![b'"'];
    mark.resize(1 + end - hashes_from, b'#');
    Ok(Some((0, end + 1, span(mark))))
}

fn open_heredoc(source: &[u8], at: usize, remaining: &mut usize) -> Result<Opened, ScannerError> {
    let mut before = at;
    while before > 0 && matches!(source[before - 1], b' ' | b'\t') {
        charge(remaining)?;
        before -= 1;
    }
    if before < 2 || &source[before - 2..before] != b"<<" {
        return Ok(None);
    }
    let Some(&quote @ (b'\'' | b'"')) = source.get(at) else {
        return Ok(None);
    };
    let mut end = at + 1;
    while let Some(&byte) = source.get(end) {
        charge(remaining)?;
        if byte == quote {
            break;
        }
        if matches!(byte, b'\\' | b'\n' | b'\r') {
            return Ok(None);
        }
        if end - at > MAX_MARK {
            return Err(ScannerError::Limit("heredoc delimiter"));
        }
        end += 1;
    }
    if end == at + 1 || source.get(end) != Some(&quote) {
        return Ok(None);
    }
    Ok(Some((0, end + 1, span(source[at + 1..end].to_vec()))))
}

fn open_ruby(source: &[u8], at: usize, opens: &[SymbolId], wanted: &[SymbolId]) -> Opened {
    let first = *source.get(at)?;
    let (mut tag, mut end, mut interpolates, mut space_ends) = (0, at + 1, false, false);
    let opener = match first {
        b'"' => {
            interpolates = true;
            b'"'
        }
        b'\'' => b'\'',
        b'`' => {
            tag = 2;
            interpolates = true;
            b'`'
        }
        b'/' => {
            tag = 3;
            interpolates = true;
            b'/'
        }
        b'%' => {
            interpolates = true;
            match source.get(end)? {
                b's' => {
                    tag = 1;
                    interpolates = false;
                    end += 1;
                }
                b'r' => {
                    tag = 3;
                    end += 1;
                }
                b'x' => {
                    tag = 2;
                    end += 1;
                }
                b'q' => {
                    interpolates = false;
                    end += 1;
                }
                b'Q' => {
                    end += 1;
                }
                b'w' | b'W' => {
                    tag = 4;
                    space_ends = true;
                    interpolates = source[end] == b'W';
                    end += 1;
                }
                b'i' | b'I' => {
                    tag = 5;
                    space_ends = true;
                    interpolates = source[end] == b'I';
                    end += 1;
                }
                b'(' | b'[' | b'{' | b'<' | b'|' | b'!' => {}
                _ => return None,
            }
            let byte = *source.get(end)?;
            end += 1;
            byte
        }
        _ => return None,
    };
    if !wanted.contains(&opens[tag]) {
        return None;
    }
    let closer = match opener {
        b'(' => b')',
        b'[' => b']',
        b'{' => b'}',
        b'<' => b'>',
        b'|' | b'!' | b'/' | b'"' | b'\'' | b'~' | b'^' | b'#' | b'*' | b'+' | b'-' | b'='
        | b',' | b'.' | b':' | b';' | b'?' | b'@' | b'_' | b'`' => opener,
        _ => return None,
    };
    let mut span = span(vec![closer]);
    span.paired = (opener != closer).then_some(opener);
    span.interpolates = interpolates;
    span.space_ends = space_ends;
    Some((tag, end, span))
}

enum Read {
    Body(usize),
    Close(usize),
    Abstain,
}

fn closes(kind: Kind, span: &Span, source: &[u8], at: usize) -> bool {
    if !source[at..].starts_with(&span.mark) {
        return false;
    }
    if kind != Kind::QuotedHeredoc {
        return span.nesting == 0;
    }
    if at != 0 && source[at - 1] != b'\n' {
        return false;
    }
    let after = at + span.mark.len();
    after == source.len() || source[after] == b'\n' || source[after..].starts_with(b"\r\n")
}

fn read(
    kind: Kind,
    span: &mut Span,
    source: &[u8],
    at: usize,
    remaining: &mut usize,
) -> Result<Read, ScannerError> {
    let mut end = at;
    while end < source.len() {
        charge(remaining)?;
        if closes(kind, span, source, end) {
            return Ok(if end == at {
                Read::Close(end + span.mark.len())
            } else {
                Read::Body(end)
            });
        }
        let byte = source[end];
        if kind == Kind::Ruby {
            if byte == b'\\'
                || (span.interpolates && source[end..].starts_with(b"#{"))
                || (span.space_ends && byte.is_ascii_whitespace())
            {
                break;
            }
            if span.paired == Some(byte) {
                if span.nesting == MAX_NESTING {
                    return Err(ScannerError::Limit("paired literal nesting"));
                }
                span.nesting += 1;
            } else if span.nesting > 0 && span.mark.first() == Some(&byte) {
                span.nesting -= 1;
            }
        }
        end += 1;
    }
    Ok(if end == at {
        Read::Abstain
    } else {
        Read::Body(end)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_delimiters_preserve_all_hashes_and_backslashes_do_not_escape_a_close() {
        let source = br###"br##"a\"b"##"###;
        let (_, end, mut span) = open_raw(source, 0, &mut 1000).unwrap().unwrap();
        assert_eq!(end, 5);
        assert_eq!(span.mark, b"\"##");
        assert!(matches!(
            read(Kind::RustRaw, &mut span, source, end, &mut 1000).unwrap(),
            Read::Body(9)
        ));
        assert!(matches!(
            read(Kind::RustRaw, &mut span, source, 9, &mut 1000).unwrap(),
            Read::Close(12)
        ));
        let source = b"r\"x\\\"";
        let (_, end, mut span) = open_raw(source, 0, &mut 1000).unwrap().unwrap();
        assert!(matches!(
            read(Kind::RustRaw, &mut span, source, end, &mut 1000).unwrap(),
            Read::Body(4)
        ));
        assert!(matches!(
            read(Kind::RustRaw, &mut span, source, 4, &mut 1000).unwrap(),
            Read::Close(5)
        ));
        let mut source = vec![b'r'];
        source.extend([b'#'; 40]);
        source.extend(b"\"a\"");
        source.extend([b'#'; 33]);
        source.push(b'b');
        let close = source.len();
        source.push(b'"');
        source.extend([b'#'; 40]);
        let (_, end, mut span) = open_raw(&source, 0, &mut 1000).unwrap().unwrap();
        assert_eq!(span.mark.len(), 41);
        assert!(
            matches!(read(Kind::RustRaw, &mut span, &source, end, &mut 1000).unwrap(), Read::Body(n) if n == close)
        );
        assert!(
            matches!(read(Kind::RustRaw, &mut span, &source, close, &mut 1000).unwrap(), Read::Close(n) if n == source.len())
        );
    }

    #[test]
    fn quoted_heredoc_requires_a_whole_delimiter_at_a_line_start() {
        let source = b"<<'END'\nEND_extra\ntext END\nEND\n";
        let (_, end, mut span) = open_heredoc(source, 2, &mut 1000).unwrap().unwrap();
        assert_eq!(end, 7);
        let close = source.windows(5).rposition(|s| s == b"\nEND\n").unwrap() + 1;
        assert!(
            matches!(read(Kind::QuotedHeredoc, &mut span, source, 8, &mut 1000).unwrap(), Read::Body(n) if n == close)
        );
        assert!(
            matches!(read(Kind::QuotedHeredoc, &mut span, source, close, &mut 1000).unwrap(), Read::Close(n) if n == close+3)
        );
        assert!(open_heredoc(b"<<EOF", 2, &mut 1000).unwrap().is_none());
        assert!(open_heredoc(b"<<-'EOF'", 3, &mut 1000).unwrap().is_none());
    }

    #[test]
    fn fence_copy_work_counts_each_owned_mark() {
        let state = FenceState {
            stack: vec![span(vec![b'#'; 40]), span(b"END".to_vec())],
        };
        assert_eq!(state.clone_work(), 45);
    }

    #[test]
    fn ruby_pair_depth_survives_a_content_boundary_and_interpolation_abstains() {
        let mut span = span(vec![b']']);
        span.paired = Some(b'[');
        span.interpolates = true;
        let source = b"a [b#{x}c] d]";
        assert!(matches!(
            read(Kind::Ruby, &mut span, source, 0, &mut 1000).unwrap(),
            Read::Body(4)
        ));
        assert_eq!(span.nesting, 1);
        assert!(matches!(
            read(Kind::Ruby, &mut span, source, 4, &mut 1000).unwrap(),
            Read::Abstain
        ));
        assert!(matches!(
            read(Kind::Ruby, &mut span, source, 8, &mut 1000).unwrap(),
            Read::Body(12)
        ));
        assert_eq!(span.nesting, 0);
        assert!(matches!(
            read(Kind::Ruby, &mut span, source, 12, &mut 1000).unwrap(),
            Read::Close(13)
        ));
    }

    #[test]
    fn a_partial_name_collision_does_not_bind_an_external_protocol() {
        let graph = Automaton::from_tree_sitter(
            br#"{"rules":{"doc":{"type":"STRING","value":"x"}},
            "externals":[{"type":"SYMBOL","name":"_string_start"}]}"#,
        )
        .unwrap();
        assert!(FenceProgram::bind(&graph).unwrap().is_none());
    }
}
