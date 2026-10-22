//! Byte-oriented scanner probes. Ordinary tokens keep the linear DFA backend.

use std::ops::Range;

use irgx::{Regex, RegexBuilder};

use super::ScannerError;

fn native_error(error: irgx::Error) -> ScannerError {
    match &error {
        irgx::Error::Groups {
            detail: Some(name), ..
        }
        | irgx::Error::Search {
            detail: Some(name), ..
        }
        | irgx::Error::OutOfMemory { detail: Some(name) }
            if name == "BudgetExceeded" =>
        {
            ScannerError::Limit("probe matching")
        }
        _ => ScannerError::Probe(error.to_string()),
    }
}

const MAX_PATTERN_BYTES: usize = 16 << 10;
pub(super) const MAX_CAPTURES: usize = 32;

/// Finite PCRE2 ceilings for each scanner probe or classifier invocation.
///
/// Limits belong to the immutable compiled grammar and every worker handle.
/// Matching uses the interpreter because PCRE2 JIT ignores depth and heap caps.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProbeLimits {
    /// PCRE2 matching steps, in `0..=u32::MAX`. Zero refuses matching work.
    pub match_steps: u64,
    /// Interpreter depth, in `0..=u32::MAX`. Zero refuses interpreter frames.
    pub depth: u64,
    /// Matching heap bytes, a whole number of KiB, including zero.
    ///
    /// Must fit both `usize` and PCRE2's `u32` KiB counter. This bounds PCRE2
    /// matching scratch, independently of compiled patterns and capture ranges.
    pub heap_bytes: u64,
}

impl Default for ProbeLimits {
    fn default() -> Self {
        // The authored Elixir heredoc probe needs >1MiB of interpreter frames
        // for a valid 9KiB body. 32Ki depth/4MiB passed that pinned workload;
        // double those measured values leaves headroom while keeping the same
        // 100k step ceiling that bounds backtracking. Callers can set all three.
        Self {
            match_steps: 100_000,
            depth: 65_536,
            heap_bytes: 8 << 20,
        }
    }
}

impl ProbeLimits {
    pub(super) fn validate(self) -> Result<(), ScannerError> {
        if self.match_steps > u32::MAX.into() {
            return Err(ScannerError::InvalidLimits("match_steps exceeds u32::MAX"));
        }
        if self.depth > u32::MAX.into() {
            return Err(ScannerError::InvalidLimits("depth exceeds u32::MAX"));
        }
        if self.heap_bytes > usize::MAX as u64 || self.heap_bytes / 1024 > u64::from(u32::MAX) {
            return Err(ScannerError::InvalidLimits(
                "heap_bytes exceeds the native ceiling",
            ));
        }
        if self.heap_bytes % 1024 != 0 {
            return Err(ScannerError::InvalidLimits(
                "heap_bytes must be a whole number of KiB",
            ));
        }
        Ok(())
    }
}

pub(super) struct Probe {
    regex: Regex,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(super) struct Captures {
    pub slots: Vec<Option<Range<usize>>>,
}

impl Captures {
    pub(super) fn group<'a>(&self, source: &'a [u8], group: usize) -> &'a [u8] {
        self.slots
            .get(group)
            .and_then(Option::as_ref)
            .and_then(|range| source.get(range.clone()))
            .unwrap_or_default()
    }
    pub(super) fn width(&self) -> usize {
        self.slots
            .first()
            .and_then(Option::as_ref)
            .map_or(0, |r| r.end - r.start)
    }
}

impl Probe {
    #[cfg(test)]
    pub(super) fn compile(pattern: &str, whole: bool) -> Result<Self, ScannerError> {
        Self::compile_with_limits(pattern, whole, ProbeLimits::default())
    }

    pub(super) fn compile_with_limits(
        pattern: &str,
        whole: bool,
        limits: ProbeLimits,
    ) -> Result<Self, ScannerError> {
        limits.validate()?;
        if pattern.len() > MAX_PATTERN_BYTES {
            return Err(ScannerError::Limit("probe pattern bytes"));
        }
        // PCRE2 is an explicitly selected byte backend, matching the reference.
        // \G anchors at the supplied offset while preserving full lookbehind context.
        // Explicit depth and heap ceilings disable JIT, which ignores those limits.
        let body = if whole {
            format!("(?:{pattern})$")
        } else {
            pattern.to_owned()
        };
        let pattern = format!("\\G(?:{body})");
        let regex = RegexBuilder::new(&pattern)
            .unicode(false)
            .pcre(true)
            .match_limit(limits.match_steps)
            .depth_limit(limits.depth)
            .heap_limit_bytes(limits.heap_bytes)
            .build()
            .map_err(native_error)?;
        if regex.groups().is_none_or(|n| n + 1 > MAX_CAPTURES) {
            return Err(ScannerError::Limit("probe capture groups"));
        }
        Ok(Self { regex })
    }

    pub(super) fn capture(
        &self,
        source: &[u8],
        at: usize,
        remaining: &mut usize,
    ) -> Result<Option<Captures>, ScannerError> {
        if at > source.len() {
            return Ok(None);
        }
        super::charge(remaining)?;
        self.regex
            .try_capture_ranges_at(source, at)
            .map(|matched| matched.map(|slots| Captures { slots }))
            .map_err(native_error)
    }
}

impl std::fmt::Debug for Probe {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("Probe").field(&self.regex.as_str()).finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..")
    }

    fn patterns() -> Vec<(String, String, bool)> {
        let mut found = Vec::new();
        for file in std::fs::read_dir(root().join("customary")).unwrap() {
            let path = file.unwrap().path();
            if path.extension().and_then(|x| x.to_str()) != Some("json") {
                continue;
            }
            let book: serde_json::Value =
                serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
            for (name, value) in book["probes"].as_object().unwrap() {
                found.push((
                    format!("{}:{name}", path.display()),
                    value.as_str().unwrap().into(),
                    false,
                ));
            }
            if let Some(classes) = book["classes"].as_object() {
                for (name, arms) in classes {
                    for (i, arm) in arms.as_array().unwrap().iter().enumerate() {
                        found.push((
                            format!("{}:{name}/{i}", path.display()),
                            arm[0].as_str().unwrap().into(),
                            true,
                        ));
                    }
                }
            }
        }
        found.sort();
        found
    }

    #[test]
    fn every_shipped_probe_compiles_without_rewriting() {
        let patterns = patterns();
        assert_eq!(patterns.len(), 218);
        for (name, pattern, whole) in patterns {
            Probe::compile(&pattern, whole).unwrap_or_else(|e| panic!("{name}: {e}"));
        }
    }

    #[test]
    fn byte_captures_and_lookbehind_match_safe_pcre2_oracle() {
        let mut subjects: Vec<Vec<u8>> = vec![
            b"".to_vec(),
            b"x.foo\n .bar".to_vec(),
            b"##\"a \"# b\"##".to_vec(),
            b"##\"a\\##(f(x))b\"##".to_vec(),
            b"<!--a--->tail".to_vec(),
            b"\xff\"\xfe".to_vec(),
            b"\t\r\n--- key: 1.2 #comment\n".to_vec(),
            b"a\nb\n".to_vec(),
            b"\"\"\"a\"\"\"\"$foo ${x}".to_vec(),
        ];
        for language in [
            "html", "swift", "kotlin", "yaml", "haskell", "scala", "elixir",
        ] {
            for file in
                std::fs::read_dir(root().join("research/joinery/specimen").join(language)).unwrap()
            {
                let path = file.unwrap().path();
                if path
                    .with_extension(format!(
                        "{}.expect",
                        path.extension().unwrap().to_str().unwrap()
                    ))
                    .exists()
                {
                    subjects.push(std::fs::read(path).unwrap());
                }
            }
        }
        let mut compared = 0;
        let mut matching = 0;
        for (name, pattern, whole) in patterns() {
            let ours = Probe::compile(&pattern, whole).unwrap();
            let body = if whole {
                format!("(?:{pattern})$")
            } else {
                pattern
            };
            let pattern = format!("\\G(?:{body})");
            let oracle = pcre2::bytes::RegexBuilder::new()
                .utf(false)
                .ucp(false)
                .jit(false)
                .build(&pattern)
                .unwrap_or_else(|e| panic!("{name}: {e}"));
            let mut locations = oracle.capture_locations();
            for source in &subjects {
                for at in 0..=source.len() {
                    let ours = ours.capture(source, at, &mut 1_000_000).unwrap();
                    let theirs = oracle
                        .captures_read_at(&mut locations, source, at)
                        .unwrap()
                        .map(|_| Captures {
                            slots: (0..oracle.captures_len())
                                .map(|i| locations.get(i).map(|(a, b)| a..b))
                                .collect(),
                        });
                    matching += usize::from(ours.is_some());
                    assert_eq!(ours, theirs, "{name}: offset {at}, bytes {source:?}");
                    compared += 1;
                }
            }
        }
        eprintln!(
            "scanner probe captures compared against PCRE2: {compared} ({matching} successful matches)"
        );
        assert!(compared > 25_000);
        assert!(matching > 1_000);
    }
}

#[cfg(test)]
mod limits_and_threads {
    use super::*;

    #[test]
    fn finite_policy_rejects_native_narrowing_and_preserves_zero_budgets() {
        for limits in [
            ProbeLimits {
                match_steps: u64::MAX,
                ..ProbeLimits::default()
            },
            ProbeLimits {
                depth: u64::from(u32::MAX) + 1,
                ..ProbeLimits::default()
            },
            ProbeLimits {
                heap_bytes: u64::MAX,
                ..ProbeLimits::default()
            },
            ProbeLimits {
                heap_bytes: 1025,
                ..ProbeLimits::default()
            },
        ] {
            assert!(matches!(
                limits.validate(),
                Err(ScannerError::InvalidLimits(_))
            ));
        }
        for limits in [
            ProbeLimits {
                match_steps: 0,
                ..ProbeLimits::default()
            },
            ProbeLimits {
                depth: 0,
                ..ProbeLimits::default()
            },
            ProbeLimits {
                heap_bytes: 0,
                ..ProbeLimits::default()
            },
        ] {
            let probe = Probe::compile_with_limits("(a+)+$", false, limits).unwrap();
            assert!(matches!(
                probe.capture(b"aaaa", 0, &mut 100),
                Err(ScannerError::Limit("probe matching"))
            ));
        }
    }

    #[test]
    fn authored_linear_bodies_fit_documented_defaults_and_refuse_under_small_caps() {
        let cases = [
            (
                include_str!("../../../customary/html.json"),
                "script_body",
                format!("{}</script>", "x".repeat(2_000)),
                2_000,
            ),
            (
                include_str!("../../../customary/elixir.json"),
                "i_heredoc_double",
                format!("{}\n  \"\"\"", "x".repeat(10_000)),
                10_003,
            ),
        ];
        for (book, name, source, extent) in cases {
            let book: serde_json::Value = serde_json::from_str(book).unwrap();
            let pattern = book["probes"][name].as_str().unwrap();
            let old = Probe::compile_with_limits(
                pattern,
                false,
                ProbeLimits {
                    match_steps: 100_000,
                    depth: 1_000,
                    heap_bytes: 1 << 20,
                },
            )
            .unwrap();
            assert!(
                matches!(
                    old.capture(source.as_bytes(), 0, &mut 100),
                    Err(ScannerError::Limit("probe matching"))
                ),
                "{name}"
            );
            let probe = Probe::compile(pattern, false).unwrap();
            let captures = probe
                .capture(source.as_bytes(), 0, &mut 100)
                .unwrap()
                .unwrap();
            assert_eq!(captures.width(), extent, "{name}");
        }
    }

    #[test]
    fn capture_resource_refusal_is_distinct_from_no_match() {
        let probe = Probe::compile(r"(a+)+$", false).unwrap();
        assert!(matches!(
            probe.capture(b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!", 0, &mut 100),
            Err(ScannerError::Limit("probe matching"))
        ));
        assert_eq!(
            Probe::compile("x", false)
                .unwrap()
                .capture(b"a", 0, &mut 100)
                .unwrap(),
            None
        );
        assert!(matches!(
            Probe::compile("x", false).unwrap().capture(b"x", 0, &mut 0),
            Err(ScannerError::Limit("program work"))
        ));
    }
    #[test]
    fn immutable_probe_keeps_thread_capture_scratch_independent() {
        let probe = std::sync::Arc::new(Probe::compile(r"(?<=!)([A-Za-z]+)-\1", false).unwrap());
        std::thread::scope(|scope| {
            for word in ["alpha", "beta", "gamma", "delta"] {
                let probe = std::sync::Arc::clone(&probe);
                scope.spawn(move || {
                    let source = format!("!{word}-{word}").into_bytes();
                    for _ in 0..100 {
                        let caps = probe.capture(&source, 1, &mut 100).unwrap().unwrap();
                        assert_eq!(caps.group(&source, 1), word.as_bytes());
                        assert_eq!(caps.slots[0], Some(1..source.len()));
                    }
                });
            }
        });
    }
}
