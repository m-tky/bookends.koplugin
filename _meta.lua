local _ = require("bookends_i18n").gettext
return {
    -- `name` removed -- deprecated in koreader/koreader#15096; the
    -- PluginLoader now uses the directory name ("bookends" here)
    -- for enabled/disabled tracking. Setting `name` here triggers a
    -- WARN on every plugin load in nightly builds.
    fullname = _("Bookends"),
    description = _([[Configurable text overlays at screen corners and edges with token expansion and icon support.]]),
    version = "5.14.1",
}
