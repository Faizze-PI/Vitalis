#include "onnx_task_engine.h"
#include <windows.h>
#include <bcrypt.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <onnxruntime_cxx_api.h>
#include <algorithm>
#include <cmath>
#include <climits>
#include <fstream>
#include <limits>
#include <regex>
#include <set>

// HC-083: CPU-only Windows adapter for the existing bounded HC-078 task contract.
namespace vitalis::tasks {
namespace {
void Require(bool ok, const char* code) { if (!ok) throw Failure{code}; }
bool Identity(const std::string& id) {
  return std::regex_match(id, std::regex("[a-f0-9]{32}"));
}
void OrdinaryPath(const std::filesystem::path& path) {
  Require(path.is_absolute(), "fileUnavailable");
  for (auto current = path; !current.empty(); current = current.parent_path()) {
    const auto attributes = GetFileAttributesW(current.c_str());
    Require(attributes != INVALID_FILE_ATTRIBUTES &&
        !(attributes & FILE_ATTRIBUTE_REPARSE_POINT), "fileUnavailable");
    if (current == current.root_path()) break;
  }
  Require(std::filesystem::is_regular_file(path), "fileUnavailable");
}
std::filesystem::path Model(const Request& request) {
  Require(request.model_id.empty() != request.package_id.empty(), "fileIdentity");
  if (!request.model_id.empty()) return OwnedInput(request.root, request.model_id);
  Require(Identity(request.package_id), "fileIdentity");
  auto directory = request.root / L"algorithm_packages" / request.package_id;
  OrdinaryPath(directory / L"ready.json");
  auto model = directory / L"model.blob";
  OrdinaryPath(model);
  return model;
}
std::string Hash(const std::vector<uint8_t>& bytes) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  Require(BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM,
      nullptr, 0) == 0, "hashUnavailable");
  unsigned char digest[32]{};
  const auto status = BCryptHash(algorithm, nullptr, 0,
      const_cast<PUCHAR>(bytes.data()), static_cast<ULONG>(bytes.size()),
      digest, sizeof(digest));
  BCryptCloseAlgorithmProvider(algorithm, 0);
  Require(status == 0, "hashUnavailable");
  const char* hex = "0123456789abcdef";
  std::string result;
  for (auto value : digest) { result += hex[value >> 4]; result += hex[value & 15]; }
  return result;
}
std::vector<uint8_t> ReadModel(const std::filesystem::path& path,
                             uint64_t budget, Control& control) {
  const auto size = std::filesystem::file_size(path);
  Require(size > 0 && size <= budget && size <= ULONG_MAX, "memoryBudget");
  std::vector<uint8_t> bytes(static_cast<size_t>(size));
  std::ifstream input(path, std::ios::binary);
  for (size_t offset = 0; offset < bytes.size();) {
    control.Check();
    const auto count = std::min<size_t>(8192, bytes.size() - offset);
    input.read(reinterpret_cast<char*>(bytes.data() + offset), count);
    Require(input.gcount() == static_cast<std::streamsize>(count), "fileChanged");
    offset += count;
  }
  Require(input.peek() == std::char_traits<char>::eof(), "fileChanged");
  return bytes;
}
void HResult(HRESULT value) { Require(SUCCEEDED(value), "invalidImage"); }
std::vector<float> Image(const Request& request, uint64_t budget, Control& control) {
  using Microsoft::WRL::ComPtr;
  const auto& spec = request.image;
  Require(request.shape.size() == 4 && request.shape[0] == 1 &&
      (spec.layout == "NHWC" || spec.layout == "NCHW") &&
      spec.mean.size() == 3 && spec.deviation.size() == 3 &&
      std::isfinite(spec.scale) && spec.scale > 0, "imageContract");
  const bool nhwc = spec.layout == "NHWC";
  Require(request.shape[nhwc ? 3 : 1] == 3, "imageContract");
  const auto height = request.shape[nhwc ? 1 : 2];
  const auto width = request.shape[nhwc ? 2 : 3];
  Require(height > 0 && width > 0 && height <= UINT_MAX && width <= UINT_MAX &&
      static_cast<uint64_t>(width) <= budget / 3 / sizeof(float) / height,
      "memoryBudget");
  for (size_t i = 0; i < 3; ++i)
    Require(std::isfinite(spec.mean[i]) && std::isfinite(spec.deviation[i]) &&
        spec.deviation[i] > 0, "imageContract");
  const auto input = OwnedInput(request.root, request.input_id);
  const auto initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  Require(SUCCEEDED(initialized), "imageUnavailable");
  struct Apartment { ~Apartment() { CoUninitialize(); } } apartment;
  ComPtr<IWICImagingFactory> factory;
  HResult(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(&factory)));
  ComPtr<IWICBitmapDecoder> decoder;
  HResult(factory->CreateDecoderFromFilename(input.c_str(), nullptr, GENERIC_READ,
      WICDecodeMetadataCacheOnDemand, &decoder));
  GUID container{};
  HResult(decoder->GetContainerFormat(&container));
  Require(container == GUID_ContainerFormatPng || container == GUID_ContainerFormatJpeg,
      "imageFormat");
  UINT frames = 0;
  HResult(decoder->GetFrameCount(&frames));
  Require(frames == 1, "imageFrames");
  ComPtr<IWICBitmapFrameDecode> frame;
  HResult(decoder->GetFrame(0, &frame));
  UINT source_width = 0, source_height = 0;
  HResult(frame->GetSize(&source_width, &source_height));
  Require(source_width > 0 && source_height > 0 &&
      source_width <= budget / 4 / source_height, "memoryBudget");
  ComPtr<IWICFormatConverter> converter;
  HResult(factory->CreateFormatConverter(&converter));
  HResult(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppRGBA,
      WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom));
  const auto source_bytes = static_cast<size_t>(source_width) * source_height * 4;
  Require(source_bytes <= UINT_MAX, "memoryBudget");
  std::vector<uint8_t> pixels(source_bytes);
  HResult(converter->CopyPixels(nullptr, source_width * 4,
      static_cast<UINT>(pixels.size()), pixels.data()));
  const auto plane = static_cast<size_t>(width * height);
  std::vector<float> values(plane * 3);
  for (int64_t y = 0; y < height; ++y) {
    control.Check();
    // Matches the Android adapter: nearest source pixel, no EXIF rotation.
    const auto sy = static_cast<uint64_t>(y) * source_height / height;
    for (int64_t x = 0; x < width; ++x) {
      const auto sx = static_cast<uint64_t>(x) * source_width / width;
      const auto offset = static_cast<size_t>((sy * source_width + sx) * 4);
      Require(pixels[offset + 3] == 255, "imageAlpha");
      for (size_t channel = 0; channel < 3; ++channel) {
        const auto value = static_cast<float>(
            (pixels[offset + channel] * spec.scale - spec.mean[channel]) /
            spec.deviation[channel]);
        Require(std::isfinite(value), "nonFiniteInput");
        const auto index = static_cast<size_t>(y * width + x);
        values[nhwc ? index * 3 + channel : channel * plane + index] = value;
      }
    }
  }
  return values;
}
}  // namespace

void Control::Check() const { if (cancelled.load()) throw Failure{"cancelled"}; }
void Control::Cancel() {
  std::lock_guard<std::mutex> lock(mutex);
  cancelled.store(true);
  if (run_options != nullptr) static_cast<Ort::RunOptions*>(run_options)->SetTerminate();
}
uint64_t AllocationBudget() {
  MEMORYSTATUSEX memory{};
  memory.dwLength = sizeof(memory);
  Require(GlobalMemoryStatusEx(&memory) && memory.ullAvailPhys > 0, "memoryBudget");
  return std::min<uint64_t>(memory.ullAvailPhys / 4, INT_MAX);
}
std::filesystem::path OwnedInput(const std::filesystem::path& root,
                                const std::string& id) {
  Require(Identity(id), "fileIdentity");
  auto file = root / L"input_workspace" / (id + ".blob");
  OrdinaryPath(file);
  return file;
}
std::vector<Output> Run(const Request& request, Control& control) {
  control.Check();
  const auto budget = AllocationBudget();
  const auto model = Model(request);
  Require(std::regex_match(request.hash, std::regex("[a-f0-9]{64}")), "hashRequired");
  auto bytes = ReadModel(model, budget, control);
  Require(Hash(bytes) == request.hash, "hashMismatch");
  control.Check();
  uint64_t count = 1;
  Require(!request.shape.empty() && !request.outputs.empty() &&
      std::set<std::string>(request.outputs.begin(), request.outputs.end()).size() ==
          request.outputs.size(), "inputContract");
  for (auto dimension : request.shape) {
    Require(dimension > 0 && static_cast<uint64_t>(dimension) <= budget / sizeof(float) / count,
        "memoryBudget");
    count *= dimension;
  }
  auto values = request.kind == "image" ? Image(request, budget, control) : request.values;
  Require((request.kind == "csv" || request.kind == "image") && count == values.size(),
      "inputContract");
  for (auto value : values) Require(std::isfinite(value), "nonFiniteInput");
  static Ort::Env environment([] {
    Ort::Env env(ORT_LOGGING_LEVEL_FATAL, "vitalis-tasks");
    env.DisableTelemetryEvents(); return env;
  }());
  Ort::SessionOptions options;
  options.SetIntraOpNumThreads(1);
  options.SetInterOpNumThreads(1);
  options.DisableMemPattern();
  options.DisableCpuMemArena();
  Ort::Session session(environment, bytes.data(), bytes.size(), options);
  control.Check();
  Ort::AllocatorWithDefaultOptions allocator;
  Require(session.GetInputCount() == 1 &&
      std::string(session.GetInputNameAllocated(0, allocator).get()) == request.input_name,
      "inputContract");
  const auto type = session.GetInputTypeInfo(0);
  const auto info = type.GetTensorTypeAndShapeInfo();
  Require(info.GetElementType() == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, "inputContract");
  const auto shape = info.GetShape();
  Require(shape.size() == request.shape.size(), "inputShape");
  for (size_t i = 0; i < shape.size(); ++i)
    Require(shape[i] <= 0 || shape[i] == request.shape[i], "inputShape");
  auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
  auto tensor = Ort::Value::CreateTensor<float>(memory, values.data(), values.size(),
      request.shape.data(), request.shape.size());
  const char* input_name = request.input_name.c_str();
  std::vector<const char*> names;
  for (const auto& name : request.outputs) names.push_back(name.c_str());
  Ort::RunOptions run;
  {
    std::lock_guard<std::mutex> lock(control.mutex);
    control.run_options = &run;
    if (control.cancelled.load()) run.SetTerminate();
  }
  struct Detach {
    Control& control;
    ~Detach() { std::lock_guard<std::mutex> lock(control.mutex); control.run_options = nullptr; }
  } detach{control};
  try {
    control.Check();
    auto result = session.Run(run, &input_name, &tensor, 1, names.data(), names.size());
    control.Check();
    std::vector<Output> outputs;
    auto remaining = budget / sizeof(float);
    for (size_t i = 0; i < result.size(); ++i) {
      Require(result[i].IsTensor(), "outputType");
      auto output_info = result[i].GetTensorTypeAndShapeInfo();
      Require(output_info.GetElementType() == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, "outputType");
      const auto size = output_info.GetElementCount();
      Require(size <= remaining, "outputBudget");
      remaining -= size;
      const auto* data = result[i].GetTensorData<float>();
      outputs.push_back({request.outputs[i], output_info.GetShape(),
          std::vector<float>(data, data + size)});
    }
    control.Check();
    return outputs;
  } catch (const Ort::Exception&) { control.Check(); throw Failure{"executionFailed"}; }
}
}  // namespace vitalis::tasks
