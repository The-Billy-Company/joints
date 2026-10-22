//! Independent SHA-256 byte contracts, separate from artifact envelope policy.
#![forbid(unsafe_code)]

use sha2::{Digest, Sha256};

fn expected(hex: &str) -> [u8; 32] {
    assert_eq!(hex.len(), 64);
    let mut bytes = [0; 32];
    for (out, pair) in bytes.iter_mut().zip(hex.as_bytes().chunks_exact(2)) {
        *out = u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap();
    }
    bytes
}

#[test]
fn sha256_standard_vectors_keep_exact_digest_bytes() {
    for (bytes, hex) in [
        (
            b"".as_slice(),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ),
        (
            b"abc".as_slice(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        ),
        (
            b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".as_slice(),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
        ),
    ] {
        assert_eq!(Sha256::digest(bytes).as_slice(), expected(hex));
    }
}

#[test]
fn sha256_padding_multiblock_chunking_and_cloned_prefix_keep_independent_bytes() {
    // Literal expected values were generated independently with Python/OpenSSL,
    // not by this dependency. Message byte i is i modulo256.
    for (length, hex) in [
        (
            0,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ),
        (
            1,
            "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d",
        ),
        (
            55,
            "463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59",
        ),
        (
            56,
            "da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562",
        ),
        (
            63,
            "29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488",
        ),
        (
            64,
            "fdeab9acf3710362bd2658cdc9a29e8f9c757fcf9811603a8c447cd1d9151108",
        ),
        (
            65,
            "4bfd2c8b6f1eec7a2afeb48b934ee4b2694182027e6d0fc075074f2fabb31781",
        ),
        (
            127,
            "92ca0fa6651ee2f97b884b7246a562fa71250fedefe5ebf270d31c546bfea976",
        ),
        (
            128,
            "471fb943aa23c511f6f72f8d1652d9c880cfa392ad80503120547703e56a2be5",
        ),
        (
            129,
            "5099c6a56203f9687f7d33f4bfdf576d31dc91f6b695ecea38b2770c87631135",
        ),
        (
            1024,
            "785b0751fc2c53dc14a4ce3d800e69ef9ce1009eb327ccf458afe09c242c26c9",
        ),
        (
            65536,
            "7daca2095d0438260fa849183dfc67faa459fdf4936e1bc91eec6b281b27e4c2",
        ),
    ] {
        let bytes: Vec<_> = (0..length)
            .map(|i| u8::try_from(i % 256).unwrap())
            .collect();
        let want = expected(hex);
        assert_eq!(Sha256::digest(&bytes).as_slice(), want, "length={length}");
        for size in [1, 3, 7, 55, 64, 65, 257, 4096] {
            let mut digest = Sha256::new();
            digest.update([]);
            for chunk in bytes.chunks(size) {
                digest.update(chunk);
            }
            digest.update([]);
            assert_eq!(
                digest.finalize().as_slice(),
                want,
                "length={length}, chunk={size}"
            );
        }
        // Clone partially filled and exactly filled blocks before independently
        // completing the same known message. Finalizing one copy cannot alter
        // the other copy's retained prefix.
        for split in [0, 1, 55, 56, 63, 64, 65, 127, 128] {
            let split = split.min(length);
            let mut prefix = Sha256::new();
            prefix.update(&bytes[..split]);
            let mut copy = prefix.clone();
            prefix.update(&bytes[split..]);
            for chunk in bytes[split..].chunks(7) {
                copy.update(chunk);
            }
            assert_eq!(
                prefix.finalize().as_slice(),
                want,
                "length={length}, split={split}"
            );
            assert_eq!(
                copy.finalize().as_slice(),
                want,
                "cloned length={length}, split={split}"
            );
        }
    }
}
