// Fuzzes the raw image-data hint of a notification (D-Bus "(iiibiiay)") as handled by
// icon_get_for_data(). Input layout (little-endian host order): width, height, rowstride (int32 each),
// has_alpha, bits_per_sample, n_channels, min_size, max_size, scale (one byte each), then the rest of
// the input as the pixel array. Nothing is normalised: dunst's own validation (dimensions, format,
// alpha mismatch, rowstride, length overflow/mismatch) has to accept or reject the fields.
#include <stdint.h>
#include <string.h>
#include <glib.h>
#include <gdk-pixbuf/gdk-pixbuf.h>

#include "icon.h"
#include "log.h"
#include "option_parser.h"
#include "settings.h"

#define HDR 18

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
        dunst_log_init(DUNST_LOG_NONE);
        set_defaults();
        return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
        if (size < HDR)
                return -1;

        int32_t width, height, rowstride;
        memcpy(&width, data, 4);
        memcpy(&height, data + 4, 4);
        memcpy(&rowstride, data + 8, 4);
        gboolean has_alpha = data[12] & 1;
        int bits_per_sample = data[13];
        int channels = data[14];
        int min_size = data[15];
        int max_size = data[16];
        double scale = 0.5 + data[17] / 64.0;

        GVariant *pixels = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, data + HDR, size - HDR, 1);
        GVariant *v = g_variant_ref_sink(g_variant_new("(iiibii@ay)", width, height, rowstride,
                                                       has_alpha, bits_per_sample, channels, pixels));

        char *id = NULL;
        GdkPixbuf *pb = icon_get_for_data(v, &id, scale, min_size, max_size);
        if (pb)
                g_object_unref(pb);
        g_free(id);
        g_variant_unref(v);
        return 0;
}
