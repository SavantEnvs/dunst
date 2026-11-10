// Fuzzes the notification body markup transforms (no/strip/full markup, with and without ignore_newline).
#include <stdint.h>
#include <glib.h>

#include "log.h"
#include "markup.h"
#include "option_parser.h"
#include "settings.h"

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
        dunst_log_init(DUNST_LOG_NONE);
        set_defaults();
        return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
        if (size < 1)
                return -1;

        // Notification text arrives from D-Bus as a GVariant 's', which is always valid UTF-8.
        if (!g_utf8_validate((const char *)data + 1, size - 1, NULL))
                return -1;

        enum markup_mode mode = MARKUP_NO + (data[0] % 3);
        settings.ignore_newline = (data[0] >> 2) & 1;

        char *text = g_strndup((const char *)data + 1, size - 1);
        char *out = markup_transform(text, mode); // takes ownership of text
        g_free(out);
        return 0;
}
