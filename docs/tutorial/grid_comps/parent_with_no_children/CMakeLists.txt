esma_set_this (OVERRIDE MAPL.parent_no_children)
set (srcs
    ParentNoChildren_GridComp.F90
    )

esma_add_library (${this} SRCS ${srcs} DEPENDENCIES MAPL.shared MAPL TYPE ${MAPL_LIBRARY_TYPE})
if (NOT CMAKE_Fortran_COMPILER_ID MATCHES "NAG")
  target_link_libraries(${this} PRIVATE OpenMP::OpenMP_Fortran)
endif ()
target_link_libraries(${this} PRIVATE esmf)
target_include_directories (${this} PUBLIC $<BUILD_INTERFACE:${MAPL_SOURCE_DIR}/include>)
set_target_properties (${this} PROPERTIES Fortran_MODULE_DIRECTORY ${include_${this}})
#target_compile_definitions(${this} PRIVATE SYSTEM_DSO_SUFFIX="${CMAKE_SHARED_LIBRARY_SUFFIX}")
