# Vendored dependencies

All dependencies required by `forge build` and `forge test` are ordinary source
files under `lib/`. Neither network access nor a package installation is required
by the verifier. The environment must provide Foundry and Solidity **0.8.26**.
No submodules or compiler binaries are included.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | [v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | The 19 Solidity files in the transitive import closure of ERC20, ERC721, SafeERC20, ReentrancyGuard, Base64 and Strings | `lib/openzeppelin-contracts/LICENSE` (MIT) |
| forge-std | [v1.9.6](https://github.com/foundry-rs/forge-std/tree/v1.9.6) | The upstream `src/` directory | `lib/forge-std/LICENSE-MIT` and `LICENSE-APACHE` |

Downloaded release archives, before selecting files:

- `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2`
  SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`
- `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.6`
  SHA-256: `53d2b498183cb7dc62cf726cc6c1a222ad728b0d87976a877ca1f3ed3707b1c6`

The selected upstream files are unmodified. There is no npm dependency. The ABI
export helper uses only Python's standard library.
