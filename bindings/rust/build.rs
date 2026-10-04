//! Resolve an already-built native library without running a foreign build.

use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-env-changed=JOINTS_LIB_DIR");
    println!("cargo:rerun-if-env-changed=JOINTS_LINK_KIND");
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let repository = manifest.parent().and_then(|p| p.parent());
    let directory = match env::var_os("JOINTS_LIB_DIR") {
        Some(path) => PathBuf::from(path),
        None => match repository.filter(|p| p.join("build.zig").is_file()) {
            Some(root) => root.join("zig-out/lib"),
            None => {
                panic!("libjnt is built separately: set JOINTS_LIB_DIR to its library directory")
            }
        },
    };
    let kind = env::var("JOINTS_LINK_KIND").unwrap_or_else(|_| "static".into());
    let target = env::var("CARGO_CFG_TARGET_OS").unwrap();
    let filename = match (kind.as_str(), target.as_str()) {
        ("static", _) => "libjnt.a",
        ("dynamic", "macos") => "libjnt.dylib",
        ("dynamic", "windows") => "jnt.dll.lib",
        ("dynamic", _) => "libjnt.so",
        _ => panic!("JOINTS_LINK_KIND must be static (default) or dynamic"),
    };
    let library = directory.join(filename);
    assert!(
        library.is_file(),
        "missing {}: run `zig build` in joints, then set JOINTS_LIB_DIR to its zig-out/lib; build the native library for the Cargo target",
        library.display()
    );
    println!("cargo:rerun-if-changed={}", library.display());
    let mut directory = directory.canonicalize().expect("resolve JOINTS_LIB_DIR");
    if kind == "static" {
        // Darwin resolves direct -ljnt links to a same-name dylib even for
        // Rust's static request. A private archive-only search directory also
        // makes test/doc executables independent of the runtime dylib path.
        directory = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("native-static");
        std::fs::create_dir_all(&directory).expect("create native archive directory");
        let output = if target == "windows" {
            "jnt.lib"
        } else {
            filename
        };
        std::fs::copy(&library, directory.join(output)).expect("copy native archive");
        println!("cargo:rustc-link-lib=static=jnt");
    } else {
        println!("cargo:rustc-link-lib=dylib=jnt");
    }
    let display = directory.to_str().expect("JOINTS_LIB_DIR must be UTF-8");
    println!("cargo:rustc-link-search=native={display}");
    // Cargo's test/doc executables need the same explicit directory used by
    // the linker; an installed consumer chooses its own runtime deployment.
    if kind == "dynamic" && matches!(target.as_str(), "macos" | "linux") {
        println!("cargo:rustc-link-arg=-Wl,-rpath,{display}");
    }
}
