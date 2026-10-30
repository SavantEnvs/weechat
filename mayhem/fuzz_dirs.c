#include <stdlib.h>
#include <string.h>

extern char *weechat_config_dir, *weechat_data_dir, *weechat_state_dir,
    *weechat_cache_dir, *weechat_runtime_dir;

/* weechat_init_directories() sets these before anything is evaluated in a real weechat; the harnesses
 * never call it, so ${weechat_*_dir} would strdup(NULL). Nothing is ever written under them. */
__attribute__((constructor)) static void
fuzz_init_dirs (void)
{
    if (!weechat_config_dir)  weechat_config_dir  = strdup ("/tmp/weechat-fuzz/config");
    if (!weechat_data_dir)    weechat_data_dir    = strdup ("/tmp/weechat-fuzz/data");
    if (!weechat_state_dir)   weechat_state_dir   = strdup ("/tmp/weechat-fuzz/state");
    if (!weechat_cache_dir)   weechat_cache_dir   = strdup ("/tmp/weechat-fuzz/cache");
    if (!weechat_runtime_dir) weechat_runtime_dir = strdup ("/tmp/weechat-fuzz/runtime");
}
