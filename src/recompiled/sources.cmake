# DMC4 Recompiled Game Sources
# Automatically includes all C/C++ translation units placed in this folder.
file(GLOB_RECURSE DMC4_GAME_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_LIST_DIR}/*.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/*.c"
)
