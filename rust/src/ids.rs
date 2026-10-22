//! Typed indexes keep grammar domains distinct without exposing their storage.

macro_rules! id {
    ($name:ident) => {
        #[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
        pub struct $name(u32);

        impl $name {
            pub fn index(self) -> usize {
                self.0 as usize
            }

            pub(crate) fn from_index(index: usize) -> Self {
                Self(u32::try_from(index).expect("bounded grammar index"))
            }
        }
    };
}

id!(SymbolId);
id!(StateId);
id!(ProductionId);
id!(ReductionId);
id!(FieldId);
id!(PatternId);
id!(CaptureId);
