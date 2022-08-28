
add_executable (example main.cpp)

target_link_libraries (example LINK_PUBLIC libultraship)

target_include_directories(example PRIVATE assets
    ${CMAKE_CURRENT_SOURCE_DIR}/..
    ${CMAKE_CURRENT_SOURCE_DIR}/../libultraship/Lib/
	${CMAKE_CURRENT_SOURCE_DIR}/../libultraship/Lib/libjpeg/include/
	${CMAKE_CURRENT_SOURCE_DIR}/../libultraship/Lib/spdlog/include/
    ${CMAKE_CURRENT_SOURCE_DIR}/../libultraship/Lib/Fast3D/U64/PR
	${CMAKE_CURRENT_SOURCE_DIR}/../ZAPDTR/ZAPDUtils
)
