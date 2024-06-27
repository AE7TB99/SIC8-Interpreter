include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(SIC8_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(SIC8_setup_options)
  option(SIC8_ENABLE_HARDENING "Enable hardening" ON)
  option(SIC8_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    SIC8_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    SIC8_ENABLE_HARDENING
    OFF)

  SIC8_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR SIC8_PACKAGING_MAINTAINER_MODE)
    option(SIC8_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(SIC8_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(SIC8_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(SIC8_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(SIC8_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(SIC8_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(SIC8_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(SIC8_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(SIC8_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(SIC8_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(SIC8_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(SIC8_ENABLE_PCH "Enable precompiled headers" OFF)
    option(SIC8_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(SIC8_ENABLE_IPO "Enable IPO/LTO" ON)
    option(SIC8_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(SIC8_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(SIC8_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(SIC8_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(SIC8_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(SIC8_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(SIC8_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(SIC8_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(SIC8_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(SIC8_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(SIC8_ENABLE_PCH "Enable precompiled headers" OFF)
    option(SIC8_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      SIC8_ENABLE_IPO
      SIC8_WARNINGS_AS_ERRORS
      SIC8_ENABLE_USER_LINKER
      SIC8_ENABLE_SANITIZER_ADDRESS
      SIC8_ENABLE_SANITIZER_LEAK
      SIC8_ENABLE_SANITIZER_UNDEFINED
      SIC8_ENABLE_SANITIZER_THREAD
      SIC8_ENABLE_SANITIZER_MEMORY
      SIC8_ENABLE_UNITY_BUILD
      SIC8_ENABLE_CLANG_TIDY
      SIC8_ENABLE_CPPCHECK
      SIC8_ENABLE_COVERAGE
      SIC8_ENABLE_PCH
      SIC8_ENABLE_CACHE)
  endif()

  SIC8_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (SIC8_ENABLE_SANITIZER_ADDRESS OR SIC8_ENABLE_SANITIZER_THREAD OR SIC8_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(SIC8_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(SIC8_global_options)
  if(SIC8_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    SIC8_enable_ipo()
  endif()

  SIC8_supports_sanitizers()

  if(SIC8_ENABLE_HARDENING AND SIC8_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR SIC8_ENABLE_SANITIZER_UNDEFINED
       OR SIC8_ENABLE_SANITIZER_ADDRESS
       OR SIC8_ENABLE_SANITIZER_THREAD
       OR SIC8_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${SIC8_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${SIC8_ENABLE_SANITIZER_UNDEFINED}")
    SIC8_enable_hardening(SIC8_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(SIC8_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(SIC8_warnings INTERFACE)
  add_library(SIC8_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  SIC8_set_project_warnings(
    SIC8_warnings
    ${SIC8_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(SIC8_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    SIC8_configure_linker(SIC8_options)
  endif()

  include(cmake/Sanitizers.cmake)
  SIC8_enable_sanitizers(
    SIC8_options
    ${SIC8_ENABLE_SANITIZER_ADDRESS}
    ${SIC8_ENABLE_SANITIZER_LEAK}
    ${SIC8_ENABLE_SANITIZER_UNDEFINED}
    ${SIC8_ENABLE_SANITIZER_THREAD}
    ${SIC8_ENABLE_SANITIZER_MEMORY})

  set_target_properties(SIC8_options PROPERTIES UNITY_BUILD ${SIC8_ENABLE_UNITY_BUILD})

  if(SIC8_ENABLE_PCH)
    target_precompile_headers(
      SIC8_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(SIC8_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    SIC8_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(SIC8_ENABLE_CLANG_TIDY)
    SIC8_enable_clang_tidy(SIC8_options ${SIC8_WARNINGS_AS_ERRORS})
  endif()

  if(SIC8_ENABLE_CPPCHECK)
    SIC8_enable_cppcheck(${SIC8_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(SIC8_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    SIC8_enable_coverage(SIC8_options)
  endif()

  if(SIC8_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(SIC8_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(SIC8_ENABLE_HARDENING AND NOT SIC8_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR SIC8_ENABLE_SANITIZER_UNDEFINED
       OR SIC8_ENABLE_SANITIZER_ADDRESS
       OR SIC8_ENABLE_SANITIZER_THREAD
       OR SIC8_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    SIC8_enable_hardening(SIC8_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
