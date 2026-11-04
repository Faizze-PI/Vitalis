# HC-083: official, SHA-256-locked CPU runtime. No Python at build or runtime.
set(ORT_ROOT "${CMAKE_BINARY_DIR}/onnxruntime-1.24.4")
file(MAKE_DIRECTORY "${ORT_ROOT}/include")
function(ort_fetch URL FILE HASH)
  if(EXISTS "${FILE}")
    file(SHA256 "${FILE}" ACTUAL)
    if(ACTUAL STREQUAL HASH)
      return()
    endif()
  endif()
  file(DOWNLOAD "${URL}" "${FILE}.part" EXPECTED_HASH "SHA256=${HASH}"
    TLS_VERIFY ON TIMEOUT 600 STATUS FETCH_STATUS)
  list(GET FETCH_STATUS 0 FETCH_CODE)
  if(NOT FETCH_CODE EQUAL 0)
    message(FATAL_ERROR "Verified ONNX Runtime download failed: ${FETCH_STATUS}")
  endif()
  file(RENAME "${FILE}.part" "${FILE}")
endfunction()
ort_fetch("https://files.pythonhosted.org/packages/dd/59/8febe015f391aa1757fa5ba82c759ea4b6c14ef970132efb5e316665ba61/onnxruntime-1.24.4-cp311-cp311-win_amd64.whl" "${ORT_ROOT}/runtime.zip" "b43b63eb24a2bc8fc77a09be67587a570967a412cccb837b6245ccb546691153")
execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xf runtime.zip WORKING_DIRECTORY "${ORT_ROOT}" RESULT_VARIABLE EXTRACT_RESULT)
if(NOT EXTRACT_RESULT EQUAL 0)
  message(FATAL_ERROR "ONNX Runtime extraction failed")
endif()
ort_fetch("https://raw.githubusercontent.com/microsoft/onnxruntime/v1.24.4/include/onnxruntime/core/session/onnxruntime_cxx_api.h" "${ORT_ROOT}/include/onnxruntime_cxx_api.h" "5eb8809db561261210ffcafcf9823873f0603fd799542797b6b728bb3f75e5f6")
ort_fetch("https://raw.githubusercontent.com/microsoft/onnxruntime/v1.24.4/include/onnxruntime/core/session/onnxruntime_cxx_inline.h" "${ORT_ROOT}/include/onnxruntime_cxx_inline.h" "022f4559009a35b157bc05a1aae9a59a2603a17e535d9410a49d0f9187f18039")
ort_fetch("https://raw.githubusercontent.com/microsoft/onnxruntime/v1.24.4/include/onnxruntime/core/session/onnxruntime_c_api.h" "${ORT_ROOT}/include/onnxruntime_c_api.h" "9ed0d7054a4e74249467365b25b415d36f51a44a6349e2a994a1812e4723d1e2")
ort_fetch("https://raw.githubusercontent.com/microsoft/onnxruntime/v1.24.4/include/onnxruntime/core/session/onnxruntime_ep_c_api.h" "${ORT_ROOT}/include/onnxruntime_ep_c_api.h" "e94ac3490697bdb107844fa9d403952ee7136134132a057eae5c1207b57ce352")
ort_fetch("https://raw.githubusercontent.com/microsoft/onnxruntime/v1.24.4/include/onnxruntime/core/session/onnxruntime_float16.h" "${ORT_ROOT}/include/onnxruntime_float16.h" "88b242845d25981633a0bbd1c148e273cf8bfb016ea3f57c4af41a06530f72b0")
file(WRITE "${ORT_ROOT}/onnxruntime.def" "LIBRARY onnxruntime\nEXPORTS\nOrtGetApiBase\n")
get_filename_component(MSVC_BIN "${CMAKE_LINKER}" DIRECTORY)
execute_process(COMMAND "${MSVC_BIN}/lib.exe" /nologo "/def:${ORT_ROOT}/onnxruntime.def"
  /machine:x64 "/out:${ORT_ROOT}/onnxruntime.lib" RESULT_VARIABLE LIB_RESULT)
if(NOT LIB_RESULT EQUAL 0)
  message(FATAL_ERROR "ONNX Runtime import library creation failed")
endif()
add_library(vitalis_onnx SHARED IMPORTED GLOBAL)
set_target_properties(vitalis_onnx PROPERTIES
  IMPORTED_IMPLIB "${ORT_ROOT}/onnxruntime.lib"
  IMPORTED_LOCATION "${ORT_ROOT}/onnxruntime/capi/onnxruntime.dll"
  INTERFACE_INCLUDE_DIRECTORIES "${ORT_ROOT}/include")
install(FILES "${ORT_ROOT}/onnxruntime/capi/onnxruntime.dll"
  "${ORT_ROOT}/onnxruntime/capi/onnxruntime_providers_shared.dll"
  DESTINATION "$<TARGET_FILE_DIR:${BINARY_NAME}>" COMPONENT Runtime)
install(FILES "${ORT_ROOT}/onnxruntime/LICENSE" "${ORT_ROOT}/onnxruntime/ThirdPartyNotices.txt"
  DESTINATION "$<TARGET_FILE_DIR:${BINARY_NAME}>/licenses/onnxruntime" COMPONENT Runtime)
