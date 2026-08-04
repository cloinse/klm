import os

application = os.path.abspath(defines["app"])  # noqa: F821
background_image = os.path.abspath(defines["background"])  # noqa: F821
application_name = os.path.basename(application)

format = "UDZO"
compression_level = 9
filesystem = "HFS+"

files = [application]
symlinks = {"Applications": "/Applications"}
hide_extensions = [application_name]

background = background_image
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((120, 120), (660, 420))
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 14
icon_size = 112
icon_locations = {
    application_name: (170, 210),
    "Applications": (490, 210),
}
