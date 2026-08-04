use std::collections::HashMap;

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
    println!("total={}", l.total());
}
