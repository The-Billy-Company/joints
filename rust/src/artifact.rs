//! Owned, checked compiled data. Loading native tables never constructs LR states.
//!
//! Version three uses explicit little-endian values, canonical sorted maps and a
//! SHA-256 seal over the header and payload. A seal detects corruption; it does
//! not authenticate an untrusted author. No native struct is viewed as bytes.

use crate::{
    CompileOptions, CompiledGrammar, Error, compiler::Automaton, lexer::Lexer,
    scanner::ScannerProgram,
};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs::File,
    io::Read,
    ops::Range,
    path::Path,
    sync::{Arc, Mutex},
};

mod image;
pub(crate) use image::{ImageOperation, ImageSession};

const GRAMMAR_MAGIC: &[u8; 8] = b"JNTRART\0";
const BANK_MAGIC: &[u8; 8] = b"JNTRBNK\0";
const VERSION: u32 = 3;
// Revision four adds native lexer images to the checked lexical recipe.
const SCHEMA: u32 = 4;
const HEADER: usize = 24;
const SEAL: usize = 32;

/// Native-table decode budgets; artifact-supplied counts never raise them.
/// `bytes` and `languages` also govern JSON dispatch. JSON construction uses
/// [`CompileOptions::default`], with its separate finite construction budgets;
/// use `CompiledGrammar::compile_with_options` to choose a different JSON policy.
/// Matching ceilings stored in a native artifact are retained, not replaced by
/// these decode budgets. Workers still supply their own `ParseLimits`.
/// Envelope SHA verification retains its existing `bytes` ruler. Shared `work`
/// covers accepted Reader, recipe and native-image work; it is not a CPU meter
/// for envelope hashing, scanner binding, or later worker pool growth.
#[derive(Clone, Copy, Debug)]
pub struct ArtifactLimits {
    pub bytes: usize,
    pub languages: usize,
    pub symbols: usize,
    pub productions: usize,
    pub steps: usize,
    pub states: usize,
    pub items: usize,
    pub table_entries: usize,
    pub actions: usize,
    pub text_bytes: usize,
    pub work: usize,
    /// Aggregate image shape and live-storage ceilings for one operation.
    pub images: irgx::ImageLimits,
    /// Cumulative new image/recipe/output allocation requests; never refunded.
    pub image_allocation: u64,
}
impl Default for ArtifactLimits {
    fn default() -> Self {
        Self {
            bytes: 512 << 20,
            languages: 256,
            symbols: 4096,
            productions: 16384,
            steps: 262144,
            states: 131072,
            items: 10_000_000,
            table_entries: 16_000_000,
            actions: 16_000_000,
            text_bytes: 16 << 20,
            work: 128_000_000,
            images: irgx::ImageLimits::default(),
            image_allocation: 256 << 20,
        }
    }
}
#[derive(Debug, thiserror::Error)]
pub enum ArtifactError {
    #[error("artifact exceeds {resource} limit {limit}")]
    Limit {
        resource: &'static str,
        limit: usize,
    },
    #[error("truncated native artifact")]
    Truncated,
    #[error("unrecognized artifact format; expected native artifact, bank, or grammar JSON")]
    Format,
    #[error(
        "legacy Zig {format} is incompatible; re-mint from the original grammar JSON with the native mint command"
    )]
    LegacyFormat { format: &'static str },
    #[error("unsupported native artifact version {found}; re-mint with this runtime")]
    Version { found: u32 },
    #[error("native artifact schema or scanner books differ; re-mint with this runtime")]
    Schema,
    #[error("native artifact length or trailing bytes disagree with its header")]
    Length,
    #[error("native artifact SHA-256 seal does not match")]
    Seal,
    #[error("invalid native artifact: {0}")]
    Invalid(&'static str),
    #[error("native artifact allocation failed: {0}")]
    Allocation(&'static str),
    #[error(transparent)]
    Image(#[from] irgx::ImageError),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Grammar(#[from] Error),
}

pub(crate) struct Writer {
    pub(crate) bytes: Vec<u8>,
}
impl Writer {
    pub(crate) fn new() -> Self {
        Self { bytes: Vec::new() }
    }
    pub(crate) fn tag(&mut self, n: u8) {
        self.bytes.push(n);
    }
    pub(crate) fn flag(&mut self, n: bool) {
        self.tag(u8::from(n));
    }
    pub(crate) fn number(&mut self, n: usize) -> Result<(), ArtifactError> {
        self.bytes.extend(
            u32::try_from(n)
                .map_err(|_| ArtifactError::Invalid("value exceeds u32"))?
                .to_le_bytes(),
        );
        Ok(())
    }
    pub(crate) fn signed(&mut self, n: i32) {
        self.bytes.extend(n.to_le_bytes());
    }
    pub(crate) fn wide(&mut self, n: u64) {
        self.bytes.extend(n.to_le_bytes());
    }
    pub(crate) fn raw(&mut self, b: &[u8]) {
        self.bytes.extend_from_slice(b);
    }
    pub(crate) fn blob(&mut self, b: &[u8]) -> Result<(), ArtifactError> {
        self.number(b.len())?;
        self.raw(b);
        Ok(())
    }
    pub(crate) fn text(&mut self, s: &str) -> Result<(), ArtifactError> {
        self.blob(s.as_bytes())
    }
    pub(crate) fn optional(&mut self, n: Option<usize>) -> Result<(), ArtifactError> {
        match n {
            Some(n) => {
                self.tag(1);
                self.number(n)?;
            }
            None => self.tag(0),
        };
        Ok(())
    }
    // Charge the complete capacity request, including a preexisting table prefix.
    fn paid_raw(&mut self, bytes: &[u8], op: &mut ImageOperation) -> Result<(), ArtifactError> {
        let needed = self
            .bytes
            .len()
            .checked_add(bytes.len())
            .ok_or(ArtifactError::Length)?;
        if needed > self.bytes.capacity() {
            op.charge_allocation(needed)?;
            // A reserve may relocate the complete old allocation.
            op.charge_work(self.bytes.capacity())?;
            self.bytes
                .try_reserve_exact(needed - self.bytes.len())
                .map_err(|_| ArtifactError::Allocation("image output"))?;
        }
        op.charge_work(bytes.len())?;
        self.bytes.extend_from_slice(bytes);
        Ok(())
    }
    pub(crate) fn image_count(
        &mut self,
        count: usize,
        op: &mut ImageOperation,
    ) -> Result<(), ArtifactError> {
        let count = u32::try_from(count).map_err(|_| ArtifactError::Length)?;
        self.paid_raw(&count.to_le_bytes(), op)
    }
    pub(crate) fn image(
        &mut self,
        bytes: &[u8],
        op: &mut ImageOperation,
    ) -> Result<(), ArtifactError> {
        self.image_count(bytes.len(), op)?;
        self.paid_raw(bytes, op)
    }
}

pub(crate) struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
    pub(crate) limits: ArtifactLimits,
    work: usize,
    image_checkpoint: usize,
    text: usize,
}
impl<'a> Reader<'a> {
    pub(crate) fn new(bytes: &'a [u8], limits: ArtifactLimits) -> Self {
        Self {
            bytes,
            at: 0,
            limits,
            work: 0,
            image_checkpoint: 0,
            text: 0,
        }
    }
    pub(crate) fn charge(&mut self, n: usize) -> Result<(), ArtifactError> {
        let next = self
            .work
            .checked_add(n)
            .ok_or(ArtifactError::Invalid("work overflow"))?;
        if next > self.limits.work {
            return Err(ArtifactError::Limit {
                resource: "decode work",
                limit: self.limits.work,
            });
        }
        self.work = next;
        Ok(())
    }
    pub(crate) fn take(&mut self, n: usize) -> Result<&'a [u8], ArtifactError> {
        self.charge(1)?;
        let end = self.at.checked_add(n).ok_or(ArtifactError::Length)?;
        let result = self
            .bytes
            .get(self.at..end)
            .ok_or(ArtifactError::Truncated)?;
        self.at = end;
        Ok(result)
    }
    pub(crate) fn tag(&mut self) -> Result<u8, ArtifactError> {
        Ok(self.take(1)?[0])
    }
    pub(crate) fn flag(&mut self) -> Result<bool, ArtifactError> {
        match self.tag()? {
            0 => Ok(false),
            1 => Ok(true),
            _ => Err(ArtifactError::Invalid("boolean tag")),
        }
    }
    pub(crate) fn number(&mut self) -> Result<usize, ArtifactError> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().expect("four bytes")) as usize)
    }
    pub(crate) fn signed(&mut self) -> Result<i32, ArtifactError> {
        Ok(i32::from_le_bytes(
            self.take(4)?.try_into().expect("four bytes"),
        ))
    }
    pub(crate) fn wide(&mut self) -> Result<u64, ArtifactError> {
        Ok(u64::from_le_bytes(
            self.take(8)?.try_into().expect("eight bytes"),
        ))
    }
    pub(crate) fn size(&mut self) -> Result<usize, ArtifactError> {
        usize::try_from(self.wide()?).map_err(|_| ArtifactError::Invalid("size exceeds host"))
    }
    pub(crate) fn count(
        &mut self,
        max: usize,
        min_width: usize,
        resource: &'static str,
    ) -> Result<usize, ArtifactError> {
        let n = self.number()?;
        if n > max {
            return Err(ArtifactError::Limit {
                resource,
                limit: max,
            });
        }
        if n > self.remaining() / min_width.max(1) {
            return Err(ArtifactError::Truncated);
        }
        self.charge(n)?;
        Ok(n)
    }
    pub(crate) fn blob(&mut self) -> Result<&'a [u8], ArtifactError> {
        let n = self.number()?;
        self.text = self.text.checked_add(n).ok_or(ArtifactError::Length)?;
        if self.text > self.limits.text_bytes {
            return Err(ArtifactError::Limit {
                resource: "text bytes",
                limit: self.limits.text_bytes,
            });
        }
        self.charge(n)?;
        self.take(n)
    }
    pub(crate) fn text(&mut self) -> Result<String, ArtifactError> {
        String::from_utf8(self.blob()?.to_vec()).map_err(|_| ArtifactError::Invalid("UTF-8 text"))
    }
    pub(crate) fn optional(&mut self) -> Result<Option<usize>, ArtifactError> {
        if self.flag()? {
            Ok(Some(self.number()?))
        } else {
            Ok(None)
        }
    }
    pub(crate) fn remaining(&self) -> usize {
        self.bytes.len() - self.at
    }
    pub(crate) fn finish(&self) -> Result<(), ArtifactError> {
        if self.remaining() == 0 {
            Ok(())
        } else {
            Err(ArtifactError::Length)
        }
    }
}

fn legacy(bytes: &[u8]) -> Result<(), ArtifactError> {
    if bytes.starts_with(b"OTLFOLIO") {
        return Err(ArtifactError::LegacyFormat { format: "folio" });
    }
    if bytes.starts_with(b"OTLCODEX") {
        return Err(ArtifactError::LegacyFormat { format: "codex" });
    }
    Ok(())
}
#[cfg(test)]
fn seal(magic: &[u8; 8], payload: Vec<u8>) -> Vec<u8> {
    let mut out = Vec::with_capacity(HEADER + payload.len() + SEAL);
    out.extend(magic);
    out.extend(VERSION.to_le_bytes());
    out.extend(SCHEMA.to_le_bytes());
    out.extend((payload.len() as u64).to_le_bytes());
    out.extend(payload);
    let digest = Sha256::digest(&out);
    out.extend(digest);
    out
}

// Reuse the payload allocation. Every new whole-capacity request and the full
// in-place move are paid; the old table encoder retains its existing ruler.
fn seal_image(
    magic: &[u8; 8],
    mut payload: Vec<u8>,
    op: &mut ImageOperation,
    image_bytes: u64,
) -> Result<Vec<u8>, ArtifactError> {
    let body = payload.len();
    let length = body
        .checked_add(HEADER + SEAL)
        .ok_or(ArtifactError::Length)?;
    if length > payload.capacity() {
        op.charge_allocation(length)?;
        op.charge_work(payload.capacity())?;
        payload
            .try_reserve_exact(length - body)
            .map_err(|_| ArtifactError::Allocation("artifact envelope"))?;
    }
    op.charge_work(length)?;
    payload.resize(length, 0);
    payload.copy_within(..body, HEADER);
    payload[..8].copy_from_slice(magic);
    payload[8..12].copy_from_slice(&VERSION.to_le_bytes());
    payload[12..16].copy_from_slice(&SCHEMA.to_le_bytes());
    payload[16..24].copy_from_slice(&(body as u64).to_le_bytes());
    // Existing table hashing has its old ruler; the appended image hash visits
    // are additional work in this account.
    op.charge_work(usize::try_from(image_bytes).map_err(|_| ArtifactError::Length)?)?;
    let end = length - SEAL;
    let signet = Sha256::digest(&payload[..end]);
    payload[end..].copy_from_slice(&signet);
    Ok(payload)
}
#[cfg(test)]
thread_local! {
    static ENVELOPE_HASHES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}
fn envelope<'a>(
    bytes: &'a [u8],
    magic: &[u8; 8],
    limits: ArtifactLimits,
) -> Result<&'a [u8], ArtifactError> {
    if bytes.len() > limits.bytes {
        return Err(ArtifactError::Limit {
            resource: "artifact bytes",
            limit: limits.bytes,
        });
    }
    legacy(bytes)?;
    if bytes.len() < HEADER + SEAL {
        return Err(ArtifactError::Truncated);
    }
    if &bytes[..8] != magic {
        return Err(ArtifactError::Format);
    }
    let mut head = Reader::new(&bytes[8..HEADER], limits);
    let found = head.number()? as u32;
    if found != VERSION {
        return Err(ArtifactError::Version { found });
    }
    if head.number()? as u32 != SCHEMA {
        return Err(ArtifactError::Schema);
    }
    let len = head.size()?;
    if len.checked_add(HEADER + SEAL) != Some(bytes.len()) {
        return Err(ArtifactError::Length);
    }
    let end = bytes.len() - SEAL;
    #[cfg(test)]
    ENVELOPE_HASHES.with(|count| count.set(count.get() + 1));
    if Sha256::digest(&bytes[..end]).as_slice() != &bytes[end..] {
        return Err(ArtifactError::Seal);
    }
    Ok(&bytes[HEADER..end])
}
fn scanner_seal() -> [u8; 32] {
    let mut hash = Sha256::new();
    for source in ScannerProgram::artifact_sources() {
        hash.update((source.len() as u64).to_le_bytes());
        hash.update(source.as_bytes());
    }
    hash.finalize().into()
}
fn write_options(w: &mut Writer, o: CompileOptions) {
    for n in [
        o.tables.source_bytes,
        o.tables.symbols,
        o.tables.productions,
        o.tables.production_steps,
        o.tables.alternatives,
        o.tables.states,
        o.tables.items,
        o.tables.work,
        o.lexer.pattern_bytes,
        o.lexer.scan_transitions,
    ] {
        w.wide(n as u64);
    }
    for n in [o.probes.match_steps, o.probes.depth, o.probes.heap_bytes] {
        w.wide(n);
    }
}
fn read_options(r: &mut Reader<'_>) -> Result<CompileOptions, ArtifactError> {
    let mut o = CompileOptions::default();
    o.tables.source_bytes = r.size()?;
    o.tables.symbols = r.size()?;
    o.tables.productions = r.size()?;
    o.tables.production_steps = r.size()?;
    o.tables.alternatives = r.size()?;
    o.tables.states = r.size()?;
    o.tables.items = r.size()?;
    o.tables.work = r.size()?;
    o.lexer.pattern_bytes = r.size()?;
    o.lexer.scan_transitions = r.size()?;
    o.probes.match_steps = r.wide()?;
    o.probes.depth = r.wide()?;
    o.probes.heap_bytes = r.wide()?;
    Ok(o)
}
impl CompiledGrammar {
    /// Persist checked compiled tables, metadata and matching ceilings.
    pub fn artifact(&self) -> Result<Vec<u8>, ArtifactError> {
        self.artifact_in(&mut ImageOperation::new(ArtifactLimits::default()))
    }
    fn artifact_in(&self, op: &mut ImageOperation) -> Result<Vec<u8>, ArtifactError> {
        let initial_images = op.image_bytes();
        let mut w = Writer::new();
        w.text(self.name())?;
        w.raw(&scanner_seal());
        write_options(&mut w, self.options);
        w.flag(self.customary.is_some());
        if let Some(source) = &self.customary {
            w.blob(source)?;
        }
        self.automaton.write_artifact(&mut w)?;
        self.lexer.write_images(&mut w, op)?;
        let image_bytes = op
            .image_bytes()
            .checked_sub(initial_images)
            .ok_or(ArtifactError::Length)?;
        seal_image(GRAMMAR_MAGIC, w.bytes, op, image_bytes)
    }
    pub fn from_artifact(bytes: &[u8]) -> Result<Arc<Self>, ArtifactError> {
        Self::from_artifact_with_limits(bytes, ArtifactLimits::default())
    }
    /// Decode owned tables without rerunning grammar normalization or LR construction.
    pub fn from_artifact_with_limits(
        bytes: &[u8],
        limits: ArtifactLimits,
    ) -> Result<Arc<Self>, ArtifactError> {
        let payload = VerifiedPayload::check(bytes, 0..bytes.len(), limits)?;
        Self::from_verified_payload(&payload, limits, &mut ImageOperation::new(limits))
    }
    // The capability is private and can only be created by envelope verification
    // or an immutable copy of an already verified payload. All table, scanner,
    // regex, title and resource validation remains in this decoder.
    fn from_verified_payload<B: AsRef<[u8]>>(
        payload: &VerifiedPayload<B>,
        limits: ArtifactLimits,
        op: &mut ImageOperation,
    ) -> Result<Arc<Self>, ArtifactError> {
        let mut r = Reader::new(payload.payload(), op.reader_limits(limits));
        let result = (|| {
            let name = r.text()?;
            if r.take(32)? != scanner_seal() {
                return Err(ArtifactError::Schema);
            }
            let options = read_options(&mut r)?;
            let customary = if r.flag()? {
                let source = r.blob()?;
                if source.len() > 1024 * 1024 {
                    return Err(ArtifactError::Limit {
                        resource: "customary bytes",
                        limit: 1024 * 1024,
                    });
                }
                Some(Arc::from(source))
            } else {
                None
            };
            let automaton = Arc::new(Automaton::read_artifact(name, &mut r)?);
            let program = ScannerProgram::bind_with_customary(
                &automaton,
                customary.as_deref(),
                options.probes,
            )
            .map_err(Error::from)?
            .map(Arc::new);
            let lexer = Lexer::load_with_program(
                &automaton,
                program.as_deref(),
                options.lexer,
                &mut ImageSession::new(&mut r, op)?,
            )?;
            r.finish()?;
            Ok(Arc::new(Self {
                automaton,
                lexer,
                program,
                options,
                customary,
            }))
        })();
        op.settle(&mut r)?;
        result
    }
}

// A proof about precisely these immutable bytes, never an unchecked range or
// caller-owned mutable storage. Borrowed direct loads avoid an ownership copy.
struct VerifiedPayload<B> {
    bytes: B,
    body: Range<usize>,
}
impl<B: AsRef<[u8]>> VerifiedPayload<B> {
    fn check(bytes: B, range: Range<usize>, limits: ArtifactLimits) -> Result<Self, ArtifactError> {
        envelope(
            bytes
                .as_ref()
                .get(range.clone())
                .ok_or(ArtifactError::Length)?,
            GRAMMAR_MAGIC,
            limits,
        )?;
        // A successful envelope check proves these additions/subtractions stay
        // within the checked range and its underlying immutable byte slice.
        Ok(Self {
            bytes,
            body: range.start + HEADER..range.end - SEAL,
        })
    }
    fn payload(&self) -> &[u8] {
        &self.bytes.as_ref()[self.body.clone()]
    }
}
impl VerifiedPayload<&[u8]> {
    fn into_owned(self) -> VerifiedPayload<Arc<[u8]>> {
        let bytes: Arc<[u8]> = Arc::from(self.payload());
        let end = bytes.len();
        VerifiedPayload {
            bytes,
            body: 0..end,
        }
    }
}

enum Member {
    Ready(Arc<CompiledGrammar>),
    Native(Mutex<NativeMember>),
}
enum NativeMember {
    Pending(VerifiedPayload<Arc<[u8]>>),
    Ready(Arc<CompiledGrammar>),
}
/// A checked language directory. Members are decoded and validated when selected,
/// then cached. Selected grammars own their tables independently of the bank.
pub struct Bank {
    members: BTreeMap<String, Member>,
    limits: ArtifactLimits,
}
impl Bank {
    /// Envelope version written and accepted by this runtime.
    pub const FORMAT_VERSION: u32 = VERSION;

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, ArtifactError> {
        Self::from_bytes_with_limits(bytes, ArtifactLimits::default())
    }
    pub fn from_bytes_with_limits(
        bytes: &[u8],
        limits: ArtifactLimits,
    ) -> Result<Self, ArtifactError> {
        if bytes.len() > limits.bytes {
            return Err(ArtifactError::Limit {
                resource: "artifact bytes",
                limit: limits.bytes,
            });
        }
        legacy(bytes)?;
        if limits.languages == 0 {
            return Err(ArtifactError::Limit {
                resource: "languages",
                limit: 0,
            });
        }
        if bytes.iter().find(|b| !b.is_ascii_whitespace()) == Some(&b'{') {
            let grammar = CompiledGrammar::compile(bytes)?;
            let mut members = BTreeMap::new();
            members.insert(grammar.name().to_owned(), Member::Ready(grammar));
            return Ok(Self { members, limits });
        }
        if bytes.starts_with(GRAMMAR_MAGIC) {
            let payload = VerifiedPayload::check(bytes, 0..bytes.len(), limits)?;
            let mut r = Reader::new(payload.payload(), limits);
            let title = r.text()?;
            let mut members = BTreeMap::new();
            members.insert(
                title,
                Member::Native(Mutex::new(NativeMember::Pending(payload.into_owned()))),
            );
            return Ok(Self { members, limits });
        }
        let payload = envelope(bytes, BANK_MAGIC, limits)?;
        let mut r = Reader::new(payload, limits);
        let n = r.count(limits.languages, 20, "languages")?;
        if n == 0 {
            return Err(ArtifactError::Invalid("empty bank"));
        }
        let mut directory = Vec::with_capacity(n);
        let mut previous = None;
        for _ in 0..n {
            let title = r.text()?;
            if previous.as_ref().is_some_and(|p: &String| p >= &title) {
                return Err(ArtifactError::Invalid("duplicate or unordered language"));
            }
            previous = Some(title.clone());
            directory.push((title, r.size()?, r.size()?));
        }
        let arena_at = payload.len() - r.remaining();
        let arena = &payload[arena_at..];
        let mut next = 0;
        let owned: Arc<[u8]> = Arc::from(bytes);
        let mut members = BTreeMap::new();
        for (title, off, len) in directory {
            if off != next {
                return Err(ArtifactError::Invalid("member offset"));
            }
            let end = off.checked_add(len).ok_or(ArtifactError::Length)?;
            // Validate the owned member itself, tying the proof to the exact
            // immutable Arc later decoded by get().
            arena.get(off..end).ok_or(ArtifactError::Length)?;
            let member = VerifiedPayload::check(
                Arc::clone(&owned),
                HEADER + arena_at + off..HEADER + arena_at + end,
                limits,
            )?;
            let mut check = Reader::new(member.payload(), limits);
            if check.text()? != title {
                return Err(ArtifactError::Invalid(
                    "directory title differs from member",
                ));
            }
            members.insert(
                title,
                Member::Native(Mutex::new(NativeMember::Pending(member))),
            );
            next = end;
        }
        if next != arena.len() {
            return Err(ArtifactError::Length);
        }
        Ok(Self { members, limits })
    }
    pub fn open(path: impl AsRef<Path>) -> Result<Self, ArtifactError> {
        Self::open_with_limits(path, ArtifactLimits::default())
    }
    pub fn open_with_limits(
        path: impl AsRef<Path>,
        limits: ArtifactLimits,
    ) -> Result<Self, ArtifactError> {
        let file = File::open(path)?;
        if file.metadata()?.len() > limits.bytes as u64 {
            return Err(ArtifactError::Limit {
                resource: "artifact bytes",
                limit: limits.bytes,
            });
        }
        let mut bytes = Vec::new();
        file.take((limits.bytes as u64).saturating_add(1))
            .read_to_end(&mut bytes)?;
        Self::from_bytes_with_limits(&bytes, limits)
    }
    pub fn languages(&self) -> impl ExactSizeIterator<Item = &str> {
        self.members.keys().map(String::as_str)
    }
    pub fn get(&self, name: &str) -> Result<Option<Arc<CompiledGrammar>>, ArtifactError> {
        let Some(member) = self.members.get(name) else {
            return Ok(None);
        };
        let cache = match member {
            Member::Ready(grammar) => return Ok(Some(Arc::clone(grammar))),
            Member::Native(cache) => cache,
        };
        let mut slot = cache
            .lock()
            .map_err(|_| ArtifactError::Invalid("member cache poisoned"))?;
        let grammar = match &*slot {
            NativeMember::Ready(grammar) => return Ok(Some(Arc::clone(grammar))),
            NativeMember::Pending(payload) => CompiledGrammar::from_verified_payload(
                payload,
                self.limits,
                &mut ImageOperation::new(self.limits),
            )?,
        };
        // Decode borrows the checked bytes without taking them out of Pending.
        // Every failure therefore keeps the original proof for another try;
        // only a complete owned grammar replaces and releases that payload.
        *slot = NativeMember::Ready(Arc::clone(&grammar));
        Ok(Some(grammar))
    }
    /// Canonical byte output, independent of caller language order.
    pub fn pack(grammars: &[Arc<CompiledGrammar>]) -> Result<Vec<u8>, ArtifactError> {
        if grammars.is_empty() {
            return Err(ArtifactError::Invalid("empty bank"));
        }
        let mut members = BTreeMap::new();
        let mut op = ImageOperation::new(ArtifactLimits::default());
        for grammar in grammars {
            if members
                .insert(grammar.name(), grammar.artifact_in(&mut op)?)
                .is_some()
            {
                return Err(ArtifactError::Invalid("duplicate language"));
            }
        }
        pack_members(
            &members
                .iter()
                .map(|(&name, bytes)| (name, bytes.as_slice()))
                .collect::<Vec<_>>(),
            &mut op,
        )
    }
    /// Validate and pack members one grammar at a time. This permits a minter
    /// to release each expensive compiled graph before compiling the next one.
    pub fn pack_artifacts(parts: &[&[u8]]) -> Result<Vec<u8>, ArtifactError> {
        let mut members = BTreeMap::new();
        let limits = ArtifactLimits::default();
        let mut op = ImageOperation::new(limits);
        for &bytes in parts {
            let payload = VerifiedPayload::check(bytes, 0..bytes.len(), limits)?;
            let grammar = CompiledGrammar::from_verified_payload(&payload, limits, &mut op)?;
            if members.insert(grammar.name().to_owned(), bytes).is_some() {
                return Err(ArtifactError::Invalid("duplicate language"));
            }
        }
        pack_members(
            &members
                .iter()
                .map(|(name, &bytes)| (name.as_str(), bytes))
                .collect::<Vec<_>>(),
            &mut op,
        )
    }
}

fn pack_members(
    members: &[(&str, &[u8])],
    op: &mut ImageOperation,
) -> Result<Vec<u8>, ArtifactError> {
    if members.is_empty() {
        return Err(ArtifactError::Invalid("empty bank"));
    }
    let mut w = Writer::new();
    w.number(members.len())?;
    let mut off = 0usize;
    for &(name, bytes) in members {
        w.text(name)?;
        w.wide(off as u64);
        w.wide(bytes.len() as u64);
        off = off.checked_add(bytes.len()).ok_or(ArtifactError::Length)?;
    }
    for &(_, bytes) in members {
        w.paid_raw(bytes, op)?;
    }
    let image_bytes = op.image_bytes();
    seal_image(BANK_MAGIC, w.bytes, op, image_bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{CompileOptions, Node, ProbeLimits, TreeSnapshot};
    fn json() -> Arc<CompiledGrammar> {
        CompiledGrammar::compile(include_bytes!("../../test/grammar/json.json")).unwrap()
    }
    fn view(tree: &TreeSnapshot) -> serde_json::Value {
        fn node(n: Node<'_>) -> serde_json::Value {
            serde_json::json!([
                n.name(),
                n.is_named(),
                n.is_extra(),
                n.field(),
                n.span().start(),
                n.span().end(),
                n.children().map(node).collect::<Vec<_>>()
            ])
        }
        serde_json::json!([
            format!("{:?}", tree.stop()),
            tree.roots().map(node).collect::<Vec<_>>()
        ])
    }
    fn parity(a: &Arc<CompiledGrammar>, b: &Arc<CompiledGrammar>, source: &[u8]) {
        let mut sa = a.session();
        let mut sb = b.session();
        let ta = sa.parse_partial(source).unwrap();
        let tb = sb.parse_partial(source).unwrap();
        assert_eq!(view(&ta), view(&tb));
        let mut ea = a.effect_store();
        let mut eb = b.effect_store();
        let pa = sa.product(&mut ea).unwrap();
        let pb = sb.product(&mut eb).unwrap();
        assert_eq!(ea.describe(pa).unwrap(), eb.describe(pb).unwrap());
    }
    fn pending_bytes(bank: &Bank, name: &str) -> std::sync::Weak<[u8]> {
        let Member::Native(cache) = &bank.members[name] else {
            panic!("expected a native member");
        };
        let slot = cache.lock().unwrap();
        let NativeMember::Pending(payload) = &*slot else {
            panic!("expected a pending native proof");
        };
        Arc::downgrade(&payload.bytes)
    }
    fn two_tiers() -> Arc<CompiledGrammar> {
        let source = serde_json::json!({"name":"two_tiers","rules":{
            "source_file":{"type":"SEQ","members":[{"type":"SYMBOL","name":"high"},{"type":"SYMBOL","name":"low"}]},
            "high":{"type":"TOKEN","content":{"type":"PREC","value":2,"content":{"type":"PATTERN","value":"a+"}}},
            "low":{"type":"TOKEN","content":{"type":"PREC","value":-2,"content":{"type":"PATTERN","value":"b+"}}}
        }});
        CompiledGrammar::compile(&serde_json::to_vec(&source).unwrap()).unwrap()
    }
    fn image_tail(body: &[u8]) -> usize {
        let mut reader = Reader::new(body, ArtifactLimits::default());
        let name = reader.text().unwrap();
        reader.take(32).unwrap();
        read_options(&mut reader).unwrap();
        if reader.flag().unwrap() {
            reader.blob().unwrap();
        }
        Automaton::read_artifact(name, &mut reader).unwrap();
        reader.at
    }
    fn account_load(
        bytes: &[u8],
        limits: ArtifactLimits,
        op: &mut ImageOperation,
    ) -> Result<Arc<CompiledGrammar>, ArtifactError> {
        let payload = VerifiedPayload::check(bytes, 0..bytes.len(), limits)?;
        CompiledGrammar::from_verified_payload(&payload, limits, op)
    }
    fn measured_load(bytes: &[u8]) -> (u64, u64) {
        let limits = ArtifactLimits::default();
        let mut op = ImageOperation::new(limits);
        let before = op.remaining();
        account_load(bytes, limits, &mut op).unwrap();
        let after = op.remaining();
        (before.0 - after.0, before.1 - after.1)
    }
    #[test]
    fn image_artifacts_preserve_two_tiers_and_canonical_trees() {
        let source = two_tiers();
        assert!(
            source
                .session()
                .parse(b"aabb")
                .unwrap()
                .confidence()
                .is_strict()
        );
        let bytes = source.artifact().unwrap();
        let body = envelope(&bytes, GRAMMAR_MAGIC, ArtifactLimits::default()).unwrap();
        let tail = image_tail(body);
        assert_eq!(
            u32::from_le_bytes(body[tail..tail + 4].try_into().unwrap()),
            2
        );
        let loaded = CompiledGrammar::from_artifact(&bytes).unwrap();
        assert_eq!(loaded.artifact().unwrap(), bytes);
        parity(&source, &loaded, b"aabb");
        parity(&source, &loaded, b"aaXbb");
        parity(&source, &loaded, b"a");
    }
    #[test]
    fn image_load_exact_and_one_short_operation_budgets() {
        let bytes = two_tiers().artifact().unwrap();
        let (allocation, work) = measured_load(&bytes);
        assert!(allocation > 1 && work > 1);
        let exact = ArtifactLimits {
            work: work as usize,
            image_allocation: allocation,
            ..ArtifactLimits::default()
        };
        let mut op = ImageOperation::new(exact);
        account_load(&bytes, exact, &mut op).unwrap();
        assert_eq!(op.remaining(), (0, 0));
        for limits in [
            ArtifactLimits {
                work: work as usize - 1,
                ..exact
            },
            ArtifactLimits {
                image_allocation: allocation - 1,
                ..exact
            },
        ] {
            let mut op = ImageOperation::new(limits);
            assert!(account_load(&bytes, limits, &mut op).is_err());
            assert!(
                op.remaining().0 <= limits.image_allocation
                    && op.remaining().1 <= limits.work as u64
            );
        }
    }
    #[test]
    fn image_load_member_budgets_survive_drops_without_refunds() {
        let bytes = two_tiers().artifact().unwrap();
        let (allocation, work) = measured_load(&bytes);
        let exact = ArtifactLimits {
            work: 2 * work as usize,
            image_allocation: 2 * allocation,
            ..ArtifactLimits::default()
        };
        let mut op = ImageOperation::new(exact);
        account_load(&bytes, exact, &mut op).unwrap();
        account_load(&bytes, exact, &mut op).unwrap();
        assert_eq!(op.remaining(), (0, 0));
        for retain in [false, true] {
            for limits in [
                ArtifactLimits {
                    work: exact.work - 1,
                    ..exact
                },
                ArtifactLimits {
                    image_allocation: exact.image_allocation - 1,
                    ..exact
                },
            ] {
                let mut op = ImageOperation::new(limits);
                let first = account_load(&bytes, limits, &mut op).unwrap();
                let before = op.remaining();
                let retained = if retain {
                    Some(first)
                } else {
                    drop(first);
                    None
                };
                assert_eq!(before, op.remaining());
                assert!(account_load(&bytes, limits, &mut op).is_err());
                assert!(op.remaining().0 <= before.0 && op.remaining().1 <= before.1);
                assert_eq!(retained.is_some(), retain);
            }
        }
    }
    #[test]
    fn image_output_budgets_cover_all_tiers_copies_and_prior_members() {
        let grammar = two_tiers();
        let limits = ArtifactLimits::default();
        let mut measured = ImageOperation::new(limits);
        let initial = measured.remaining();
        let expected = grammar.artifact_in(&mut measured).unwrap();
        let left = measured.remaining();
        let allocation = initial.0 - left.0;
        let work = initial.1 - left.1;
        let exact = ArtifactLimits {
            image_allocation: allocation,
            work: work as usize,
            ..limits
        };
        let mut op = ImageOperation::new(exact);
        assert_eq!(grammar.artifact_in(&mut op).unwrap(), expected);
        assert_eq!(op.remaining(), (0, 0));
        for limits in [
            ArtifactLimits {
                image_allocation: allocation - 1,
                ..exact
            },
            ArtifactLimits {
                work: work as usize - 1,
                ..exact
            },
        ] {
            let mut op = ImageOperation::new(limits);
            assert!(grammar.artifact_in(&mut op).is_err());
        }
        for retain in [false, true] {
            let limits = ArtifactLimits {
                image_allocation: 2 * allocation - 1,
                work: 2 * work as usize,
                ..limits
            };
            let mut op = ImageOperation::new(limits);
            let first = grammar.artifact_in(&mut op).unwrap();
            let before = op.remaining();
            let retained = if retain {
                Some(first)
            } else {
                drop(first);
                None
            };
            assert_eq!(op.remaining(), before);
            assert!(grammar.artifact_in(&mut op).is_err());
            assert_eq!(retained.is_some(), retain);
        }
    }
    #[test]
    fn image_shape_caps_are_aggregate_across_tiers_and_dropped_members() {
        let grammar = two_tiers();
        let bytes = grammar.artifact().unwrap();
        let one = ArtifactLimits {
            images: irgx::ImageLimits {
                patterns: 1,
                ..irgx::ImageLimits::default()
            },
            ..ArtifactLimits::default()
        };
        let mut op = ImageOperation::new(one);
        assert!(matches!(
            account_load(&bytes, one, &mut op),
            Err(ArtifactError::Image(irgx::ImageError::Oversized))
        ));
        assert!(op.remaining().0 > 0 && op.remaining().1 > 0);
        let mut output = ImageOperation::new(one);
        assert!(matches!(
            grammar.artifact_in(&mut output),
            Err(ArtifactError::Image(irgx::ImageError::Oversized))
        ));
        let three = ArtifactLimits {
            images: irgx::ImageLimits {
                patterns: 3,
                ..irgx::ImageLimits::default()
            },
            ..ArtifactLimits::default()
        };
        let mut op = ImageOperation::new(three);
        drop(account_load(&bytes, three, &mut op).unwrap());
        assert!(matches!(
            account_load(&bytes, three, &mut op),
            Err(ArtifactError::Image(irgx::ImageError::Oversized))
        ));
        assert!(op.remaining().0 > 0 && op.remaining().1 > 0);
    }
    #[test]
    fn image_load_refuses_corrupt_frames_wrong_rosters_and_tier_counts() {
        let bytes = two_tiers().artifact().unwrap();
        let body = envelope(&bytes, GRAMMAR_MAGIC, ArtifactLimits::default()).unwrap();
        let tail = image_tail(body);
        let first_len = u32::from_le_bytes(body[tail + 4..tail + 8].try_into().unwrap()) as usize;
        let second_at = tail + 8 + first_len;
        let second_len =
            u32::from_le_bytes(body[second_at..second_at + 4].try_into().unwrap()) as usize;
        let second = &body[second_at + 4..second_at + 4 + second_len];
        let mut corrupt = body.to_vec();
        corrupt[tail + 8 + first_len - 1] ^= 1;
        let corrupt = seal(GRAMMAR_MAGIC, corrupt);
        assert!(matches!(
            CompiledGrammar::from_artifact(&corrupt),
            Err(ArtifactError::Image(irgx::ImageError::Corrupt))
        ));
        let mut wrong = Writer::new();
        wrong.raw(&body[..tail + 4]);
        wrong.blob(second).unwrap();
        wrong.blob(second).unwrap();
        assert!(matches!(
            CompiledGrammar::from_artifact(&seal(GRAMMAR_MAGIC, wrong.bytes)),
            Err(ArtifactError::Image(irgx::ImageError::GenerationMismatch))
        ));
        let mut missing = body.to_vec();
        missing[tail..tail + 4].copy_from_slice(&0u32.to_le_bytes());
        assert!(matches!(
            CompiledGrammar::from_artifact(&seal(GRAMMAR_MAGIC, missing)),
            Err(ArtifactError::Invalid("lexer image tier count"))
        ));
        let bank = Bank::from_bytes(&corrupt).unwrap();
        for _ in 0..2 {
            assert!(matches!(
                bank.get("two_tiers"),
                Err(ArtifactError::Image(irgx::ImageError::Corrupt))
            ));
        }
        match &bank.members["two_tiers"] {
            Member::Native(cache) => {
                assert!(matches!(&*cache.lock().unwrap(), NativeMember::Pending(_)))
            }
            Member::Ready(_) => panic!("corrupt image was cached"),
        }
    }
    #[test]
    fn image_tail_failure_keeps_spent_work_and_old_versions_require_remint() {
        let bytes = two_tiers().artifact().unwrap();
        let body = envelope(&bytes, GRAMMAR_MAGIC, ArtifactLimits::default()).unwrap();
        let mut trailing = body.to_vec();
        trailing.push(0);
        let trailing = seal(GRAMMAR_MAGIC, trailing);
        let limits = ArtifactLimits::default();
        let mut op = ImageOperation::new(limits);
        let before = op.remaining();
        assert!(matches!(
            account_load(&trailing, limits, &mut op),
            Err(ArtifactError::Length)
        ));
        let after = op.remaining();
        let spent = measured_load(&bytes);
        assert_eq!((before.0 - after.0, before.1 - after.1), spent);
        let mut old = bytes;
        old[8..12].copy_from_slice(&2u32.to_le_bytes());
        old[12..16].copy_from_slice(&3u32.to_le_bytes());
        let seal_at = old.len() - SEAL;
        let digest = Sha256::digest(&old[..seal_at]);
        old[seal_at..].copy_from_slice(&digest);
        let error = match CompiledGrammar::from_artifact(&old) {
            Err(error) => error,
            Ok(_) => panic!("old format loaded without reminting"),
        };
        assert!(matches!(&error, ArtifactError::Version { found: 2 }));
        assert!(error.to_string().contains("re-mint"));
    }
    // These controls observe hashing paths and also prove
    // ownership, strict parsing, deferred table rejection and retry semantics.
    #[test]
    fn verified_standalone_owns_payload_and_hashes_once_before_lazy_decode() {
        let grammar = json();
        let original = grammar.artifact().unwrap();
        let mut caller_bytes = original.clone();
        ENVELOPE_HASHES.with(|n| n.set(0));
        let bank = Bank::from_bytes(&caller_bytes).unwrap();
        let retained = pending_bytes(&bank, "json");
        assert!(retained.upgrade().is_some());
        assert_eq!(ENVELOPE_HASHES.with(|n| n.get()), 1);
        caller_bytes.fill(0);
        drop(caller_bytes);
        let loaded = bank.get("json").unwrap().unwrap();
        assert!(
            retained.upgrade().is_none(),
            "ready grammar kept its raw payload"
        );
        parity(&grammar, &loaded, br#"{"a":[1,true]}"#);
        assert_eq!(loaded.artifact().unwrap(), original);
        assert!(Arc::ptr_eq(&loaded, &bank.get("json").unwrap().unwrap()));
        assert_eq!(ENVELOPE_HASHES.with(|n| n.get()), 1);
        drop(bank);
        loaded.session().parse(b"[null]").unwrap();
        ENVELOPE_HASHES.with(|n| n.set(0));
        let direct = CompiledGrammar::from_artifact(&original).unwrap();
        assert_eq!(ENVELOPE_HASHES.with(|n| n.get()), 1);
        parity(&grammar, &direct, b"[2]");
    }
    #[test]
    fn concurrent_native_getters_publish_one_owned_grammar_and_release_the_proof() {
        let original = json().artifact().unwrap();
        ENVELOPE_HASHES.with(|n| n.set(0));
        let bank = Arc::new(Bank::from_bytes(&original).unwrap());
        let retained = pending_bytes(&bank, "json");
        let barrier = Arc::new(std::sync::Barrier::new(8));
        let workers = (0..8)
            .map(|_| {
                let bank = Arc::clone(&bank);
                let barrier = Arc::clone(&barrier);
                std::thread::spawn(move || {
                    ENVELOPE_HASHES.with(|n| n.set(0));
                    barrier.wait();
                    let grammar = bank.get("json").unwrap().unwrap();
                    grammar
                        .session()
                        .parse(br#"{"worker":[true,null,3]}"#)
                        .unwrap();
                    assert_eq!(ENVELOPE_HASHES.with(|n| n.get()), 0);
                    grammar
                })
            })
            .collect::<Vec<_>>();
        let grammars = workers
            .into_iter()
            .map(|worker| worker.join().unwrap())
            .collect::<Vec<_>>();
        assert_eq!(grammars.len(), 8);
        assert!(
            grammars
                .iter()
                .all(|grammar| Arc::ptr_eq(grammar, &grammars[0]))
        );
        assert!(retained.upgrade().is_none());
        assert_eq!(ENVELOPE_HASHES.with(|n| n.get()), 1);
        drop(bank);
        assert_eq!(grammars[0].artifact().unwrap(), original);
        grammars[0].session().parse(b"[false]").unwrap();
    }
    #[test]
    fn verified_bank_keeps_member_proofs_on_owned_arena_and_rejects_corruption() {
        let one = json();
        let two = CompiledGrammar::compile(
            br#"{"name":"letters","rules":{"doc":{"type":"PATTERN","value":"[a-z]+"}}}"#,
        )
        .unwrap();
        let expected = one.artifact().unwrap();
        let mut bytes = Bank::pack(&[Arc::clone(&one), two]).unwrap();
        ENVELOPE_HASHES.with(|n| n.set(0));
        let bank = Bank::from_bytes(&bytes).unwrap();
        let retained = pending_bytes(&bank, "json");
        assert!(std::sync::Weak::ptr_eq(
            &retained,
            &pending_bytes(&bank, "letters")
        ));
        assert_eq!(ENVELOPE_HASHES.with(|n| n.get()), 3);
        bytes.fill(0);
        drop(bytes);
        let loaded = bank.get("json").unwrap().unwrap();
        assert!(
            retained.upgrade().is_some(),
            "unselected member lost its shared proof"
        );
        assert_eq!(loaded.artifact().unwrap(), expected);
        bank.get("letters")
            .unwrap()
            .unwrap()
            .session()
            .parse(b"abc")
            .unwrap();
        assert!(
            retained.upgrade().is_none(),
            "fully decoded bank kept its raw arena"
        );
        assert!(Arc::ptr_eq(&loaded, &bank.get("json").unwrap().unwrap()));
        assert_eq!(ENVELOPE_HASHES.with(|n| n.get()), 3);
        // Re-sealing the outer bank cannot legitimize a corrupt member.
        let mut member = expected.clone();
        member[HEADER + 10] ^= 1;
        let corrupt = pack_members(
            &[("json", &member)],
            &mut ImageOperation::new(ArtifactLimits::default()),
        )
        .unwrap();
        assert!(matches!(
            Bank::from_bytes(&corrupt),
            Err(ArtifactError::Seal)
        ));
    }
    #[test]
    fn verified_capability_does_not_skip_scanner_or_table_validation_and_failures_retry() {
        let bytes = json().artifact().unwrap();
        let mut body = envelope(&bytes, GRAMMAR_MAGIC, ArtifactLimits::default())
            .unwrap()
            .to_vec();
        let mut r = Reader::new(&body, ArtifactLimits::default());
        r.text().unwrap();
        let scanner_at = r.at;
        body[scanner_at] ^= 1;
        let invalid = seal(GRAMMAR_MAGIC, body);
        ENVELOPE_HASHES.with(|n| n.set(0));
        let bank = Bank::from_bytes(&invalid).unwrap();
        let retained = pending_bytes(&bank, "json");
        for _ in 0..2 {
            assert!(matches!(bank.get("json"), Err(ArtifactError::Schema)));
        }
        assert_eq!(ENVELOPE_HASHES.with(|n| n.get()), 1);
        match &bank.members["json"] {
            Member::Native(cache) => {
                assert!(matches!(&*cache.lock().unwrap(), NativeMember::Pending(_)))
            }
            Member::Ready(_) => panic!("invalid native member became ready"),
        }
        assert!(
            retained.upgrade().is_some(),
            "failed decode discarded its original proof"
        );
        assert!(matches!(
            CompiledGrammar::from_artifact(&invalid),
            Err(ArtifactError::Schema)
        ));
        assert_eq!(ENVELOPE_HASHES.with(|n| n.get()), 2);
    }
    #[test]
    fn verified_members_keep_decode_limits_and_do_not_publish_failed_tables() {
        let bytes = json().artifact().unwrap();
        let bank_bytes = pack_members(
            &[("json", &bytes)],
            &mut ImageOperation::new(ArtifactLimits::default()),
        )
        .unwrap();
        for limits in [
            ArtifactLimits {
                symbols: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                states: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                productions: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                steps: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                items: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                table_entries: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                actions: 1,
                ..ArtifactLimits::default()
            },
        ] {
            let bank = Bank::from_bytes_with_limits(&bank_bytes, limits).unwrap();
            for _ in 0..2 {
                assert!(matches!(bank.get("json"), Err(ArtifactError::Limit { .. })));
            }
            match &bank.members["json"] {
                Member::Native(cache) => {
                    assert!(matches!(&*cache.lock().unwrap(), NativeMember::Pending(_)))
                }
                Member::Ready(_) => panic!("limited native member became ready"),
            }
        }
        assert!(matches!(
            Bank::from_bytes_with_limits(
                &bytes,
                ArtifactLimits {
                    bytes: bytes.len() - 1,
                    ..ArtifactLimits::default()
                }
            ),
            Err(ArtifactError::Limit {
                resource: "artifact bytes",
                ..
            })
        ));
    }
    #[test]
    fn json_ready_members_have_no_native_payload_or_hash_path() {
        ENVELOPE_HASHES.with(|n| n.set(0));
        let bank = Bank::from_bytes(
            br#"{"name":"ready","rules":{"doc":{"type":"SEQ","members":[{"type":"STRING","value":"x"}]}}}"#,
        ).unwrap();
        assert!(matches!(&bank.members["ready"], Member::Ready(_)));
        let one = bank.get("ready").unwrap().unwrap();
        let two = bank.get("ready").unwrap().unwrap();
        assert!(Arc::ptr_eq(&one, &two));
        one.session().parse(b"x").unwrap();
        assert_eq!(ENVELOPE_HASHES.with(|n| n.get()), 0);
    }
    #[test]
    fn compiled_roundtrip_is_canonical_across_independent_builds_and_preserves_behavior() {
        let first = json();
        let second = json();
        let bytes = first.artifact().unwrap();
        assert_eq!(bytes, second.artifact().unwrap());
        let loaded = CompiledGrammar::from_artifact(&bytes).unwrap();
        assert_eq!(bytes, loaded.artifact().unwrap());
        assert_eq!(first.name(), loaded.name());
        assert_eq!(first.state_count(), loaded.state_count());
        for source in [
            br#"{"a":[null,true,1],"b":"text"}"#.as_slice(),
            b"[1,,2]",
            b"",
            b"[true]  \n",
        ] {
            parity(&first, &loaded, source);
        }
    }
    #[test]
    fn fields_aliases_supertypes_extras_and_conflict_order_survive() {
        let source=br#"{"name":"recipes","rules":{"doc":{"type":"SEQ","members":[{"type":"FIELD","name":"opening","content":{"type":"SYMBOL","name":"_open"}},{"type":"FIELD","name":"value","content":{"type":"ALIAS","named":true,"value":"value","content":{"type":"SYMBOL","name":"_value"}}},{"type":"STRING","value":")"}]},"_open":{"type":"STRING","value":"("},"_value":{"type":"CHOICE","members":[{"type":"SYMBOL","name":"a"},{"type":"SYMBOL","name":"b"}]},"a":{"type":"STRING","value":"x"},"b":{"type":"STRING","value":"x"}},"supertypes":["_value"],"conflicts":[["a","b"]],"extras":[{"type":"PATTERN","value":"[ ]+"}]}"#;
        let first = CompiledGrammar::compile(source).unwrap();
        let loaded = CompiledGrammar::from_artifact(&first.artifact().unwrap()).unwrap();
        parity(&first, &loaded, b"( x )");
        assert_eq!(first.automaton.supertypes(), loaded.automaton.supertypes());
        assert_eq!(
            format!("{:?}", first.conflict_diagnostics()),
            format!("{:?}", loaded.conflict_diagnostics())
        );
    }
    #[test]
    fn expanded_recipe_spellings_are_interned_on_wire_and_after_checked_loading() {
        let name = "long_alias".repeat(16_384);
        let source = serde_json::json!({"name":"shared_recipe","rules":{"doc":{
            "type":"ALIAS","named":true,"value":name,
            "content":{"type":"SEQ","members":vec![serde_json::json!({"type":"STRING","value":"x"});128]}
        }}});
        let original = CompiledGrammar::compile(&serde_json::to_vec(&source).unwrap()).unwrap();
        let bytes = original.artifact().unwrap();
        assert!(
            bytes.len() < name.len() + 100_000,
            "wire must not repeat a large expanded alias"
        );
        let loaded = CompiledGrammar::from_artifact_with_limits(
            &bytes,
            ArtifactLimits {
                text_bytes: name.len() + 1024,
                ..ArtifactLimits::default()
            },
        )
        .unwrap();
        assert_eq!(bytes, loaded.artifact().unwrap());
        let production = loaded
            .productions()
            .map(|(_, production)| production)
            .find(|p| p.lhs == loaded.start_symbol())
            .unwrap();
        let first = &production.steps[0].alias.as_ref().unwrap().name;
        assert!(
            production
                .steps
                .iter()
                .all(|s| Arc::ptr_eq(first, &s.alias.as_ref().unwrap().name))
        );
        assert_eq!(first.as_ref(), name);
        let tree = loaded.session().parse(&[b'x'; 128]).unwrap();
        assert_eq!(tree.root().unwrap().children().count(), 128);
        assert!(tree.root().unwrap().children().all(|n| n.name() == name));
    }
    #[test]
    fn resealed_recipe_dictionary_duplicates_and_bad_references_refuse() {
        let source=br#"{"name":"recipe_refs","rules":{"doc":{"type":"SEQ","members":[
            {"type":"ALIAS","named":true,"value":"native_alias_A","content":{"type":"STRING","value":"x"}},
            {"type":"ALIAS","named":true,"value":"native_alias_B","content":{"type":"STRING","value":"y"}}]}}}"#;
        let original = CompiledGrammar::compile(source)
            .unwrap()
            .artifact()
            .unwrap();
        let payload = envelope(&original, GRAMMAR_MAGIC, ArtifactLimits::default()).unwrap();
        let at = |name: &[u8]| payload.windows(name.len()).position(|s| s == name).unwrap();
        let mut duplicate = payload.to_vec();
        let a = at(b"native_alias_A");
        let b = at(b"native_alias_B");
        duplicate.copy_within(a..a + b"native_alias_A".len(), b);
        assert!(matches!(
            CompiledGrammar::from_artifact(&seal(GRAMMAR_MAGIC, duplicate)),
            Err(ArtifactError::Invalid("recipe spelling order"))
        ));
        // The small fixture has the augmented entry and one authored sequence.
        // Read the first entry recipe, then locate the authored step's alias ID.
        let after = b + b"native_alias_B".len();
        let mut r = Reader::new(&payload[after..], ArtifactLimits::default());
        assert_eq!(r.number().unwrap(), 2);
        r.number().unwrap();
        r.signed().unwrap();
        assert_eq!(r.number().unwrap(), 1);
        r.number().unwrap();
        assert_eq!(r.optional().unwrap(), None);
        assert!(!r.flag().unwrap());
        let marker = after + r.at;
        assert_eq!(r.tag().unwrap(), 0);
        for (value, reason) in [
            (255, "alias recipe tag"),
            (1, "local alias recipe without alias"),
        ] {
            let mut invalid = payload.to_vec();
            invalid[marker] = value;
            assert!(matches!(
                CompiledGrammar::from_artifact(&seal(GRAMMAR_MAGIC, invalid)),
                Err(ArtifactError::Invalid(found)) if found == reason
            ));
        }
        assert_eq!(r.tag().unwrap(), 0);
        assert_eq!(r.tag().unwrap(), 0);
        r.number().unwrap();
        assert!(!r.flag().unwrap());
        assert!(!r.flag().unwrap());
        r.number().unwrap();
        r.signed().unwrap();
        assert_eq!(r.number().unwrap(), 2);
        r.number().unwrap();
        assert_eq!(r.optional().unwrap(), None);
        assert!(r.flag().unwrap());
        let offset = after + r.at;
        let mut bad_id = payload.to_vec();
        bad_id[offset..offset + 4].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(matches!(
            CompiledGrammar::from_artifact(&seal(GRAMMAR_MAGIC, bad_id)),
            Err(ArtifactError::Invalid("recipe spelling ID"))
        ));
    }
    #[test]
    fn previous_native_drafts_require_remint_even_inside_a_current_bank() {
        let mut member = json().artifact().unwrap();
        member[8..12].copy_from_slice(&1u32.to_le_bytes());
        member[12..16].copy_from_slice(&2u32.to_le_bytes());
        let error = CompiledGrammar::from_artifact(&member).unwrap_err();
        assert!(matches!(error, ArtifactError::Version { found: 1 }));
        assert!(error.to_string().contains("re-mint"));
        assert!(matches!(
            Bank::from_bytes(&member),
            Err(ArtifactError::Version { found: 1 })
        ));
        assert!(matches!(
            Bank::pack_artifacts(&[&member]),
            Err(ArtifactError::Version { found: 1 })
        ));

        let mut bank = Bank::pack(&[json()]).unwrap();
        bank[8..12].copy_from_slice(&1u32.to_le_bytes());
        bank[12..16].copy_from_slice(&2u32.to_le_bytes());
        assert!(matches!(
            Bank::from_bytes(&bank),
            Err(ArtifactError::Version { found: 1 })
        ));

        let mut directory = Writer::new();
        directory.number(1).unwrap();
        directory.text("json").unwrap();
        directory.wide(0);
        directory.wide(member.len() as u64);
        directory.raw(&member);
        assert!(matches!(
            Bank::from_bytes(&seal(BANK_MAGIC, directory.bytes)),
            Err(ArtifactError::Version { found: 1 })
        ));

        let mut schema = json().artifact().unwrap();
        schema[12..16].copy_from_slice(&2u32.to_le_bytes());
        assert!(matches!(
            CompiledGrammar::from_artifact(&schema),
            Err(ArtifactError::Schema)
        ));
    }
    #[test]
    fn pooled_named_precedence_and_reserved_recipe_metadata_roundtrip_without_claiming_enforcement()
    {
        let source=br#"{"name":"rank_context","rules":{"doc":{"type":"RESERVED","context_name":"ctx","content":{"type":"PREC_LEFT","value":"tier","content":{"type":"SEQ","members":[{"type":"ALIAS","named":true,"value":"kept","content":{"type":"STRING","value":"x"}},{"type":"STRING","value":"y"}]}}}},"reserved":{"ctx":[]},"precedences":[[{"type":"STRING","value":"tier"}]]}"#;
        let original = CompiledGrammar::compile(source).unwrap();
        let loaded = CompiledGrammar::from_artifact(&original.artifact().unwrap()).unwrap();
        let a = original
            .productions()
            .map(|(_, p)| p.steps.clone())
            .collect::<Vec<_>>();
        let b = loaded
            .productions()
            .map(|(_, p)| p.steps.clone())
            .collect::<Vec<_>>();
        assert_eq!(a, b);
        assert!(b.iter().flatten().any(
            |s| matches!(&s.prec,crate::Prec::Named(n) if n.as_ref()=="tier")
                && s.reserved.as_deref() == Some("ctx")
        ));
        assert_eq!(original.limitations(), loaded.limitations());
        assert!(
            matches!(loaded.limitations(),[crate::CompileLimitation::ReservedWordContexts{contexts}] if contexts==&["ctx"])
        );
        parity(&original, &loaded, b"xy");
    }
    #[test]
    fn rule_shaped_extra_entry_kernels_and_named_extra_trees_roundtrip() {
        let source=br#"{"name":"rule_extra","rules":{"doc":{"type":"REPEAT1","content":{"type":"STRING","value":"x"}},"comment":{"type":"SEQ","members":[{"type":"SYMBOL","name":"open"},{"type":"PATTERN","value":"[a-z]+"},{"type":"STRING","value":"*/"}]},"open":{"type":"STRING","value":"/*"}},"extras":[{"type":"SYMBOL","name":"comment"},{"type":"PATTERN","value":"[ ]+"}]}"#;
        let first = CompiledGrammar::compile(source).unwrap();
        assert_eq!(first.automaton.extra_entries().len(), 1);
        let loaded = CompiledGrammar::from_artifact(&first.artifact().unwrap()).unwrap();
        parity(&first, &loaded, b"x /*note*/ x");
        assert_eq!(
            first.automaton.extra_entries(),
            loaded.automaton.extra_entries()
        );
    }
    #[test]
    fn json_dispatch_and_native_decoding_have_explicit_separate_work_policies() {
        let source = br#"{"name":"json_dispatch","rules":{"doc":{"type":"STRING","value":"x"}}}"#;
        let bank = Bank::from_bytes_with_limits(
            source,
            ArtifactLimits {
                work: 0,
                ..ArtifactLimits::default()
            },
        )
        .unwrap();
        bank.get("json_dispatch")
            .unwrap()
            .unwrap()
            .session()
            .parse(b"x")
            .unwrap();
        assert!(matches!(
            Bank::from_bytes_with_limits(
                source,
                ArtifactLimits {
                    bytes: 0,
                    ..ArtifactLimits::default()
                }
            ),
            Err(ArtifactError::Limit {
                resource: "artifact bytes",
                ..
            })
        ));
    }
    #[test]
    fn custom_scanner_source_and_matching_ceilings_are_sealed_and_reconstructed() {
        let source=br#"{"name":"custom","externals":[{"type":"SYMBOL","name":"answer"}],"rules":{"doc":{"type":"SYMBOL","name":"answer"}}}"#;
        let book=br#"{"cohort":["answer"],"probes":{"body":"x+"},"rules":[{"phase":"bounded","when":[["wanted","answer"],["probe","body"]],"then":[["emit","answer"]]}]}"#;
        let options = CompileOptions {
            probes: ProbeLimits {
                match_steps: 12345,
                depth: 1234,
                heap_bytes: 1024 * 1024,
            },
            ..CompileOptions::default()
        };
        let first = CompiledGrammar::compile_with_customary(source, book, options).unwrap();
        let bytes = first.artifact().unwrap();
        let loaded = CompiledGrammar::from_artifact(&bytes).unwrap();
        assert_eq!(loaded.customary.as_deref(), Some(book.as_slice()));
        assert_eq!(loaded.options.probes, options.probes);
        parity(&first, &loaded, b"xxx");
        let mut payload = envelope(&bytes, GRAMMAR_MAGIC, ArtifactLimits::default())
            .unwrap()
            .to_vec();
        let mut r = Reader::new(&payload, ArtifactLimits::default());
        r.text().unwrap();
        let at = r.at;
        payload[at] ^= 1;
        assert!(matches!(
            CompiledGrammar::from_artifact(&seal(GRAMMAR_MAGIC, payload)),
            Err(ArtifactError::Schema)
        ));
    }
    #[test]
    fn banks_are_sorted_owned_independent_and_reject_duplicate_titles() {
        let one = json();
        let two = CompiledGrammar::compile(
            br#"{"name":"letters","rules":{"doc":{"type":"PATTERN","value":"[a-z]+"}}}"#,
        )
        .unwrap();
        let bytes = Bank::pack(&[Arc::clone(&one), Arc::clone(&two)]).unwrap();
        assert_eq!(
            bytes,
            Bank::pack(&[Arc::clone(&two), Arc::clone(&one)]).unwrap()
        );
        assert_eq!(
            bytes,
            Bank::pack_artifacts(&[&two.artifact().unwrap(), &one.artifact().unwrap()]).unwrap()
        );
        let bank = Bank::from_bytes(&bytes).unwrap();
        assert_eq!(
            bank.languages().collect::<Vec<_>>(),
            vec!["json", "letters"]
        );
        let grammar = bank.get("letters").unwrap().unwrap();
        assert!(Arc::ptr_eq(
            &grammar,
            &bank.get("letters").unwrap().unwrap()
        ));
        assert!(bank.get("missing").unwrap().is_none());
        drop(bank);
        drop(bytes);
        grammar.session().parse(b"abc").unwrap();
        assert!(Bank::pack(&[]).is_err());
        assert!(Bank::pack(&[Arc::clone(&one), one]).is_err());
        assert_eq!(
            Bank::from_bytes(br#"{"name":"single","rules":{"doc":{"type":"STRING","value":"x"}}}"#)
                .unwrap()
                .languages()
                .next(),
            Some("single")
        );
    }
    #[test]
    fn malformed_envelopes_fail_closed_including_validly_resealed_bad_tags_and_counts() {
        let bytes = json().artifact().unwrap();
        for end in 0..bytes.len() {
            assert!(
                CompiledGrammar::from_artifact(&bytes[..end]).is_err(),
                "prefix {end}"
            );
        }
        for at in 0..bytes.len() {
            let mut flipped = bytes.clone();
            flipped[at] ^= 0x80;
            assert!(
                CompiledGrammar::from_artifact(&flipped).is_err(),
                "flip {at}"
            );
        }
        let mut tail = bytes.clone();
        tail.push(0);
        assert!(matches!(
            CompiledGrammar::from_artifact(&tail),
            Err(ArtifactError::Length)
        ));
        let mut payload = envelope(&bytes, GRAMMAR_MAGIC, ArtifactLimits::default())
            .unwrap()
            .to_vec();
        let mut r = Reader::new(&payload, ArtifactLimits::default());
        r.text().unwrap();
        r.take(32).unwrap();
        read_options(&mut r).unwrap();
        r.flag().unwrap();
        let count = r.at;
        payload[count..count + 4].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(matches!(
            CompiledGrammar::from_artifact(&seal(GRAMMAR_MAGIC, payload)),
            Err(ArtifactError::Limit {
                resource: "symbols",
                ..
            })
        ));
        let mut payload = envelope(&bytes, GRAMMAR_MAGIC, ArtifactLimits::default())
            .unwrap()
            .to_vec();
        let mut r = Reader::new(&payload, ArtifactLimits::default());
        r.text().unwrap();
        r.take(32).unwrap();
        read_options(&mut r).unwrap();
        r.flag().unwrap();
        r.number().unwrap();
        r.text().unwrap();
        let shape = r.at;
        payload[shape] = 255;
        assert!(matches!(
            CompiledGrammar::from_artifact(&seal(GRAMMAR_MAGIC, payload)),
            Err(ArtifactError::Invalid("symbol shape"))
        ));
        let mut version = bytes.clone();
        version[8..12].copy_from_slice(&99u32.to_le_bytes());
        assert!(matches!(
            CompiledGrammar::from_artifact(&version),
            Err(ArtifactError::Version { found: 99 })
        ));
        for (data, format) in [
            (b"OTLFOLIO".as_slice(), "folio"),
            (b"OTLCODEX".as_slice(), "codex"),
        ] {
            assert!(
                matches!(Bank::from_bytes(data),Err(ArtifactError::LegacyFormat{format:f}) if f==format)
            );
        }
    }
    #[test]
    fn sealed_bank_directories_refuse_offsets_overlaps_titles_and_trailing_members() {
        fn directory(entries: &[(&str, u64, u64)], arena: &[u8]) -> Vec<u8> {
            let mut w = Writer::new();
            w.number(entries.len()).unwrap();
            for &(name, off, len) in entries {
                w.text(name).unwrap();
                w.wide(off);
                w.wide(len);
            }
            w.raw(arena);
            seal(BANK_MAGIC, w.bytes)
        }
        let member = json().artifact().unwrap();
        let n = member.len() as u64;
        for data in [
            directory(&[("json", 1, n)], &member),
            directory(&[("forged", 0, n)], &member),
            directory(&[("json", 0, u64::MAX)], &member),
            directory(
                &[("json", 0, n), ("json", n, n)],
                &[member.clone(), member.clone()].concat(),
            ),
            directory(&[("a", 0, n), ("b", 0, n)], &member),
            directory(&[("json", 0, n)], &[member.clone(), vec![0]].concat()),
        ] {
            assert!(Bank::from_bytes(&data).is_err());
        }
        let mut bad = Writer::new();
        bad.number(1).unwrap();
        bad.blob(&[255]).unwrap();
        bad.wide(0);
        bad.wide(n);
        bad.raw(&member);
        assert!(matches!(
            Bank::from_bytes(&seal(BANK_MAGIC, bad.bytes)),
            Err(ArtifactError::Invalid("UTF-8 text"))
        ));
    }
    // Known retained diagnostic payload, not total heap/RSS: row headers and
    // items, history-map key/value payloads, and concrete member IDs. Allocator
    // overhead, BTree node bookkeeping and spare capacity are excluded.
    fn diagnostic_payload(grammar: &CompiledGrammar) -> (usize, usize, usize, usize) {
        let kernels = (0..grammar.state_count())
            .map(|index| {
                grammar
                    .state_items(grammar.state_id(index).unwrap())
                    .unwrap()
                    .len()
            })
            .sum::<usize>();
        let (mut classes, mut members) = (0usize, 0usize);
        for (production, rule) in grammar.productions() {
            for dot in 0..=rule.steps.len() {
                if let Some(history) =
                    grammar.cursor_histories(crate::StateItem { production, dot })
                {
                    classes += 1;
                    members += history.len();
                }
            }
        }
        let bytes = grammar.state_count() * std::mem::size_of::<Vec<crate::StateItem>>()
            + kernels * std::mem::size_of::<crate::StateItem>()
            + classes * std::mem::size_of::<(crate::StateItem, Vec<crate::ProductionId>)>()
            + members * std::mem::size_of::<crate::ProductionId>();
        (kernels, classes, members, bytes)
    }
    #[test]
    #[ignore = "explicit pinned native table roundtrip and load-cost probe"]
    fn pinned_native_table_load_probe() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
        let selected = std::env::var("JNT_ARTIFACT_PINS").unwrap_or_else(|_| "go,python".into());
        let mut count = 0;
        for block in include_str!("../../grammars.toml")
            .split("[[grammar]]")
            .skip(1)
        {
            let read = |key: &str| {
                block
                    .lines()
                    .find_map(|line| line.strip_prefix(&format!("{key} = \""))?.strip_suffix('"'))
            };
            let Some(name) = read("name") else { continue };
            if !selected.split(',').any(|s| s == name) {
                continue;
            }
            let input = root.join(format!("upstream/grammars/{name}.json"));
            let source = std::fs::read(&input).unwrap();
            let expected = read("sha256").unwrap();
            assert_eq!(
                Sha256::digest(&source)
                    .iter()
                    .map(|byte| format!("{byte:02x}"))
                    .collect::<String>(),
                expected
            );
            let begin = std::time::Instant::now();
            let original = CompiledGrammar::compile(&source).unwrap();
            let compile = begin.elapsed();
            let bytes = original.artifact().unwrap();
            let before = std::time::Instant::now();
            let loaded = CompiledGrammar::from_artifact(&bytes).unwrap();
            let load = before.elapsed();
            assert_eq!(bytes, loaded.artifact().unwrap());
            assert_eq!(original.state_count(), loaded.state_count());
            let diagnostics = diagnostic_payload(&original);
            assert_eq!(diagnostics, diagnostic_payload(&loaded));
            for index in 0..original.state_count() {
                let state = original.state_id(index).unwrap();
                assert_eq!(original.state_items(state), loaded.state_items(state));
            }
            match name {
                "go" => parity(
                    &original,
                    &loaded,
                    b"package main\nfunc f() { println(1) }\n",
                ),
                "python" => parity(&original, &loaded, b"def f(x):\n  return x + 1\n"),
                _ => {}
            }
            assert_eq!(std::fs::read(input).unwrap(), source);
            eprintln!(
                "ARTIFACT_PIN {name} states={} bytes={} compile_ns={} load_ns={} kernel_items={} history_classes={} history_members={} diagnostic_payload_bytes={}",
                original.state_count(),
                bytes.len(),
                compile.as_nanos(),
                load.as_nanos(),
                diagnostics.0,
                diagnostics.1,
                diagnostics.2,
                diagnostics.3
            );
            count += 1;
        }
        assert!(count > 0, "empty artifact pin selection");
    }
    #[test]
    fn explicit_low_load_budgets_refuse_without_native_publication() {
        let bytes = json().artifact().unwrap();
        for limits in [
            ArtifactLimits {
                bytes: 8,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                symbols: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                states: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                productions: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                steps: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                items: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                table_entries: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                actions: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                text_bytes: 1,
                ..ArtifactLimits::default()
            },
            ArtifactLimits {
                work: 1,
                ..ArtifactLimits::default()
            },
        ] {
            assert!(matches!(
                CompiledGrammar::from_artifact_with_limits(&bytes, limits),
                Err(ArtifactError::Limit { .. })
            ));
        }
        let bank = Bank::pack(&[json()]).unwrap();
        assert!(matches!(
            Bank::from_bytes_with_limits(
                &bank,
                ArtifactLimits {
                    languages: 0,
                    ..ArtifactLimits::default()
                }
            ),
            Err(ArtifactError::Limit {
                resource: "languages",
                ..
            })
        ));
    }
}
