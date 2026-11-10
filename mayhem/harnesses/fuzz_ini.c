// Fuzzes dunst's INI config reader (load_ini_file) and the accessors that walk the result.
#include <stdint.h>
#include <stdio.h>
#include <glib.h>

#include "ini.h"
#include "log.h"

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
        dunst_log_init(DUNST_LOG_NONE);
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

        for (const char *s = next_section(ini, NULL); s; s = next_section(ini, s)) {
                (void)get_value(ini, s, "format");
                (void)get_value(ini, s, "foreground");
        }

        finish_ini(ini);
        g_free(ini);
        return 0;
}
