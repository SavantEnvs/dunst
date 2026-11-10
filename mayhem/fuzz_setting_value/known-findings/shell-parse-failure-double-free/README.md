# TYPE_PATH settings free argv, then leave it dangling when g_shell_parse_argv() fails

`set_from_string()` (`src/option_parser.c`, `case TYPE_PATH`) calls `g_strfreev(*parser_data)` and then
`g_shell_parse_argv(..., parser_data, ...)`. When the value is not parseable shell text (empty, only a
`#` comment, unbalanced quote) glib leaves the output pointer untouched, so `settings.dmenu_cmd` /
`settings.browser_cmd` still points at the array that was just freed.

- Impact: use-after-free / double free on the next `settings_free()` (config reload, shutdown) or the
  next use of the command. Reachable with `dmenu =` or `browser = "` in dunstrc after the defaults set them.
- Reproducer: `repro.bin` is the harness input (first byte = setting index 78, rest = value);
  run `fuzz_setting_value-standalone repro.bin`.
- Fix: set `*parser_data = NULL` after the `g_strfreev()`.
