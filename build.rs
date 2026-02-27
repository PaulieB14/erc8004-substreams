fn main() {
    substreams_ethereum::Abigen::new("IdentityRegistry", "abi/identity_registry.json")
        .expect("Failed to load IdentityRegistry ABI")
        .generate()
        .expect("Failed to generate IdentityRegistry bindings")
        .write_to_file("src/abi/identity_registry.rs")
        .expect("Failed to write IdentityRegistry bindings");

    substreams_ethereum::Abigen::new("ReputationRegistry", "abi/reputation_registry.json")
        .expect("Failed to load ReputationRegistry ABI")
        .generate()
        .expect("Failed to generate ReputationRegistry bindings")
        .write_to_file("src/abi/reputation_registry.rs")
        .expect("Failed to write ReputationRegistry bindings");
}
