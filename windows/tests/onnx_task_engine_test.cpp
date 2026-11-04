#include "../runner/onnx_task_engine.h"
#include <cmath>
#include <fstream>
#include <iostream>
#include <windows.h>

using namespace vitalis::tasks;
static void Require(bool ok) { if (!ok) throw Failure{"testAssertion"}; }
template<class F> void Reject(F action, const char* code) {
  try { action(); } catch (const Failure& e) { Require(e.code == code); return; }
  throw Failure{"expectedRejection"};
}
int wmain(int argc, wchar_t** argv) {
  try {
    Require(argc == 2 || argc == 3);
    const std::filesystem::path fixtures(argv[1]);
    const auto root = fixtures / (L"windows-owned-test-" + std::to_wstring(GetCurrentProcessId()));
    Require(!std::filesystem::exists(root));
    struct Cleanup { std::filesystem::path path; ~Cleanup() {
      std::error_code ignored; std::filesystem::remove_all(path, ignored);
    } } cleanup{root};
    std::filesystem::create_directories(root / L"input_workspace");
    const std::string id(32, 'a');
    Reject([&] { OwnedInput(root, "../outside"); }, "fileIdentity");
    Reject([&] { OwnedInput(root, id); }, "fileUnavailable");
    Control cancelled;
    cancelled.Cancel();
    Request request;
    Reject([&] { Run(request, cancelled); }, "cancelled");
    std::filesystem::copy_file(fixtures / L"csv_sum.onnx",
      root / L"input_workspace" / (id + ".blob"),
      std::filesystem::copy_options::overwrite_existing);
    request.root = root;
    request.model_id = id;
    request.kind = "csv";
    request.input_name = "features";
    request.shape = {3, 2};
    request.values = {1, 2, -1, 3, 0, 0};
    request.outputs = {"prediction"};
    std::ifstream hash_file(fixtures / L"csv_sum.sha256");
    hash_file >> request.hash;
    Control control;
    auto bad_hash = request;
    bad_hash.hash = std::string(64, '0');
    Reject([&] { Run(bad_hash, control); }, "hashMismatch");
    auto bad_shape = request;
    bad_shape.shape = {6, 1};
    Reject([&] { Run(bad_shape, control); }, "inputShape");
    const auto result = Run(request, control);
    Require(result.size() == 1 && result[0].values == std::vector<float>({3, 2, 0}));
    const std::string image_id(32, 'b');
    std::filesystem::copy_file(fixtures / L"image_mean_rgb.onnx",
      root / L"input_workspace" / (id + ".blob"), std::filesystem::copy_options::overwrite_existing);
    std::filesystem::copy_file(fixtures / L"input.png", root / L"input_workspace" / (image_id + ".blob"));
    request.kind = "image";
    request.input_id = image_id;
    request.input_name = "image";
    request.shape = {1, 3, 2, 2};
    request.outputs = {"mean_rgb"};
    request.hash = "26904e58ee126cae50d69479be86d5fcd2e7aab24ec866e334b735fa0bc61277";
    request.image = {"NCHW", 1.0 / 255, {0, 0, 0}, {1, 1, 1}};
    Require(Run(request, control)[0].values == std::vector<float>({.5f, .25f, .25f}));
    if (argc == 3) {
      const std::filesystem::path demo(argv[2]);
      std::filesystem::copy_file(demo / L"model.onnx", root / L"input_workspace" / (id + ".blob"),
        std::filesystem::copy_options::overwrite_existing);
      request.input_name = "input";
      request.shape = {1, 224, 224, 3};
      request.outputs = {"dense_2"};
      request.hash = "e6364c7a3c301b1b356415977f244fe1a0911f275c399fb14e9f918cbf986a88";
      request.image = {"NHWC", 1, {0, 0, 0}, {1, 1, 1}};
      const std::vector<std::vector<float>> expected = {
        {.9989776611f, .0008800498f, .0000487977f, .0000935463f},
        {.0202770457f, .0053196964f, .9741971493f, .0002061551f}};
      size_t sample = 0;
      for (const auto* name : {L"glioma.png", L"no-tumor.png"}) {
        std::filesystem::copy_file(demo / name, root / L"input_workspace" / (image_id + ".blob"),
          std::filesystem::copy_options::overwrite_existing);
        const auto actual = Run(request, control)[0].values;
        Require(actual.size() == 4);
        float difference = 0;
        for (size_t i = 0; i < actual.size(); ++i)
          difference = std::max(difference, std::abs(actual[i] - expected[sample][i]));
        Require(difference <= .0001f);
        std::cout << "PASS image parity sample " << sample++ << " max_abs_diff=" << difference << '\n';
      }
    }
    std::cout << "PASS ownership, pre-cancel, hash, shape, real CSV and image inference\n";
    return 0;
  } catch (const Failure& failure) {
    std::cerr << "FAIL " << failure.code << '\n'; return 1;
  } catch (...) { std::cerr << "FAIL unexpected\n"; return 1; }
}
