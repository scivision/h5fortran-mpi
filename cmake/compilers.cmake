if(CMAKE_Fortran_COMPILER_ID STREQUAL GNU)
  string(APPEND CMAKE_Fortran_FLAGS_DEBUG " -Werror=array-bounds")
  string(APPEND CMAKE_Fortran_FLAGS_RELEASE " -fno-backtrace")
endif()
