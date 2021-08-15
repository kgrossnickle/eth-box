#----------------------------------------------------------------
# Generated CMake target import file for configuration "RelWithDebInfo".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "ethash::keccak" for configuration "RelWithDebInfo"
set_property(TARGET ethash::keccak APPEND PROPERTY IMPORTED_CONFIGURATIONS RELWITHDEBINFO)
set_target_properties(ethash::keccak PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELWITHDEBINFO "C"
  IMPORTED_LOCATION_RELWITHDEBINFO "${_IMPORT_PREFIX}/lib/keccak.lib"
  )

list(APPEND _IMPORT_CHECK_TARGETS ethash::keccak )
list(APPEND _IMPORT_CHECK_FILES_FOR_ethash::keccak "${_IMPORT_PREFIX}/lib/keccak.lib" )

# Import target "ethash::ethash" for configuration "RelWithDebInfo"
set_property(TARGET ethash::ethash APPEND PROPERTY IMPORTED_CONFIGURATIONS RELWITHDEBINFO)
set_target_properties(ethash::ethash PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELWITHDEBINFO "C;CXX"
  IMPORTED_LOCATION_RELWITHDEBINFO "${_IMPORT_PREFIX}/lib/ethash.lib"
  )

list(APPEND _IMPORT_CHECK_TARGETS ethash::ethash )
list(APPEND _IMPORT_CHECK_FILES_FOR_ethash::ethash "${_IMPORT_PREFIX}/lib/ethash.lib" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
