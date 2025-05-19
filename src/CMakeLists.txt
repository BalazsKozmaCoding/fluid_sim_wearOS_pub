# Minimum CMake version required
cmake_minimum_required(VERSION 3.10)

# Project name (can be anything, used internally by CMake)
project(simulation_native LANGUAGES CXX)

# --- Find OpenMP ---
find_package(OpenMP REQUIRED)

# Add the C++ source file to a variable
# *** IMPORTANT: Rename your source file to simulation_native.cpp ***
# *** OR change this line to match your actual filename (e.g., simulation_native_vectorized.cpp) ***
set(SOURCE_FILES simulation_native.cpp) 

# Set C++ standard to C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Define the target: a SHARED library named "simulation_native_optimized"
# *** Ensure this library name matches what your Dart FFI expects ***
add_library(simulation_native SHARED ${SOURCE_FILES})

# --- Find NDK Libraries ---
# Find the logging library (common requirement)
find_library(log-lib log)

# --- Link Libraries ---
target_link_libraries( # Specifies the target library.
                       simulation_native
                       # Link OpenMP flags and libraries
                       PUBLIC OpenMP::OpenMP_CXX
                       # Links the logging library.
                       ${log-lib} )

# --- Compiler Optimizations ---
# Apply optimization flags specifically to our library target
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    # -O3: Aggressive optimization
    # -ffast-math: Allow optimizations that might break strict IEEE 754 compliance
    # -fPIC: Position Independent Code (required for shared libraries)
    # Add OpenMP flags explicitly here as well for clarity/older CMake versions? (Optional, target_link usually handles it)
    # target_compile_options(simulation_native PRIVATE -fopenmp) # Usually not needed with target_link_libraries(OpenMP::OpenMP_CXX)
    target_compile_options(simulation_native PRIVATE $<$<CONFIG:Release>:-O3> $<$<CONFIG:Release>:-ffast-math> -fPIC)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
    # Add MSVC specific flags if needed (less common for Android NDK)
    target_compile_options(simulation_native PRIVATE $<$<CONFIG:Release>:/O2> $<$<CONFIG:Release>:/fp:fast>)
    # OpenMP flags for MSVC if necessary: /openmp
    # target_compile_options(simulation_native PRIVATE /openmp) 
endif()

# Android specific settings (ABI, platform version) are typically handled by Gradle/NDK