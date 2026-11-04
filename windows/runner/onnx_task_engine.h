#pragma once

#include <atomic>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace vitalis::tasks {
struct Failure { std::string code; };
struct Control {
  void Cancel();
  void Check() const;
  std::atomic<bool> cancelled{false};
  std::mutex mutex;
  void* run_options = nullptr;
};
struct ImageSpec {
  std::string layout;
  double scale = 1;
  std::vector<double> mean, deviation;
};
struct Request {
  std::filesystem::path root;
  std::string model_id, package_id, input_id, hash, input_name, kind;
  std::vector<int64_t> shape;
  std::vector<float> values;
  std::vector<std::string> outputs;
  ImageSpec image;
};
struct Output {
  std::string name;
  std::vector<int64_t> shape;
  std::vector<float> values;
};
uint64_t AllocationBudget();
std::filesystem::path OwnedInput(const std::filesystem::path& root,
                                const std::string& id);
std::vector<Output> Run(const Request& request, Control& control);
}  // namespace vitalis::tasks
