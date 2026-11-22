# Layout of the install window, read by dmgbuild
# (https://dmgbuild.readthedocs.io). dmgbuild writes the window's settings
# itself, without asking Finder, so it works on a build machine with no
# screen. Built by Support/make-dmg.sh.
#
# The background is drawn by Support/make-art.swift. KEEP IN SYNC with it: the
# arrow there sits between the two icons placed here.

import os

# dmgbuild provides `defines`: the -D options of Support/make-dmg.sh.
app = defines["app"]  # noqa: F821
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}

# The disk shows the app's own icon in Finder and on the desktop.
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

# dmgbuild also picks up background@2x.png next to this file for Retina.
background = os.path.join(defines["art"], "background.png")  # noqa: F821

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

# The window's content is 660 x 420 points, the size of the background.
window_rect = ((240, 180), (660, 420))

arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    app_name: (170, 200),
    "Applications": (490, 200),
}
