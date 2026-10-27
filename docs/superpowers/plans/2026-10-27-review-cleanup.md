# Project review and documentation cleanup

**Goal:** Review the current app, remove confirmed rollback leftovers and unhelpful comments, and replace outdated README content with verified setup and usage instructions.

**Base:** `e54ba96` on `main`.

**Constraints:** Keep the accepted screens and interactions. Do not exercise school write endpoints, submit applications, or make payments. Preserve comments explaining security boundaries, cancellation, persistence, and platform workarounds. Record behavior changes separately from cleanup. Do not merge this review branch without a new request.

- [ ] Review authentication/payment, academic/campus state, UI infrastructure, build workflows, scripts, and the Flutter prototype. Report reproducible defects separately from structural recommendations.
- [ ] Remove unreachable wallet/printing and unused meter artwork/components after checking source, project, tests, and workflow references. Trim redundant comments without changing behavior.
- [ ] Install and apply `github/awesome-copilot`'s `create-readme` skill. Rewrite the root README for app users and `ios/README.md` for developers; use verified features, build commands, and synthetic screenshots.
- [ ] Run local syntax, offline regressions, reference checks, and native CI. Review the final diff and document remaining risks with file/line evidence.
