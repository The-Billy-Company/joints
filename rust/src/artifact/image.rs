//! One conservative account for an artifact operation, including every member.
//! Reader work and image work meet only at ImageSession's checked bridge.
use super::{ArtifactError, ArtifactLimits, Reader};
use irgx::{ImageBudget, ImageLimits, Munch, MunchBuilder, MunchImage};

const HEADER_WORK: u64 = 176;
const WORK_LIMIT: u64 = 128_000_000;

#[derive(Clone, Copy, Default, Debug)]
struct Shape {
    encoded: u64,
    decoded: u64,
    patterns: u64,
    voices: u64,
    states: u64,
    transitions: u64,
    auxiliary: u64,
}
impl Shape {
    fn remaining(self, limits: ImageLimits) -> Result<ImageLimits, ArtifactError> {
        let subtract = |cap: u64, used: u64| {
            cap.checked_sub(used)
                .ok_or(ArtifactError::Invalid("aggregate image shape"))
        };
        Ok(ImageLimits {
            encoded_bytes: subtract(limits.encoded_bytes, self.encoded)?,
            decoded_bytes: subtract(limits.decoded_bytes, self.decoded)?,
            patterns: subtract(limits.patterns, self.patterns)?,
            voices: subtract(limits.voices, self.voices)?,
            states: subtract(limits.states, self.states)?,
            transition_entries: subtract(limits.transition_entries, self.transitions)?,
            auxiliary_entries: subtract(limits.auxiliary_entries, self.auxiliary)?,
            live_owned_bytes: limits.live_owned_bytes,
        })
    }
    fn plus(self, other: Self) -> Result<Self, ArtifactError> {
        let add = |a: u64, b: u64| {
            a.checked_add(b)
                .ok_or(ArtifactError::Invalid("image shape overflow"))
        };
        Ok(Self {
            encoded: add(self.encoded, other.encoded)?,
            decoded: add(self.decoded, other.decoded)?,
            patterns: add(self.patterns, other.patterns)?,
            voices: add(self.voices, other.voices)?,
            states: add(self.states, other.states)?,
            transitions: add(self.transitions, other.transitions)?,
            auxiliary: add(self.auxiliary, other.auxiliary)?,
        })
    }
}

pub(crate) struct ImageOperation {
    limits: ImageLimits,
    budget: ImageBudget,
    shape: Shape,
}
impl ImageOperation {
    pub(crate) fn new(limits: ArtifactLimits) -> Self {
        Self {
            limits: limits.images,
            budget: ImageBudget::new(
                limits.image_allocation,
                (limits.work as u64).min(WORK_LIMIT),
                &limits.images,
            ),
            shape: Shape::default(),
        }
    }
    pub(crate) fn reader_limits(&self, mut limits: ArtifactLimits) -> ArtifactLimits {
        limits.work = limits.work.min(self.budget.work_left() as usize);
        limits
    }
    pub(crate) fn charge_allocation(&mut self, bytes: usize) -> Result<(), ArtifactError> {
        self.budget.charge_allocation(bytes as u64)?;
        Ok(())
    }
    pub(crate) fn charge_work(&mut self, visits: usize) -> Result<(), ArtifactError> {
        self.budget.charge_work(visits as u64)?;
        Ok(())
    }
    pub(super) fn image_bytes(&self) -> u64 {
        self.shape.encoded
    }
    // Called only after successful native validation. The seal/graph/identity
    // decoder remains native; this paid projection commits its fixed statistics.
    fn project(&mut self, bytes: &[u8]) -> Result<(), ArtifactError> {
        self.budget.charge_work(HEADER_WORK)?;
        if bytes.len() < 208 || &bytes[..8] != b"IRGXMCH1" {
            return Err(ArtifactError::Invalid("validated image header"));
        }
        let small = |at| u32::from_le_bytes(bytes[at..at + 4].try_into().expect("header field"));
        let wide = |at| u64::from_le_bytes(bytes[at..at + 8].try_into().expect("header field"));
        if small(8) != 1 || small(12) != 176 || small(28) != 0 || wide(32) != bytes.len() as u64 {
            return Err(ArtifactError::Invalid("validated image layout"));
        }
        let next = self.shape.plus(Shape {
            encoded: wide(32),
            decoded: wide(40),
            patterns: small(48).into(),
            voices: small(52).into(),
            states: wide(64),
            transitions: wide(72),
            auxiliary: wide(80),
        })?;
        next.remaining(self.limits)?;
        self.shape = next;
        Ok(())
    }
    pub(crate) fn save(&mut self, slate: &Munch) -> Result<MunchImage, ArtifactError> {
        let limits = self.shape.remaining(self.limits)?;
        let image = slate.save_image(&limits, &mut self.budget)?;
        self.project(image.as_bytes())?;
        Ok(image)
    }
    fn load(&mut self, expected: &MunchBuilder, bytes: &[u8]) -> Result<Munch, ArtifactError> {
        let limits = self.shape.remaining(self.limits)?;
        let slate = expected.load_image(bytes, &limits, &mut self.budget)?;
        self.project(bytes)?;
        Ok(slate)
    }
    /// Settle the accepted non-image tail on every decoder return, even error.
    pub(crate) fn settle(&mut self, reader: &mut Reader<'_>) -> Result<(), ArtifactError> {
        let delta = reader
            .work
            .checked_sub(reader.image_checkpoint)
            .ok_or(ArtifactError::Invalid("image work checkpoint"))?;
        self.charge_work(delta)?;
        reader.image_checkpoint = reader.work;
        Ok(())
    }
    fn metered<T>(
        &mut self,
        reader: &mut Reader<'_>,
        action: impl FnOnce(&mut Self) -> Result<T, ArtifactError>,
    ) -> Result<T, ArtifactError> {
        self.settle(reader)?;
        // Clipping is a restriction, never a work debit. Measure afterwards.
        self.budget
            .clamp_work_left((reader.limits.work - reader.work) as u64);
        let before = self.budget.work_left();
        let result = action(self);
        let spent = before
            .checked_sub(self.budget.work_left())
            .ok_or(ArtifactError::Invalid("image work grew"))?;
        reader.charge(spent as usize)?;
        reader.image_checkpoint = reader.work;
        result
    }
    #[cfg(test)]
    pub(super) fn remaining(&self) -> (u64, u64) {
        (self.budget.allocation_left(), self.budget.work_left())
    }
}

/// The lexer cannot use native work with an allowance from before its framing.
pub(crate) struct ImageSession<'r, 'a, 'op> {
    reader: &'r mut Reader<'a>,
    operation: &'op mut ImageOperation,
}
impl<'r, 'a, 'op> ImageSession<'r, 'a, 'op> {
    pub(crate) fn new(
        reader: &'r mut Reader<'a>,
        operation: &'op mut ImageOperation,
    ) -> Result<Self, ArtifactError> {
        operation.settle(reader)?;
        Ok(Self { reader, operation })
    }
    pub(crate) fn charge_work(&mut self, visits: usize) -> Result<(), ArtifactError> {
        self.operation
            .metered(self.reader, |op| op.charge_work(visits))
    }
    pub(crate) fn charge_allocation(&mut self, bytes: usize) -> Result<(), ArtifactError> {
        self.operation.settle(self.reader)?;
        self.operation.charge_allocation(bytes)
    }
    pub(crate) fn tier_count(&mut self, expected: usize) -> Result<(), ArtifactError> {
        let result = (|| {
            let found = self.reader.count(expected, 4, "lexer image tiers")?;
            if found != expected {
                return Err(ArtifactError::Invalid("lexer image tier count"));
            }
            Ok(())
        })();
        self.operation.settle(self.reader)?;
        result
    }
    pub(crate) fn frame(&mut self) -> Result<&'a [u8], ArtifactError> {
        let result = (|| {
            let length = self.reader.number()?;
            self.reader.take(length)
        })();
        self.operation.settle(self.reader)?;
        result
    }
    pub(crate) fn load(
        &mut self,
        expected: &MunchBuilder,
        frame: &[u8],
    ) -> Result<Munch, ArtifactError> {
        self.operation
            .metered(self.reader, |op| op.load(expected, frame))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refused_reader_request_never_becomes_consumed_work() {
        let limits = ArtifactLimits {
            work: 1,
            ..ArtifactLimits::default()
        };
        let mut reader = Reader::new(&[], limits);
        let mut operation = ImageOperation::new(limits);
        reader.charge(1).unwrap();
        assert!(reader.charge(1).is_err());
        assert_eq!(reader.work, 1);
        operation.settle(&mut reader).unwrap();
        let remaining = operation.remaining();
        operation.settle(&mut reader).unwrap();
        assert_eq!(remaining, operation.remaining());
        assert_eq!(remaining.1, 0);
    }

    #[test]
    fn framing_cannot_leave_an_old_native_work_allowance() {
        let slate = Munch::new(["a+"]).unwrap();
        let image = ImageOperation::new(ArtifactLimits::default())
            .save(&slate)
            .unwrap();
        let mut framed = Vec::new();
        framed.extend(1u32.to_le_bytes());
        framed.extend((image.as_bytes().len() as u32).to_le_bytes());
        framed.extend(image.as_bytes());
        // count=2 visits, frame length+take=2 visits: none remain for loading.
        let limits = ArtifactLimits {
            work: 4,
            ..ArtifactLimits::default()
        };
        let mut reader = Reader::new(&framed, limits);
        let mut operation = ImageOperation::new(limits);
        let builder = MunchBuilder::new(["a+"]);
        {
            let mut session = ImageSession::new(&mut reader, &mut operation).unwrap();
            session.tier_count(1).unwrap();
            let bytes = session.frame().unwrap();
            assert!(matches!(
                session.load(&builder, bytes),
                Err(ArtifactError::Image(irgx::ImageError::BudgetExceeded))
            ));
        }
        assert_eq!(reader.work, 4);
        assert_eq!(reader.image_checkpoint, 4);
        assert_eq!(operation.remaining().1, 0);
    }

    #[test]
    fn failed_framing_settles_accepted_visits_before_returning() {
        let bytes = 12u32.to_le_bytes();
        let limits = ArtifactLimits {
            work: 4,
            ..ArtifactLimits::default()
        };
        let mut reader = Reader::new(&bytes, limits);
        let mut operation = ImageOperation::new(limits);
        {
            let mut session = ImageSession::new(&mut reader, &mut operation).unwrap();
            assert!(matches!(session.frame(), Err(ArtifactError::Truncated)));
        }
        assert_eq!(reader.work, 2);
        assert_eq!(reader.image_checkpoint, 2);
        assert_eq!(operation.remaining().1, 2);
    }

    #[test]
    fn wrapper_failure_mirrors_work_and_keeps_allocation_debits() {
        let limits = ArtifactLimits::default();
        let mut reader = Reader::new(&[], limits);
        let mut operation = ImageOperation::new(limits);
        let before = operation.remaining();
        let builder = MunchBuilder::new(["a"]);
        {
            let mut session = ImageSession::new(&mut reader, &mut operation).unwrap();
            assert!(matches!(
                session.load(&builder, &[]),
                Err(ArtifactError::Image(irgx::ImageError::Truncated))
            ));
        }
        let after = operation.remaining();
        assert!(after.0 < before.0 && after.1 < before.1);
        assert_eq!(reader.work as u64, before.1 - after.1);
        assert_eq!(reader.image_checkpoint, reader.work);
        operation.settle(&mut reader).unwrap();
        assert_eq!(operation.remaining(), after);
    }
}
