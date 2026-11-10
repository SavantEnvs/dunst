// Fuzzes the value parsers behind every dunstrc setting and rule (colors, gradients, lengths,
// lists, times, paths, enums...). The first byte picks the setting, the rest is its value.
#include <stdint.h>
#include <glib.h>

#include "log.h"
#include "option_parser.h"
#include "rules.h"
#include "settings.h"
#include "settings_data.h"

// defined in option_parser.c, not exported through its header
bool set_setting(struct setting setting, char *value);
int set_rule_value(struct rule *r, struct setting setting, char *value);

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

        struct setting setting = allowed_settings[data[0] % G_N_ELEMENTS(allowed_settings)];
        char *value = g_strndup((const char *)data + 1, size - 1);

        if (setting.value != NULL) {
                set_setting(setting, value);
                // keep each input independent of the previous ones
                settings_free(&settings);
                set_defaults();
        } else {
                struct rule *r = rule_new("fuzz");
                set_rule_value(r, setting, value);
                g_slist_free_full(rules, (GDestroyNotify)rule_free);
                rules = NULL;
        }

        g_free(value);
        return 0;
}
