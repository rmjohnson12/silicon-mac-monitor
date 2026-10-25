# Changelog

## 1.0.2 — 2026-10-25

- Add M1-family CPU/GPU sensor identifiers. Version 1.0.1 still fell back to legacy CPU probes on M1, so battery readings could appear while CPU/GPU temperatures were missing.
- Identify the reported M1 MacBook Air correctly in the sidebar instead of using a fixed MacBook Pro label. Use a generic Mac label for unknown product families.
- Show an explicit fanless message on the confirmed `MacBookAir10,1` model when no fan readings exist. Other models retain the unavailable message, and valid RPM readings remain visible.
- Add M1 sensor-selection, battery-only, chip-name, and hardware-identity regressions, bringing the suite to 40 checks.

Physical M1 CPU/GPU temperature confirmation requires a retest with this build. Automated M1 checks use synthetic SMC responses, and the supplied M1 report was captured with 1.0.1.

## 1.0.1 — 2026-10-25

- Add M2-family CPU/GPU sensor identifiers. Version 1.0 used legacy probes on an M2 and could show battery and fan readings while missing CPU/GPU temperatures.
- Re-probe temperature sensors each interval so an initially unavailable reading can recover.
- Include app version, hardware model, OS version, and core count in local snapshot exports. Serial numbers remain excluded.
- Add synthetic sensor-selection/recovery and export-metadata checks, bringing the regression suite to 32 checks.
- Create a versioned ZIP from the signed temporary app bundle for transferring test builds.

Live M3 Max regression checks passed. Physical M2 CPU/GPU temperature confirmation requires a retest with this build; the automated M2 checks use synthetic SMC responses.
