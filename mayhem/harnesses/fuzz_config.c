// Fuzzes a whole dunstrc: INI parsing followed by save_settings(), which turns sections into
// global settings and notification rules.
#include <stdint.h>
#include <stdio.h>
#include <glib.h>

#include "ini.h"
#include "log.h"
#include "option_parser.h"
#include "rules.h"
#include "settings.h"

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
        dunst_log_init(DUNST_LOG_NONE);
        set_defaults();
        return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
        if (size == 0)
                return -1; // fmemopen() rejects a zero-length buffer

        FILE *fp = fmemopen((void *)data, size, "r");
        if (!fp)
                return -1;

        struct ini *ini = load_ini_file(fp);
        fclose(fp);
        if (!ini)
                return 0;

        save_settings(ini);

        finish_ini(ini);
        g_free(ini);

        // keep each input independent of the previous ones
        g_slist_free_full(rules, (GDestroyNotify)rule_free);
        rules = NULL;
        settings_free(&settings);
        set_defaults();
        return 0;
}
