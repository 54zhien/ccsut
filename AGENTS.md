# iOS UI requirements

These project conventions record the user's requirements of 2026-10-26.

- Before adding or changing a control, consult the current Apple Developer
  documentation for the APIs and interaction being implemented. Record the
  relevant official references with the change; do not call an unchecked custom
  implementation an Apple-recommended pattern.
- Use native Liquid Glass whenever an applicable system style is available,
  including `.glass` and `.glassProminent`. Prefer native system controls,
  standard menus, sheets and SF Symbols.
  Keep content surfaces legible and avoid decorative glass layers that interfere
  with the system's material or scroll-edge behavior.
- Follow explicit page-specific refinements: keep elective controls restrained
  rather than making every control glass; score/exam filter circles match the
  neutral back control; campus add circles use theme-tinted glass. Use semantic
  light/dark colors for content such as the meter, with dark styling only in dark
  mode. These choices override the general glass preference for those surfaces.
- Implement only the UI scope explicitly requested by the user. Preserve other
  accepted layouts, animations, branding and business behavior.
- When concentric alignment is requested, use public container-corner geometry
  and measured rendered control dimensions, accounting for actual safe areas.
  Do not substitute fixed padding and claim exact physical alignment.
- Check relevant light/dark appearance, Dynamic Type, Reduce Motion and native
  interaction. Report source review, compilation, simulator verification and
  physical-device acceptance as separate evidence.
