# Changelog

## 1.0.1 — 2026-10-25

- Add M2-family CPU/GPU sensor identifiers. Version 1.0 used legacy probes on an M2 and could show battery and fan readings while missing CPU/GPU temperatures.
- Re-probe temperature sensors each interval so an initially unavailable reading can recover.
- Include app version, hardware model, OS version, and core count in local snapshot exports. Serial numbers remain excluded.
- Add synthetic sensor-selection/recovery and export-metadata checks, bringing the regression suite to 32 checks.
- Create a versioned ZIP from the signed temporary app bundle for transferring test builds.

Live M3 Max regression checks passed. Physical M2 CPU/GPU temperature confirmation requires a retest with this build; the automated M2 checks use synthetic SMC responses.
