//! Stateless bounded interiors: permissions select a mark, byte walks find its extent.

use super::{ScanHit, ScannerError, charge};
use crate::{compiler::Automaton, ids::SymbolId};

#[derive(Clone, Copy)]
enum Vein {
    RustBlock,
    SlashStar,
    Ocaml,
    RustString,
    Cpp,
    JuliaBlock,
    LuaString,
    LuaComment,
}
struct Row {
    body: SymbolId,
    close: Option<SymbolId>,
    open: Option<SymbolId>,
    vein: Vein,
    hush: Option<SymbolId>,
    evidence: Vec<SymbolId>,
}
#[derive(Clone, Copy)]
enum Walk {
    Julia,
    Php,
    Latex,
}
struct Mark {
    symbol: SymbolId,
    shut: u8,
    wide: usize,
    interpolates: bool,
    after: bool,
    tail: &'static [u8],
    command: bool,
}
struct Family {
    walk: Walk,
    marks: Vec<Mark>,
    closes: Vec<(u8, SymbolId)>,
    rivals: Vec<SymbolId>,
    lone: bool,
}
pub(super) struct Bounded {
    rows: Vec<Row>,
    families: Vec<Family>,
}
fn cohort(g: &Automaton, names: &[&str]) -> Option<Vec<SymbolId>> {
    names.iter().map(|s| g.external_by_name(s)).collect()
}
impl Bounded {
    pub(super) fn bind(g: &Automaton) -> Self {
        let mut rows = Vec::new();
        for (names, vein, body, close, open, hush) in [
            (
                &[
                    "_block_comment_content",
                    "_outer_block_doc_comment_marker",
                    "_inner_block_doc_comment_marker",
                ][..],
                Vein::RustBlock,
                0,
                None,
                None,
                None,
            ),
            (
                &["raw_string_content", "raw_string_delimiter"][..],
                Vein::Cpp,
                0,
                None,
                Some(1),
                None,
            ),
            (
                &["block_comment", "_suppress_block_comment"][..],
                Vein::SlashStar,
                0,
                None,
                None,
                None,
            ),
            (
                &["comment", "_left_quoted_string_delimiter"][..],
                Vein::Ocaml,
                0,
                None,
                None,
                None,
            ),
            (
                &["_block_comment_rest", "_immediate_paren"][..],
                Vein::JuliaBlock,
                0,
                None,
                None,
                None,
            ),
            (
                &[
                    "_block_string_content",
                    "_block_string_end",
                    "_block_string_start",
                    "_block_comment_start",
                ][..],
                Vein::LuaString,
                0,
                Some(1),
                Some(2),
                None,
            ),
            (
                &[
                    "_block_comment_content",
                    "_block_comment_end",
                    "_block_comment_start",
                    "_block_string_start",
                ][..],
                Vein::LuaComment,
                0,
                Some(1),
                Some(2),
                None,
            ),
            (
                &["string_content", "string_close", "_line_doc_content"][..],
                Vein::RustString,
                0,
                Some(1),
                None,
                Some("float_literal"),
            ),
        ] {
            if let Some(ids) = cohort(g, names) {
                rows.push(Row {
                    body: ids[body],
                    close: close.map(|i| ids[i]),
                    open: open.map(|i| ids[i]),
                    vein,
                    hush: hush.and_then(|s| g.terminal_by_name(s)),
                    evidence: if matches!(vein, Vein::RustBlock) {
                        ids
                    } else {
                        Vec::new()
                    },
                });
            }
        }
        let mut families = Vec::new();
        let julia = [
            "_content_str_1",
            "_content_str_3",
            "_content_cmd_1",
            "_content_cmd_3",
            "_content_str_1_raw",
            "_content_str_3_raw",
            "_content_cmd_1_raw",
            "_content_cmd_3_raw",
            "_end_str",
            "_end_cmd",
        ];
        if let Some(ids) = cohort(g, &julia) {
            let marks = ids[..8]
                .iter()
                .enumerate()
                .map(|(i, &symbol)| Mark {
                    symbol,
                    shut: if i % 4 < 2 { b'"' } else { b'`' },
                    wide: if i % 2 == 0 { 1 } else { 3 },
                    interpolates: i < 4,
                    after: false,
                    tail: b"",
                    command: false,
                })
                .collect();
            families.push(Family {
                walk: Walk::Julia,
                marks,
                closes: vec![(b'"', ids[8]), (b'`', ids[9])],
                rivals: vec![ids[0], ids[2]],
                lone: false,
            });
        }
        let php = [
            "encapsed_string_chars_after_variable",
            "encapsed_string_chars",
            "execution_string_chars_after_variable",
            "execution_string_chars",
            "sentinel_error",
        ];
        if let Some(ids) = cohort(g, &php) {
            let marks = ids[..4]
                .iter()
                .enumerate()
                .map(|(i, &symbol)| Mark {
                    symbol,
                    shut: if i < 2 { b'"' } else { b'`' },
                    wide: 1,
                    interpolates: false,
                    after: i % 2 == 0,
                    tail: b"",
                    command: false,
                })
                .collect();
            families.push(Family {
                walk: Walk::Php,
                marks,
                closes: Vec::new(),
                rivals: vec![ids[1], ids[3]],
                lone: false,
            });
        }
        let latex = [
            ("_trivia_raw_fi", b"fi".as_slice()),
            ("_trivia_raw_env_comment", b"end{comment}"),
            ("_trivia_raw_env_verbatim", b"end{verbatim}"),
            ("_trivia_raw_env_listing", b"end{lstlisting}"),
            ("_trivia_raw_env_minted", b"end{minted}"),
            ("_trivia_raw_env_asy", b"end{asy}"),
            ("_trivia_raw_env_asydef", b"end{asydef}"),
            ("_trivia_raw_env_pycode", b"end{pycode}"),
            ("_trivia_raw_env_luacode", b"end{luacode}"),
            ("_trivia_raw_env_luacode_star", b"end{luacode*}"),
            ("_trivia_raw_env_sagesilent", b"end{sagesilent}"),
            ("_trivia_raw_env_sageblock", b"end{sageblock}"),
        ];
        if let Some(ids) = cohort(g, &latex.iter().map(|x| x.0).collect::<Vec<_>>()) {
            let marks = ids
                .iter()
                .zip(latex)
                .enumerate()
                .map(|(i, (&symbol, (_, tail)))| Mark {
                    symbol,
                    shut: b'\\',
                    wide: 1,
                    interpolates: false,
                    after: false,
                    tail,
                    command: i == 0,
                })
                .collect();
            families.push(Family {
                walk: Walk::Latex,
                marks,
                closes: Vec::new(),
                rivals: Vec::new(),
                lone: true,
            });
        }
        Self { rows, families }
    }
    pub(super) fn remove_claimed(&mut self, claimed: &[SymbolId]) {
        self.rows.retain(|r| !claimed.contains(&r.body));
        self.families
            .retain(|f| !f.marks.iter().any(|m| claimed.contains(&m.symbol)));
    }
    pub(super) fn claims(&self, s: SymbolId) -> bool {
        self.rows.iter().any(|r| {
            r.body == s || r.close == Some(s) || r.open == Some(s) || r.evidence.contains(&s)
        }) || self
            .families
            .iter()
            .any(|f| f.marks.iter().any(|m| m.symbol == s) || f.closes.iter().any(|x| x.1 == s))
    }
    pub(super) fn step(
        &self,
        source: &[u8],
        at: usize,
        wanted: &[SymbolId],
        already: &[SymbolId],
        remaining: &mut usize,
    ) -> Result<Option<ScanHit>, ScannerError> {
        if at > source.len() {
            return Ok(None);
        }
        for row in &self.rows {
            // Ambiguous content can be hushed without hiding an unambiguous
            // closing delimiter (Rust keeps STRING_CLOSE beside FLOAT_LITERAL).
            if !row.hush.is_some_and(|s| wanted.contains(&s)) && wanted.contains(&row.body) {
                let end = match row.vein {
                    Vein::RustBlock => nested(source, at, b"/*", b"*/", false, remaining)?,
                    Vein::SlashStar => slash_star(source, at, remaining)?,
                    Vein::Ocaml => nested(source, at, b"(*", b"*)", true, remaining)?,
                    Vein::RustString => string(source, at, remaining)?,
                    Vein::Cpp => cpp(source, at, remaining)?,
                    Vein::JuliaBlock => julia_block(source, at, remaining)?,
                    Vein::LuaString | Vein::LuaComment => lua_content(source, at, remaining)?,
                };
                if let Some(end) = end.filter(|&end| end > at || !already.contains(&row.body)) {
                    return Ok(Some(ScanHit {
                        symbol: row.body,
                        start: at,
                        end,
                    }));
                }
            }
            if let Some(symbol) = row.close.filter(|s| wanted.contains(s)) {
                let end = match row.vein {
                    Vein::RustString if source.get(at) == Some(&b'"') => Some(at + 1),
                    Vein::LuaString | Vein::LuaComment => lua_bracket(source, at, b']', remaining)?,
                    _ => None,
                };
                if let Some(end) = end {
                    return Ok(Some(ScanHit {
                        symbol,
                        start: at,
                        end,
                    }));
                }
            }
            if let Some(symbol) = row.open.filter(|s| wanted.contains(s)) {
                let end = match row.vein {
                    Vein::Cpp => cpp_tag(source, at),
                    Vein::LuaString => lua_bracket(source, at, b'[', remaining)?,
                    Vein::LuaComment if source[at..].starts_with(b"--") => {
                        lua_bracket(source, at + 2, b'[', remaining)?
                    }
                    _ => None,
                };
                if let Some(end) = end {
                    return Ok(Some(ScanHit {
                        symbol,
                        start: at,
                        end,
                    }));
                }
            }
        }
        for family in &self.families {
            if family.rivals.len() > 1 && family.rivals.iter().all(|s| wanted.contains(s)) {
                continue;
            }
            if family.lone
                && family
                    .marks
                    .iter()
                    .filter(|m| wanted.contains(&m.symbol))
                    .count()
                    > 1
            {
                continue;
            }
            for mark in &family.marks {
                if !wanted.contains(&mark.symbol) {
                    continue;
                }
                let run = match family.walk {
                    Walk::Julia => julia(mark, source, at, remaining)?,
                    Walk::Php => php(mark, source, at, remaining)?.map(|end| (false, end)),
                    Walk::Latex => verbatim(mark, source, at, remaining)?.map(|end| (false, end)),
                };
                match run {
                    Some((false, end)) => {
                        return Ok(Some(ScanHit {
                            symbol: mark.symbol,
                            start: at,
                            end,
                        }));
                    }
                    Some((true, end)) => {
                        if let Some((_, symbol)) = family.closes.iter().find(|x| x.0 == mark.shut) {
                            if wanted.contains(symbol) {
                                return Ok(Some(ScanHit {
                                    symbol: *symbol,
                                    start: at,
                                    end,
                                }));
                            }
                        }
                        return Ok(None);
                    }
                    None => return Ok(None),
                }
            }
        }
        Ok(None)
    }
}
fn nested(
    source: &[u8],
    at: usize,
    open: &[u8],
    close: &[u8],
    whole: bool,
    remaining: &mut usize,
) -> Result<Option<usize>, ScannerError> {
    if if whole {
        !source[at..].starts_with(open)
    } else {
        !source[..at].ends_with(open)
    } {
        return Ok(None);
    }
    let mut i = at + if whole { open.len() } else { 0 };
    let mut depth = 1;
    while i < source.len() {
        charge(remaining)?;
        if source[i..].starts_with(open) {
            depth += 1;
            i += open.len();
        } else if source[i..].starts_with(close) {
            if depth == 1 {
                return Ok((whole || i > at).then_some(i + if whole { close.len() } else { 0 }));
            }
            depth -= 1;
            i += close.len();
        } else {
            i += 1;
        }
    }
    Ok((i > at).then_some(i))
}
fn slash_star(
    source: &[u8],
    at: usize,
    remaining: &mut usize,
) -> Result<Option<usize>, ScannerError> {
    if !source[at..].starts_with(b"/*") {
        return Ok(None);
    }
    let (mut i, mut depth, mut star) = (at + 2, 1, false);
    while i < source.len() {
        charge(remaining)?;
        match source[i] {
            b'*' => {
                i += 1;
                star = true;
            }
            b'/' => {
                i += 1;
                if star {
                    star = false;
                    depth -= 1;
                    if depth == 0 {
                        return Ok(Some(i));
                    }
                } else if source.get(i) == Some(&b'*') {
                    depth += 1;
                    i += 1;
                }
            }
            _ => {
                i += 1;
                star = false;
            }
        }
    }
    Ok(Some(i))
}
fn string(source: &[u8], at: usize, remaining: &mut usize) -> Result<Option<usize>, ScannerError> {
    let mut i = at;
    while i < source.len() && !matches!(source[i], b'"' | b'\\') {
        charge(remaining)?;
        i += 1;
    }
    Ok((i > at && i < source.len()).then_some(i))
}
fn julia_block(
    source: &[u8],
    at: usize,
    remaining: &mut usize,
) -> Result<Option<usize>, ScannerError> {
    let (mut i, mut depth, mut equals) = (at, 1, false);
    while i < source.len() {
        charge(remaining)?;
        match source[i] {
            b'=' => {
                i += 1;
                equals = true;
            }
            b'#' => {
                i += 1;
                if equals {
                    equals = false;
                    depth -= 1;
                    if depth == 0 {
                        return Ok(Some(i));
                    }
                } else if source.get(i) == Some(&b'=') {
                    depth += 1;
                    i += 1;
                }
            }
            _ => {
                i += 1;
                equals = false;
            }
        }
    }
    Ok(None)
}
fn lua_bracket(
    source: &[u8],
    at: usize,
    side: u8,
    remaining: &mut usize,
) -> Result<Option<usize>, ScannerError> {
    if source.get(at) != Some(&side) {
        return Ok(None);
    }
    let mut i = at + 1;
    while source.get(i) == Some(&b'=') {
        charge(remaining)?;
        i += 1;
    }
    Ok((source.get(i) == Some(&side)).then_some(i + 1))
}
fn lua_content(
    source: &[u8],
    at: usize,
    remaining: &mut usize,
) -> Result<Option<usize>, ScannerError> {
    if at == 0 || source[at - 1] != b'[' {
        return Ok(None);
    }
    let mut j = at - 1;
    while j > 0 && source[j - 1] == b'=' {
        charge(remaining)?;
        j -= 1;
    }
    if j == 0 || source[j - 1] != b'[' {
        return Ok(None);
    }
    let level = at - j + 1;
    let mut i = at;
    while i < source.len() {
        charge(remaining)?;
        if source[i] == b']'
            && lua_bracket(source, i, b']', remaining)?.is_some_and(|end| end - i == level)
        {
            return Ok(Some(i));
        }
        i += 1;
    }
    Ok(None)
}
fn tag_byte(c: u8) -> bool {
    c > 32 && !matches!(c, b'(' | b')' | b'\\' | b'"')
}
fn cpp_tag(source: &[u8], at: usize) -> Option<usize> {
    if at == 0 || at > source.len() {
        return None;
    }
    let end = if source[at - 1] == b'"' {
        b'('
    } else if source[at - 1] == b')' {
        b'"'
    } else {
        return None;
    };
    let mut i = at;
    while i < source.len() && i - at < 16 && tag_byte(source[i]) {
        i += 1;
    }
    (i > at && source.get(i) == Some(&end)).then_some(i)
}
fn cpp(source: &[u8], at: usize, remaining: &mut usize) -> Result<Option<usize>, ScannerError> {
    if at == 0 || source[at - 1] != b'(' {
        return Ok(None);
    }
    let mut j = at - 1;
    let mut delimiter = None;
    while j > 0 && at - j <= 17 {
        charge(remaining)?;
        if source[j - 1] == b'"' {
            delimiter = Some(&source[j..at - 1]);
            break;
        }
        if !tag_byte(source[j - 1]) {
            return Ok(None);
        }
        j -= 1;
    }
    let Some(delimiter) = delimiter else {
        return Ok(None);
    };
    let mut mark = vec![b')'];
    mark.extend_from_slice(delimiter);
    mark.push(b'"');
    let mut i = at;
    while i < source.len() {
        charge(remaining)?;
        if source[i..].starts_with(&mark) {
            return Ok((i > at).then_some(i));
        }
        i += 1;
    }
    Ok(None)
}
fn julia(
    mark: &Mark,
    source: &[u8],
    at: usize,
    remaining: &mut usize,
) -> Result<Option<(bool, usize)>, ScannerError> {
    let (mut i, mut any) = (at, false);
    loop {
        charge(remaining)?;
        let Some(&next) = source.get(i) else {
            return Ok(None);
        };
        if next == 0 {
            return Ok(None);
        }
        let end = i;
        if mark.interpolates && matches!(next, b'$' | b'\\') {
            return Ok(any.then_some((false, end)));
        } else if next == b'\\' {
            i += 1;
            if source
                .get(i)
                .is_some_and(|c| *c == mark.shut || *c == b'\\')
            {
                return Ok(any.then_some((false, end)));
            }
        } else {
            let mut width = 0;
            while width < mark.wide && source.get(i) == Some(&mark.shut) {
                i += 1;
                width += 1;
            }
            if width == mark.wide {
                return Ok(Some((!any, if any { end } else { at + mark.wide })));
            }
        }
        if i < source.len() {
            i += 1;
        }
        any = true;
    }
}
fn names(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_' || c >= 128
}
fn escapes(source: &[u8], i: &mut usize) -> bool {
    match source.get(*i) {
        Some(
            b'n' | b'r' | b't' | b'v' | b'e' | b'f' | b'\\' | b'$' | b'"' | b'u' | b'0'..=b'7',
        ) => true,
        Some(b'x') => {
            *i += 1;
            source.get(*i).is_some_and(u8::is_ascii_hexdigit)
        }
        _ => false,
    }
}
fn php(
    mark: &Mark,
    source: &[u8],
    at: usize,
    remaining: &mut usize,
) -> Result<Option<usize>, ScannerError> {
    let (mut i, mut after, mut any) = (at, mark.after, false);
    loop {
        charge(remaining)?;
        let end = i;
        let Some(&next) = source.get(i) else {
            return Ok(None);
        };
        if next == mark.shut {
            return Ok(any.then_some(end));
        }
        match next {
            b'\\' => {
                i += 1;
                if source.get(i) == Some(&b'{') {
                    i += 1;
                } else if (mark.shut == b'`' && source.get(i) == Some(&b'`'))
                    || escapes(source, &mut i)
                {
                    return Ok(any.then_some(end));
                }
            }
            b'$' => {
                i += 1;
                if source
                    .get(i)
                    .is_some_and(|c| *c == b'{' || (names(*c) && !c.is_ascii_digit()))
                {
                    return Ok(any.then_some(end));
                }
            }
            b'-' => {
                i += 1;
                if after && source.get(i) == Some(&b'>') {
                    i += 1;
                    if source.get(i).is_some_and(|c| names(*c)) {
                        return Ok(any.then_some(end));
                    }
                }
            }
            b'[' => {
                if after {
                    return Ok(any.then_some(end));
                }
                i += 1;
            }
            b'{' => {
                i += 1;
                if source.get(i) == Some(&b'$') {
                    return Ok(any.then_some(end));
                }
            }
            _ => i += 1,
        }
        after = false;
        any = true;
    }
}
fn verbatim(
    mark: &Mark,
    source: &[u8],
    at: usize,
    remaining: &mut usize,
) -> Result<Option<usize>, ScannerError> {
    let (mut i, mut end) = (at, None);
    let whole = mark.tail.len() + 1;
    while i < source.len() {
        charge(remaining)?;
        let mut n = 0;
        while n < whole
            && i + n < source.len()
            && source[i + n] == if n == 0 { mark.shut } else { mark.tail[n - 1] }
        {
            charge(remaining)?;
            n += 1;
        }
        if i + n >= source.len() && n < whole {
            break;
        }
        if n == 0 {
            i += 1;
            end = Some(i);
        } else if n < whole {
            i += n;
        } else {
            if !mark.command
                || i + whole >= source.len()
                || !source[i + whole].is_ascii_alphabetic() && !b":_@".contains(&source[i + whole])
            {
                break;
            }
            i += whole;
            end = Some(i);
        }
    }
    Ok(end)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn mark(shut: u8, wide: usize, interpolates: bool) -> Mark {
        Mark {
            symbol: SymbolId::from_index(1),
            shut,
            wide,
            interpolates,
            after: false,
            tail: b"",
            command: false,
        }
    }
    #[test]
    fn quoted_families_keep_distinct_eof_interpolation_and_delimiter_semantics() {
        let m = mark(b'"', 3, true);
        assert_eq!(
            julia(&m, b"ab\"\"cd\"\"\"", 0, &mut 100).unwrap(),
            Some((false, 6))
        );
        assert_eq!(
            julia(&m, b"\"\"\"tail", 0, &mut 100).unwrap(),
            Some((true, 3))
        );
        assert_eq!(julia(&m, b"unterminated", 0, &mut 100).unwrap(), None);
        let m = mark(b'"', 1, false);
        assert_eq!(php(&m, b"$1\"", 0, &mut 100).unwrap(), Some(2));
        assert_eq!(php(&m, b"abc$name\"", 0, &mut 100).unwrap(), Some(3));
        assert_eq!(php(&m, b"unterminated", 0, &mut 100).unwrap(), None);
        let m = Mark {
            tail: b"fi",
            command: true,
            ..mark(b'\\', 1, false)
        };
        assert_eq!(
            verbatim(&m, b"a\\fifoo b\\fi", 0, &mut 100).unwrap(),
            Some(9)
        );
    }
    #[test]
    fn bounded_comments_and_cpp_marks_preserve_extent_and_fuel() {
        assert_eq!(
            nested(b"/*a/*b*/c*/tail", 2, b"/*", b"*/", false, &mut 100).unwrap(),
            Some(9)
        );
        assert_eq!(
            nested(b"(*a(*b*)c*)tail", 0, b"(*", b"*)", true, &mut 100).unwrap(),
            Some(11)
        );
        assert_eq!(
            cpp(b"R\"tag(a )other\" b)tag\"", 6, &mut 100).unwrap(),
            Some(17)
        );
        assert_eq!(cpp_tag(b"R\"tag(", 2), Some(5));
        assert!(matches!(
            nested(b"(*abcdefgh", 0, b"(*", b"*)", true, &mut 2),
            Err(ScannerError::Limit("program work"))
        ));
    }
}

#[cfg(test)]
mod long_brackets {
    use super::*;
    use serde_json::json;
    #[test]
    fn empty_long_bracket_body_yields_to_its_closer_at_the_same_offset() {
        let names = [
            "_block_string_start",
            "_block_string_content",
            "_block_string_end",
            "_block_comment_start",
        ];
        let graph=Automaton::from_tree_sitter(&serde_json::to_vec(&json!({"name":"long-bracket","externals":names.iter().map(|name|json!({"type":"SYMBOL","name":name})).collect::<Vec<_>>(),"rules":{"doc":{"type":"STRING","value":"x"}}})).unwrap()).unwrap();
        let program = Bounded::bind(&graph);
        let body = graph.external_by_name(names[1]).unwrap();
        let close = graph.external_by_name(names[2]).unwrap();
        assert_eq!(
            program
                .step(b"[[]]", 2, &[body, close], &[], &mut 100)
                .unwrap()
                .unwrap(),
            ScanHit {
                symbol: body,
                start: 2,
                end: 2
            }
        );
        assert_eq!(
            program
                .step(b"[[]]", 2, &[body, close], &[body], &mut 100)
                .unwrap()
                .unwrap(),
            ScanHit {
                symbol: close,
                start: 2,
                end: 4
            }
        );
        assert_eq!(
            lua_content(b"[==[a ]] b]==]", 4, &mut 100).unwrap(),
            Some(10)
        );
        assert_eq!(
            julia_block(b"a #= b =# c =#", 0, &mut 100).unwrap(),
            Some(14)
        );
    }
}
