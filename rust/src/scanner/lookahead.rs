//! Stateless external protocols whose lookahead extends beyond their token.
//! Cohorts identify conventions; parse admissions supply each decision's gates.

use super::{ScanHit, ScannerError, charge};
use crate::{SymbolId, compiler::Automaton};

pub(super) struct Lookahead {
    rows: Vec<Row>,
}

enum Row {
    Css {
        symbols: [SymbolId; 2],
        veto: Option<SymbolId>,
    },
    Toml([SymbolId; 5]),
    Haskell([SymbolId; 4]),
    Ecma {
        body: SymbolId,
        gate: SymbolId,
        signature: Option<SymbolId>,
        hush: Vec<SymbolId>,
    },
    Swift([SymbolId; 2]),
    Kotlin(SymbolId),
    Elixir([SymbolId; 3]),
    Julia([SymbolId; 5]),
}
impl Row {
    fn symbols(&self) -> &[SymbolId] {
        match self {
            Self::Css { symbols, .. } | Self::Swift(symbols) => symbols,
            Self::Toml(symbols) | Self::Julia(symbols) => symbols,
            Self::Haskell(symbols) => symbols,
            Self::Elixir(symbols) => symbols,
            Self::Ecma { body, .. } | Self::Kotlin(body) => std::slice::from_ref(body),
        }
    }
}
impl Lookahead {
    pub(super) fn bind(graph: &Automaton) -> Result<Self, ScannerError> {
        fn cohort<const N: usize>(g: &Automaton, names: [&str; N]) -> Option<[SymbolId; N]> {
            names
                .map(|name| g.external_by_name(name))
                .into_iter()
                .collect::<Option<Vec<_>>>()?
                .try_into()
                .ok()
        }
        let mut rows = vec![];
        if let Some(symbols) = cohort(
            graph,
            ["_descendant_operator", "_pseudo_class_selector_colon"],
        ) {
            rows.push(Row::Css {
                symbols,
                veto: graph.terminal_by_name("__error_recovery"),
            });
        }
        if let Some(symbols) = cohort(
            graph,
            [
                "_line_ending_or_eof",
                "_multiline_basic_string_content",
                "_multiline_basic_string_end",
                "_multiline_literal_string_content",
                "_multiline_literal_string_end",
            ],
        ) {
            rows.push(Row::Toml(symbols));
        }
        if graph.external_by_name("_cmd_layout_start_do").is_some() {
            if let Some(symbols) = cohort(graph, ["comment", "haddock", "cpp", "pragma"]) {
                rows.push(Row::Haskell(symbols));
            }
        }
        if graph.external_by_name("_template_chars").is_some() {
            if let (Some(body), Some(gate)) = (
                graph.external_by_name("_automatic_semicolon"),
                graph.terminal_by_name("||"),
            ) {
                rows.push(Row::Ecma {
                    body,
                    gate,
                    signature: graph.terminal_by_name("_function_signature_automatic_semicolon"),
                    hush: ["_template_chars", "jsx_text"]
                        .into_iter()
                        .filter_map(|n| graph.terminal_by_name(n))
                        .collect(),
                });
            }
        }
        if graph.external_by_name("_fake_try_bang").is_some() {
            if let Some(symbols) = cohort(graph, ["_implicit_semi", "_explicit_semi"]) {
                rows.push(Row::Swift(symbols));
            }
        }
        if graph.external_by_name("_by_delegation_hint").is_some() {
            if let Some(body) = graph.external_by_name("_automatic_semicolon") {
                rows.push(Row::Kotlin(body));
            }
        }
        if graph.external_by_name("_not_in").is_some() {
            if let Some(symbols) = cohort(
                graph,
                [
                    "_newline_before_comment",
                    "_newline_before_do",
                    "_newline_before_binary_operator",
                ],
            ) {
                rows.push(Row::Elixir(symbols));
            }
        }
        if let Some(symbols) = cohort(
            graph,
            [
                "_immediate_paren",
                "_immediate_bracket",
                "_immediate_brace",
                "_immediate_string_start",
                "_immediate_command_start",
            ],
        ) {
            rows.push(Row::Julia(symbols));
        }
        Ok(Self { rows })
    }
    pub(super) fn claims(&self, symbol: SymbolId) -> bool {
        self.rows.iter().any(|r| r.symbols().contains(&symbol))
    }
    pub(super) fn remove_claimed(&mut self, claimed: &[SymbolId]) {
        self.rows
            .retain(|r| !r.symbols().iter().any(|s| claimed.contains(s)));
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn step(
        &self,
        source: &[u8],
        at: usize,
        fresh: bool,
        blocked: bool,
        wanted: &[SymbolId],
        already: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        if at > source.len() {
            return Err(ScannerError::Program(
                "lookahead offset exceeds source".into(),
            ));
        }
        let asks = |s: &SymbolId| wanted.contains(s) && !already.contains(s);
        for row in &self.rows {
            charge(remaining)?;
            let cut = match row {
                Row::Css { symbols, veto } if !veto.is_some_and(|s| wanted.contains(&s)) => {
                    css(source, at, asks(&symbols[0]), asks(&symbols[1]), remaining)?
                        .map(|(slot, start, end)| (symbols[slot], start, end))
                }
                Row::Toml(symbols) => toml(source, at, symbols.map(|s| asks(&s)), remaining)?
                    .map(|(slot, start, end)| (symbols[slot], start, end)),
                Row::Haskell(symbols) => haskell(source, at, symbols.map(|s| asks(&s)), remaining)?
                    .map(|(slot, end)| (symbols[slot], at, end)),
                Row::Ecma {
                    body,
                    gate,
                    signature,
                    hush,
                } if fresh && asks(body) && !hush.iter().any(|s| wanted.contains(s)) => ecma(
                    source,
                    at,
                    wanted.contains(gate),
                    signature.is_some_and(|s| wanted.contains(&s)),
                    remaining,
                )?
                .then_some((*body, at, at)),
                Row::Swift(symbols) if fresh && symbols.iter().all(asks) => {
                    swift(source, at, remaining)?
                        .map(|(spelled, start, end)| (symbols[usize::from(spelled)], start, end))
                }
                Row::Kotlin(body) if fresh && asks(body) => {
                    kotlin(source, at, remaining)?.map(|(start, end)| (*body, start, end))
                }
                Row::Elixir(symbols) if fresh => {
                    elixir(source, at, symbols.map(|s| asks(&s)), remaining)?
                        .map(|(slot, start, end)| (symbols[slot], start, end))
                }
                Row::Julia(symbols) if fresh && !blocked && at > 0 && at < source.len() => {
                    b"([{\"`"
                        .iter()
                        .position(|b| *b == source[at])
                        .filter(|i| asks(&symbols[*i]))
                        .map(|i| (symbols[i], at, at))
                }
                _ => None,
            };
            if let Some((symbol, start, end)) = cut {
                return Ok(Some(ScanHit { symbol, start, end }));
            }
        }
        Ok(None)
    }
}

fn byte(s: &[u8], i: usize) -> u8 {
    s.get(i).copied().unwrap_or(0)
}
fn space(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\r' | b'\n' | 0x0b | 0x0c)
}
fn blank(b: u8) -> bool {
    matches!(b, b' ' | b'\t')
}
fn line(b: u8) -> bool {
    matches!(b, b'\r' | b'\n')
}
fn prefix(s: &[u8], at: usize, mark: &[u8]) -> bool {
    s.get(at..).is_some_and(|s| s.starts_with(mark))
}

// A bare slash is division, so it declines the entire separator decision.
fn pass(s: &[u8], mut i: usize, work: &mut usize) -> Result<Option<usize>, ScannerError> {
    loop {
        while i < s.len() && space(s[i]) {
            charge(work)?;
            i += 1;
        }
        if i == s.len() || s[i] != b'/' {
            return Ok(Some(i));
        }
        charge(work)?;
        match byte(s, i + 1) {
            b'/' => {
                i += 2;
                while i < s.len() && s[i] != b'\n' {
                    charge(work)?;
                    i += 1;
                }
            }
            b'*' => {
                i += 2;
                while i < s.len() {
                    charge(work)?;
                    if prefix(s, i, b"*/") {
                        i += 2;
                        break;
                    }
                    i += 1;
                }
            }
            _ => return Ok(None),
        }
    }
}
fn ecma(
    s: &[u8],
    at: usize,
    binary: bool,
    signature: bool,
    work: &mut usize,
) -> Result<bool, ScannerError> {
    let mut i = at;
    loop {
        charge(work)?;
        match byte(s, i) {
            _ if i == s.len() => return Ok(true),
            b'}' => {
                i += 1;
                while i < s.len() && space(s[i]) {
                    charge(work)?;
                    i += 1;
                }
                return Ok(byte(s, i) != b':' || binary);
            }
            b'\n' => break,
            b if !space(b) => return Ok(false),
            _ => i += 1,
        }
    }
    let Some(i) = pass(s, i + 1, work)? else {
        return Ok(false);
    };
    Ok(match byte(s, i) {
        b'`' | b',' | b'.' | b';' | b'*' | b'%' | b'>' | b'<' | b'=' | b'?' | b'^' | b'|'
        | b'&' | b'/' | b':' => false,
        b'{' if signature => false,
        b'(' | b'[' if binary => false,
        b'+' => byte(s, i + 1) == b'+',
        b'-' => byte(s, i + 1) == b'-',
        b'!' => byte(s, i + 1) != b'=',
        b'i' => ![(b"in".as_slice()), b"instanceof"]
            .iter()
            .any(|w| prefix(s, i, w) && !byte(s, i + w.len()).is_ascii_alphabetic()),
        _ => true,
    })
}
fn swift(
    s: &[u8],
    at: usize,
    work: &mut usize,
) -> Result<Option<(bool, usize, usize)>, ScannerError> {
    let mut i = at;
    let mut crossed = false;
    while i < s.len() {
        charge(work)?;
        if s[i] == b';' {
            return Ok(Some((true, i, i + 1)));
        }
        if !space(s[i]) {
            break;
        }
        crossed |= line(s[i]);
        i += 1;
    }
    if !crossed {
        return Ok(None);
    }
    if byte(s, i) == b'/' {
        let Some(j) = pass(s, i, work)? else {
            return Ok(None);
        };
        if b"/=-+!*%<>&|^?~.".contains(&byte(s, j)) {
            return Ok(None);
        }
    } else if matches!(byte(s, i), b'?' | b':' | b'{') {
        return Ok(None);
    }
    Ok(Some((false, at, at)))
}
fn kotlin(s: &[u8], at: usize, work: &mut usize) -> Result<Option<(usize, usize)>, ScannerError> {
    let mut i = at;
    let mut same = true;
    while i < s.len() {
        charge(work)?;
        if s[i] == b';' {
            return Ok(Some((i, i + 1)));
        }
        if !space(s[i]) {
            break;
        }
        if line(s[i]) {
            same = false;
            i += 1;
            break;
        }
        i += 1;
    }
    if i == s.len() {
        return Ok(Some((at, at)));
    }
    let Some(j) = pass(s, i, work)? else {
        return Ok(None);
    };
    if same {
        return Ok(if prefix(s, j, b"import") {
            Some((at, at))
        } else if byte(s, j) == b';' {
            Some((j, j + 1))
        } else {
            None
        });
    }
    Ok((!b",.:*%><={[(?|&".contains(&byte(s, j))).then_some((at, at)))
}

fn terminates(b: u8) -> bool {
    b"@.+-^*/<>|~=&\\%{}[]()\"',;#".contains(&b) || blank(b) || line(b)
}
fn word(s: &[u8], at: usize, w: &[u8]) -> Option<usize> {
    (prefix(s, at, w) && terminates(byte(s, at + w.len()))).then_some(at + w.len())
}
fn settled(s: &[u8], mut at: usize, work: &mut usize) -> Result<bool, ScannerError> {
    if byte(s, at) == b':' {
        return Ok(!blank(byte(s, at + 1)) && !line(byte(s, at + 1)));
    }
    while at < s.len() && blank(s[at]) {
        charge(work)?;
        at += 1;
    }
    if byte(s, at) != b'/' {
        return Ok(true);
    }
    at += 1;
    while at < s.len() && (blank(s[at]) || line(s[at])) {
        charge(work)?;
        at += 1;
    }
    Ok(!byte(s, at).is_ascii_digit())
}
fn continues(s: &[u8], at: usize, work: &mut usize) -> Result<bool, ScannerError> {
    const OPS: &[&[u8]] = &[
        b"&&", b"&&&", b"=", b"==", b"===", b"=~", b"=>", b"::", b"++", b"+++", b"--", b"---",
        b"->", b"<", b"<=", b"<-", b"<>", b"<~", b"<~>", b"<|>", b"<<<", b"<<~", b">", b">=",
        b">>>", b"^^^", b"!=", b"!==", b"~>", b"~>>", b"|", b"||", b"|||", b"|>", b"*", b"**",
        b"/", b"//", b".", b"..", b"\\\\",
    ];
    let mut n = 0;
    let mut got = None;
    loop {
        charge(work)?;
        let accepts = OPS.iter().any(|op| op.len() == n + 1 && prefix(s, at, op));
        let deeper = OPS
            .iter()
            .any(|op| op.len() > n + 1 && s.get(at..at + n + 1) == Some(&op[..n + 1]));
        if !accepts && !deeper {
            break;
        }
        n += 1;
        got = accepts.then_some(n);
        if !deeper {
            break;
        }
    }
    if let Some(n) = got {
        if n == 2 && (prefix(s, at, b":::") || prefix(s, at, b"...")) {
            return Ok(false);
        }
        return settled(s, at + n, work);
    }
    for w in [b"when".as_slice(), b"and", b"or", b"in"] {
        if let Some(end) = word(s, at, w) {
            return settled(s, end, work);
        }
    }
    if !prefix(s, at, b"not") {
        return Ok(false);
    }
    let mut j = at + 3;
    while j < s.len() && blank(s[j]) {
        charge(work)?;
        j += 1;
    }
    if let Some(end) = word(s, j, b"in") {
        settled(s, end, work)
    } else {
        Ok(false)
    }
}
fn elixir(
    s: &[u8],
    at: usize,
    asks: [bool; 3],
    work: &mut usize,
) -> Result<Option<(usize, usize, usize)>, ScannerError> {
    if !asks.iter().any(|b| *b) {
        return Ok(None);
    }
    let mut i = at;
    while i < s.len() && blank(s[i]) {
        charge(work)?;
        i += 1;
    }
    if !line(byte(s, i)) {
        return Ok(None);
    }
    let from = i;
    i += 1;
    while i < s.len() && (blank(s[i]) || line(s[i])) {
        charge(work)?;
        i += 1;
    }
    let slot = match byte(s, i) {
        b'#' if asks[0] => 0,
        b'd' if asks[1] && word(s, i, b"do").is_some() => 1,
        b'#' | b'd' => return Ok(None),
        _ if asks[2] && continues(s, i, work)? => 2,
        _ => return Ok(None),
    };
    Ok(Some((slot, from, i)))
}

fn css(
    s: &[u8],
    at: usize,
    descendant: bool,
    colon: bool,
    work: &mut usize,
) -> Result<Option<(usize, usize, usize)>, ScannerError> {
    if descendant && space(byte(s, at)) {
        let mut i = at;
        while i < s.len() && space(s[i]) {
            charge(work)?;
            i += 1;
        }
        match byte(s, i) {
            b'#' | b'.' | b'[' | b'-' | b'*' => return Ok(Some((0, i, i))),
            b':' => {
                if space(byte(s, i + 1)) {
                    return Ok(None);
                }
                let mut j = i + 1;
                while j < s.len() {
                    charge(work)?;
                    match s[j] {
                        b';' | b'}' => return Ok(None),
                        b'{' => return Ok(Some((0, i, i))),
                        _ => j += 1,
                    }
                }
                return Ok(None);
            }
            b if b.is_ascii_alphanumeric() => return Ok(Some((0, i, i))),
            _ => {}
        }
    }
    if !colon {
        return Ok(None);
    }
    let mut i = at;
    while i < s.len() && space(s[i]) {
        charge(work)?;
        i += 1;
    }
    if byte(s, i) != b':' || byte(s, i + 1) == b':' {
        return Ok(None);
    }
    let mut j = i + 1;
    let mut commented = false;
    while j < s.len() && !matches!(s[j], b';' | b'}') {
        charge(work)?;
        j += 1;
        if j == s.len() {
            break;
        }
        if s[j] == b'{' && !commented {
            return Ok(Some((1, i, i + 1)));
        }
        if s[j] == b'/' && !commented {
            j += 1;
            if byte(s, j) == b'*' {
                commented = true;
            }
        } else if s[j] == b'*' && commented {
            j += 1;
            if byte(s, j) == b'/' {
                commented = false;
            }
        }
    }
    Ok((j >= s.len()).then_some((1, i, i + 1)))
}
fn toml(
    s: &[u8],
    at: usize,
    asks: [bool; 5],
    work: &mut usize,
) -> Result<Option<(usize, usize, usize)>, ScannerError> {
    for (q, content, end) in [(b'"', 1, 2), (b'\'', 3, 4)] {
        if !asks[end] || byte(s, at) != q {
            continue;
        }
        let mut i = at;
        while i < s.len() && s[i] == q {
            charge(work)?;
            i += 1;
        }
        let (slot, n) = match i - at {
            1 | 2 => (content, i - at),
            3 => (end, 3),
            _ => (content, 1),
        };
        if asks[slot] {
            return Ok(Some((slot, at, at + n)));
        }
    }
    if asks[0] {
        let mut i = at;
        while i < s.len() && blank(s[i]) {
            charge(work)?;
            i += 1;
        }
        if i == s.len() || byte(s, i) == b'\n' {
            return Ok(Some((0, i, i)));
        }
        if prefix(s, i, b"\r\n") {
            return Ok(Some((0, i + 1, i + 1)));
        }
    }
    Ok(None)
}

fn symop(b: u8) -> bool {
    b"!#$%&*+./<=>?@\\^|~:-".contains(&b)
}
fn documents(s: &[u8], at: usize, work: &mut usize) -> Result<Option<usize>, ScannerError> {
    let mut i = at + 2;
    while byte(s, i) == b'-' {
        charge(work)?;
        i += 1;
    }
    while i < s.len() {
        charge(work)?;
        if s[i] >= 0x80 {
            return Ok(None);
        }
        if matches!(s[i], b'|' | b'^') {
            return Ok(Some(1));
        }
        if !space(s[i]) {
            break;
        }
        i += 1;
    }
    Ok(Some(0))
}
fn haskell(
    s: &[u8],
    at: usize,
    asks: [bool; 4],
    work: &mut usize,
) -> Result<Option<(usize, usize)>, ScannerError> {
    if prefix(s, at, b"{-#") {
        if !asks[3] {
            return Ok(None);
        }
        let mut i = at + 2;
        while i + 3 <= s.len() {
            charge(work)?;
            if prefix(s, i, b"#-}") {
                return Ok(Some((3, i + 3)));
            }
            i += 1;
        }
        return Ok(None);
    }
    if prefix(s, at, b"{-") {
        let Some(slot) = documents(s, at, work)? else {
            return Ok(None);
        };
        if !asks[slot] {
            return Ok(None);
        }
        let mut i = at + 2;
        let mut nesting = 0usize;
        while i < s.len() {
            charge(work)?;
            if prefix(s, i, b"{-") {
                nesting = nesting
                    .checked_add(1)
                    .ok_or(ScannerError::Limit("nested block comments"))?;
                i += 2;
            } else if prefix(s, i, b"-}") {
                i += 2;
                if nesting == 0 {
                    return Ok(Some((slot, i)));
                }
                nesting -= 1;
            } else {
                i += 1;
            }
        }
        return Ok(Some((slot, i)));
    }
    if prefix(s, at, b"--") {
        let mut i = at;
        while byte(s, i) == b'-' {
            charge(work)?;
            i += 1;
        }
        if byte(s, i) >= 0x80 || symop(byte(s, i)) {
            return Ok(None);
        }
        let Some(slot) = documents(s, at, work)? else {
            return Ok(None);
        };
        if !asks[slot] {
            return Ok(None);
        }
        loop {
            while i < s.len() && s[i] != b'\n' {
                charge(work)?;
                i += 1;
            }
            if i == s.len() {
                return Ok(Some((slot, i)));
            }
            let mut j = i + 1;
            while j < s.len() && blank(s[j]) {
                charge(work)?;
                j += 1;
            }
            let from = j;
            while byte(s, j) == b'-' {
                charge(work)?;
                j += 1;
            }
            if j - from < 2 || byte(s, j) >= 0x80 || symop(byte(s, j)) {
                return Ok(Some((slot, i)));
            }
            i = j;
        }
    }
    if byte(s, at) == b'#' && asks[2] {
        let mut i = at + 1;
        while i < s.len() && blank(s[i]) {
            charge(work)?;
            i += 1;
        }
        if !byte(s, i).is_ascii_alphabetic() {
            return Ok(None);
        }
        while i < s.len() && s[i] != b'\n' {
            charge(work)?;
            if s[i] == b'\\' {
                i += 1;
                while i < s.len() && blank(s[i]) {
                    charge(work)?;
                    i += 1;
                }
                if byte(s, i) == b'\n' {
                    i += 1;
                }
            } else {
                i += 1;
            }
        }
        return Ok(Some((2, i)));
    }
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ecma_context_and_comments_decide_a_break() {
        for (source, binary, expected) in [
            (b"\n(x)".as_slice(), true, false),
            (b"\n(x)", false, true),
            (b"\n/* c */ + 1", true, false),
            (b"\n++x", true, true),
            (b"\nin value", true, false),
            (b"\ninteger", true, true),
            (b"}:x", false, false),
        ] {
            assert_eq!(
                ecma(source, 0, binary, false, &mut 1000).unwrap(),
                expected,
                "{source:?}"
            );
        }
        assert!(!ecma(b"\n{", 0, true, true, &mut 1000).unwrap());
    }
    #[test]
    fn tongues_preserve_their_different_separator_rules() {
        assert_eq!(swift(b" ;x", 0, &mut 1000).unwrap(), Some((true, 1, 2)));
        assert!(swift(b"", 0, &mut 1000).unwrap().is_none());
        assert!(swift(b"\n+1", 0, &mut 1000).unwrap().is_some());
        assert!(kotlin(b" importx", 0, &mut 1000).unwrap().is_some());
        assert!(kotlin(b"\n[1]", 0, &mut 1000).unwrap().is_none());
        assert_eq!(
            elixir(b" \n  do x", 0, [true; 3], &mut 1000).unwrap(),
            Some((1, 1, 4))
        );
        assert!(elixir(b"\ndo", 0, [true; 3], &mut 1000).unwrap().is_none());
        assert!(!continues(b"<< x", 0, &mut 1000).unwrap());
        assert!(continues(b"<<< x", 0, &mut 1000).unwrap());
        assert!(!continues(b"... x", 0, &mut 1000).unwrap());
    }
    #[test]
    fn toml_quote_runs_and_line_ending_have_exact_extents() {
        for (source, slot, end) in [
            (b"\"".as_slice(), 1, 1),
            (b"\"\"", 1, 2),
            (b"\"\"\"", 2, 3),
            (b"\"\"\"\"", 1, 1),
        ] {
            assert_eq!(
                toml(source, 0, [true; 5], &mut 1000).unwrap(),
                Some((slot, 0, end))
            );
        }
        assert_eq!(
            toml(b" \t\r\n", 0, [true; 5], &mut 1000).unwrap(),
            Some((0, 3, 3))
        );
        assert!(toml(b"\r", 0, [true; 5], &mut 1000).unwrap().is_none());
    }
    #[test]
    fn haskell_extras_refuse_operator_and_unicode_guesses() {
        assert_eq!(
            haskell(b"{-# CPP #-}", 0, [true; 4], &mut 1000).unwrap(),
            Some((3, 11))
        );
        assert_eq!(
            haskell(b"{- a {- b -} -}", 0, [true; 4], &mut 1000).unwrap(),
            Some((0, 15))
        );
        assert_eq!(
            haskell(b"-- | docs\n  -- next\nx", 0, [true; 4], &mut 1000).unwrap(),
            Some((1, 19))
        );
        assert!(
            haskell(b"--> x", 0, [true; 4], &mut 1000)
                .unwrap()
                .is_none()
        );
        assert!(
            haskell("--→ x".as_bytes(), 0, [true; 4], &mut 1000)
                .unwrap()
                .is_none()
        );
        assert!(
            haskell(b"{-# X #-}", 0, [true, false, false, false], &mut 1000)
                .unwrap()
                .is_none()
        );
    }
    #[test]
    fn css_colon_branch_does_not_fall_back_after_descendant_refusal() {
        assert_eq!(
            css(b":hover {", 0, false, true, &mut 1000).unwrap(),
            Some((1, 0, 1))
        );
        assert!(
            css(b" :hover;", 0, true, true, &mut 1000)
                .unwrap()
                .is_none()
        );
        assert_eq!(
            css(b" :hover {", 0, true, true, &mut 1000).unwrap(),
            Some((0, 1, 1))
        );
    }
    #[test]
    fn every_unbounded_walk_spends_the_shared_budget() {
        assert!(matches!(
            ecma(&[b' '; 20], 0, true, false, &mut 1),
            Err(ScannerError::Limit(_))
        ));
        assert!(matches!(
            haskell(b"{- aaaaaaaaaaaaa", 0, [true; 4], &mut 1),
            Err(ScannerError::Limit(_))
        ));
    }
}
