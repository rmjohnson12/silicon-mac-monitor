# Changelog

## 1.0.3 — 2026-10-25

- Add a read-only HID thermal reader for recognized CPU/GPU services when the corresponding SMC temperature group is unavailable. The M1 Air report confirmed that the 1.0.2 SMC mapping alone did not restore its temperatures.
- Keep responding SMC groups unchanged; exclude battery/SOC/unknown HID labels and invalid readings from CPU/GPU averages. Reuse the HID client and re-discover services so later samples can recover after wake.
- Include sensor source and diagnostic details in snapshots: SMC key/read-format status, HID thermal product labels/values, missing events, and missing temperature groups. Add a process-free `--sensor-diagnostics` command.
- Expand deterministic regressions to 55 checks, including fallback behavior, duplicate filtering, missing events, source attribution and diagnostic serialization.

Live M3 Max SMC CPU/GPU readings passed regression diagnostics. The HID reader returned thermal services on that Mac, but none had recognized CPU/GPU labels; its existing SMC readings were preserved. Physical M1 CPU/GPU confirmation remains pending a 1.0.3 retest. Both hardware interfaces are undocumented/private and do not establish Mac App Store eligibility.

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
