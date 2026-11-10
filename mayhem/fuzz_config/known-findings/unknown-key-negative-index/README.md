# save_settings() indexes allowed_settings[-1] for any unknown key

`src/option_parser.c:546` (`save_settings`) copies `allowed_settings[setting_id]` *before* checking
`setting_id < 0`. `get_setting_id()` returns -1 (unknown key), -2 (key in the wrong section), so any
dunstrc with a typo'd or misplaced key reads one `struct setting` in front of the table.

- Impact: out-of-bounds read of static data (ASan: global-buffer-overflow; UBSan: array-bounds). The
  value is discarded afterwards, so it is a harmless over-read in practice, but it aborts every
  sanitized run on common configs.
- Reproducer: `repro.ini` (`[global]` + unknown key), also upstream's own `test/data/test-ini`.
- Fix: move the `struct setting curr_setting = allowed_settings[setting_id];` line below the
  `if (setting_id < 0) {...continue;}` block.

The reproducers are kept out of `testsuite/` because seeds are replayed on every run.
