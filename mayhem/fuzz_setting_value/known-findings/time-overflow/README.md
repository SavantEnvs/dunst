# string_to_time() overflows a signed gint64 on a huge value

`string_to_time()` (`src/utils.c`) parses the number with `strtol()` and then multiplies it by the unit
(`val * 1000`, `S2US(val)` = `val * G_USEC_PER_SEC`, then `* 60`, `* 60 * 60`, `* 60 * 60 * 24`) without
checking the range. A value such as `9223372036854775807s` overflows `gint64`, which halting UBSan
reports as signed integer overflow at `src/utils.c:286`, `299`, `301`, `303`, `305` or `307`
depending on the suffix.

- Impact: undefined behaviour (signed overflow) in any `TYPE_TIME` setting or rule value: `timeout`,
  `idle_threshold`, `show_age_threshold`, `override_dbus_timeout`, `match_dbus_timeout`. In practice the
  stored timeout wraps to an arbitrary or negative number.
- Reproducer: `repro.bin` is the harness input (first byte = setting index 25, `timeout`; rest = value
  `9223372036854775807s`); run `fuzz_setting_value-standalone repro.bin`.
- Fix: range-check `val` against `G_MAXINT64 / multiplier` before multiplying, or use
  `g_ascii_strtoll()` plus `__builtin_mul_overflow()`, and set `errno = ERANGE` on overflow.
