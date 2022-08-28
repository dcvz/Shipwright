cmake_minimum_required (VERSION 3.10)

set(CMAKE_CXX_STANDARD 20 CACHE STRING "The C++ standard to use")

project (LUS)

add_subdirectory (libultraship)
add_subdirectory (ZAPDTR/ZAPDUtils)
add_subdirectory (example)
