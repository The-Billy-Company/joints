/*
 * The corpus program: a ledger that caches its own total.
 * push invalidates the cache, total rebuilds it and holds it until the
 * next push, and every file in this folder tells that same story.
 */
use std::collections::HashMap;

// A raw string, where the hash run in the opener is what the closer has to
// match - so the token's own delimiter is not a fixed pattern.
const BANNER: &str = r#"ledger receipt
--------------
"#;

#[derive(Debug, Clone)]
pub struct Ledger {
    rows: Vec<i64>,
    tags: HashMap<String, usize>,
    total: Option<i64>,
}

impl Ledger {
    pub fn new() -> Self {
        Ledger { rows: Vec::new(), tags: HashMap::new(), total: None }
    }

    pub fn push(&mut self, tag: &str, v: i64) -> usize {
        let at = self.rows.len();
        self.rows.push(v);
        self.tags.insert(tag.to_string(), at);
        self.total = None;
        at
    }

    pub fn total(&mut self) -> i64 {
        if let Some(t) = self.total {
            return t;
        }
        let t = self.rows.iter().filter(|&&r| r > 0).sum();
        self.total = Some(t);
        t
    }
}

fn main() {
    let mut l = Ledger::new();
    for (i, arg) in std::env::args().skip(1).enumerate() {
        match arg.parse::<i64>() {
            Ok(v) => { l.push(&format!("arg{i}"), v); }
            Err(e) => eprintln!("skipping {arg}: {e}"),
        }
    }
    print!("{BANNER}");
    println!("total={}", l.total());
}
