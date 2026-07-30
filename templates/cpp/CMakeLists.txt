cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON) # clangd reads this straight from build/

add_executable(app src/main.cpp)

find_package(Catch2 3 REQUIRED)
add_executable(tests tests/test_basic.cpp)
target_include_directories(tests PRIVATE src)
target_link_libraries(tests PRIVATE Catch2::Catch2WithMain)

include(CTest)
include(Catch)
catch_discover_tests(tests)
