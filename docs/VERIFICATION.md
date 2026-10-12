# Local verification record

Verified on 2026-10-12 with Foundry 1.8.3 and Solidity 0.8.26, using the
committed `foundry.toml` settings. This record reports contributor checks;
it is not an independent audit or launch admission.

| Check | Result |
| --- | --- |
| `forge build` | Pass |
| `forge build --offline` | Pass |
| `forge test --offline` | 42 passed, 0 failed, 0 skipped, across 7 suites |
| `forge fmt --check` | Pass |
| `python3 scripts/export_abis.py --check` | Both ABI exports match compiler artifacts |
| Fuzz tests | 512 cases each across 4 fuzz functions |
| Stateful invariant | 128 runs, 8,192 mixed calls, 0 unexpected reverts; final full withdrawals pass |
| Clean-copy offline build | Pass with only deliverable files, no cache, scratch tests or supplied inputs |
| Clean-copy parallel tests | 42 passed with `--threads 4`, after clearing the environment except executable search path |
| Reproducibility | Creation bytecode, runtime templates and ABIs exactly match between workspace and clean-copy builds |
| Art samples | Strict base64, JSON and SVG XML parsing pass; Dormant colors are greyscale and animation is absent |
| Library linking | No external library link references in either deployed contract |

Runtime sizes: `LaunchToken` **1,503 bytes**, `PulseDrone` **15,568 bytes**;
both below EIP-170's 24,576-byte limit. Constructor sizes are 2,438 and 16,492
bytes respectively. The deployment test executes both constructors through a
local factory, verifies that all launch supply remains with it, and scans actual
deployed runtimes for `DELEGATECALL`, `CALLCODE` and `SELFDESTRUCT`, skipping PUSH
data in the same way as the supplied launch baseline.

The supplied protected tests were read as acceptance definitions. They require
the service's launch environment and were not represented as executed here.
`test/Deployment.t.sol` and `test/LaunchToken.t.sol` independently exercise the
relevant baseline behavior without environment variables or external services.

Compiler/lint observations and their intentional uses are documented in the
README. Slither and Mythril were not available and were not run. No deployment,
broadcast, chain fork, funded wallet or external RPC was used. The separate
contributor's manifest and independent source/manifest review are still required
before the services release the project.
